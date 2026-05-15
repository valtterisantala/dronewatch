import AVFoundation
import Combine
import CoreLocation
import Foundation
import Vision

enum GuidedCaptureState: String {
    case previewStarting = "preview_starting"
    case ready = "ready"
    case tracking = "tracking"
    case targetLost = "target_lost"
    case complete = "complete"
    case unavailable = "unavailable"
}

private struct TrackingTraceSample {
    let timestamp: Date
    let box: CGRect
    let confidence: Double
}

private struct TargetLostEvent {
    let timestamp: Date
    let reason: String
}

final class GuidedCaptureCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var state: GuidedCaptureState = .previewStarting
    @Published private(set) var guidanceText = "Starting camera..."
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var progress = 0.0
    @Published private(set) var qualityLabel = "Not started"
    @Published private(set) var stabilityScore = 0.0
    @Published private(set) var trackingBox: CGRect?
    @Published private(set) var trackingConfidence = 0.0
    @Published private(set) var observationPackagePreview = ""
    @Published private(set) var errorText: String?

    let cameraSession = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "dronewatch.guided-capture.camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let locationManager = CLLocationManager()
    private var cameraConfigured = false
    private var captureStartedAt: Date?
    private var captureEndedAt: Date?
    private var timer: Timer?
    private var targetCenter = CGPoint(x: 0.5, y: 0.5)
    private var latestLocation: CLLocation?
    private var latestHeading: CLHeading?
    private var sequenceRequestHandler = VNSequenceRequestHandler()
    private var trackingRequest: VNTrackObjectRequest?
    private var trackingTrace: [TrackingTraceSample] = []
    private var targetLostEvents: [TargetLostEvent] = []
    private var trackingFrameCount = 0
    private var lastTraceSampleAt: Date?
    private var lastTrackingUpdateAt: Date?
    private var consecutiveLowConfidenceFrames = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var canStartTracking: Bool {
        (state == .ready && trackingBox != nil) || state == .complete
    }

    var canCompleteTracking: Bool {
        state == .tracking
    }

    func startPreview() {
        startLocationCapture()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStartCamera()
                    } else {
                        self?.markUnavailable("Camera permission is required for guided capture.")
                    }
                }
            }
        case .denied, .restricted:
            markUnavailable("Camera permission is required for guided capture.")
        @unknown default:
            markUnavailable("Camera permission state is unknown.")
        }
    }

    func nominateTarget(at normalizedPoint: CGPoint) {
        targetCenter = clamp(point: normalizedPoint)
        let selectedBox = box(around: targetCenter)
        trackingBox = selectedBox
        trackingConfidence = 0.35
        prepareVisionTracker(for: selectedBox)

        if state == .targetLost || state == .complete {
            resetTrackingRuntime()
            state = .ready
        }

        if state == .ready || state == .complete {
            guidanceText = "Target nominated. Start tracking when the object is inside the box."
        }
    }

    func startTracking() {
        guard state == .ready || state == .complete else {
            return
        }

        captureStartedAt = Date()
        captureEndedAt = nil
        elapsedSeconds = 0
        progress = 0
        qualityLabel = "Weak"
        stabilityScore = max(0.35, trackingConfidence)
        observationPackagePreview = ""
        let selectedBox = trackingBox ?? box(around: targetCenter)
        trackingBox = selectedBox
        prepareVisionTracker(for: selectedBox)
        resetTrackingEvidence()
        state = .tracking
        guidanceText = "Keep the object inside the box."
        startLocationCapture()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tickTracking()
        }
    }

    func completeTracking() {
        guard state == .tracking else {
            return
        }

        captureEndedAt = Date()
        timer?.invalidate()
        timer = nil
        state = .complete
        guidanceText = "Observation package generated locally."
        progress = min(1, progress)
        observationPackagePreview = makeObservationPackagePreview()
    }

    func cancelTracking() {
        timer?.invalidate()
        timer = nil
        captureStartedAt = nil
        captureEndedAt = nil
        elapsedSeconds = 0
        progress = 0
        qualityLabel = "Not started"
        stabilityScore = 0
        observationPackagePreview = ""
        trackingBox = nil
        trackingConfidence = 0
        resetTrackingRuntime()
        state = cameraConfigured ? .ready : .previewStarting
        guidanceText = cameraConfigured ? "Point at a flying object and tap to nominate it." : "Starting camera..."
    }

    private func configureAndStartCamera() {
        state = .previewStarting
        guidanceText = "Preparing camera..."

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if !self.cameraConfigured {
                self.cameraSession.beginConfiguration()
                self.cameraSession.sessionPreset = .high

                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    DispatchQueue.main.async {
                        self.markUnavailable("No back camera is available on this device.")
                    }
                    self.cameraSession.commitConfiguration()
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    if self.cameraSession.canAddInput(input) {
                        self.cameraSession.addInput(input)
                    }

                    self.videoOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                    if self.cameraSession.canAddOutput(self.videoOutput) {
                        self.cameraSession.addOutput(self.videoOutput)
                        if let connection = self.videoOutput.connection(with: .video),
                           connection.isVideoOrientationSupported {
                            connection.videoOrientation = .portrait
                        }
                    }
                    self.cameraConfigured = true
                } catch {
                    DispatchQueue.main.async {
                        self.markUnavailable("Could not start camera: \(error.localizedDescription)")
                    }
                    self.cameraSession.commitConfiguration()
                    return
                }

                self.cameraSession.commitConfiguration()
            }

            if !self.cameraSession.isRunning {
                self.cameraSession.startRunning()
            }

            DispatchQueue.main.async {
                self.state = .ready
                self.guidanceText = "Point at a flying object and tap to nominate it."
                self.qualityLabel = "Not started"
                self.errorText = nil
            }
        }
    }

    private func tickTracking() {
        guard let captureStartedAt else {
            return
        }

        let elapsed = Date().timeIntervalSince(captureStartedAt)
        elapsedSeconds = Int(elapsed)
        progress = min(1, elapsed / 10)

        if let lastTrackingUpdateAt, Date().timeIntervalSince(lastTrackingUpdateAt) > 1.2 {
            markTargetLost(reason: "tracker_uncertain")
            return
        }

        let continuity = continuityScore()
        stabilityScore = max(0.05, min(0.96, (trackingConfidence * 0.72) + (continuity * 0.28)))

        if elapsed >= 10 && stabilityScore >= 0.55 {
            qualityLabel = "Strong"
            guidanceText = "Strong observation. You can finish now."
        } else if elapsed >= 6 && stabilityScore >= 0.45 {
            qualityLabel = "Moderate"
            guidanceText = "Usable evidence. Keep tracking for a stronger package."
        } else if elapsed >= 3 {
            qualityLabel = "Weak"
            guidanceText = "Good start. Keep the object inside the box."
        } else {
            qualityLabel = "Weak"
            guidanceText = "Hold steady. Need a few more seconds."
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let trackingRequest,
              state == .ready || state == .tracking else {
            return
        }

        do {
            try sequenceRequestHandler.perform(
                [trackingRequest],
                on: sampleBuffer,
                orientation: .right
            )
        } catch {
            if state == .tracking {
                DispatchQueue.main.async { [weak self] in
                    self?.markTargetLost(reason: "tracker_uncertain")
                }
            }
            return
        }

        guard let observation = trackingRequest.results?.first as? VNDetectedObjectObservation else {
            if state == .tracking {
                DispatchQueue.main.async { [weak self] in
                    self?.markTargetLost(reason: "tracker_uncertain")
                }
            }
            return
        }

        trackingRequest.inputObservation = observation

        let confidence = Double(observation.confidence)
        let displayBox = displayBox(fromVisionBox: observation.boundingBox)
        let timestamp = Date()

        DispatchQueue.main.async { [weak self] in
            self?.applyTrackingUpdate(box: displayBox, confidence: confidence, timestamp: timestamp)
        }
    }

    private func makeObservationPackagePreview() -> String {
        let startedAt = captureStartedAt ?? Date()
        let endedAt = captureEndedAt ?? Date()
        let durationMs = max(0, Int(endedAt.timeIntervalSince(startedAt) * 1000))
        let continuityScore = continuityScore()
        let visualConfidence = averageTrackingConfidence()
        let trackingStatus = trackingStatus(continuityScore: continuityScore, visualConfidence: visualConfidence)
        let qualityScore = min(0.95, (progress * 0.5) + (stabilityScore * 0.25) + (continuityScore * 0.15) + (visualConfidence * 0.1))
        let tier = qualityTier(for: qualityScore)
        let packageId = "obs_pkg_\(Int(endedAt.timeIntervalSince1970))"
        let captureSessionId = "cap_\(Int(startedAt.timeIntervalSince1970))"
        let headingDegrees = latestHeading?.trueHeading ?? latestHeading?.magneticHeading

        var motion: [String: Any] = [
            "devicePoseTrace": [
                ["timestamp": isoString(startedAt)],
                ["timestamp": isoString(endedAt)]
            ],
            "motionSummary": [
                "stability": stabilityScore > 0.75 ? "stable" : "some_jitter",
                "motionSmoothnessScore": rounded(stabilityScore),
                "headingStabilityScore": rounded(stabilityScore * 0.9)
            ]
        ]

        if let headingDegrees, headingDegrees >= 0 {
            motion["bearingEstimate"] = [
                "degrees": rounded(headingDegrees),
                "source": "device_heading",
                "uncertaintyDegrees": 25
            ]
        }

        var validationJoin: [String: Any] = [
            "timeWindow": [
                "startedAt": isoString(startedAt),
                "endedAt": isoString(endedAt)
            ],
            "spatialUncertaintyMeters": spatialUncertaintyMeters()
        ]

        if let latestLocation {
            validationJoin["observerLocation"] = [
                "lat": latestLocation.coordinate.latitude,
                "lon": latestLocation.coordinate.longitude,
                "accuracyMeters": max(0, latestLocation.horizontalAccuracy),
                "source": "device_gps"
            ]
        }

        if let headingDegrees, headingDegrees >= 0 {
            validationJoin["roughBearingDegrees"] = rounded(headingDegrees)
        }

        let package: [String: Any] = [
            "schemaVersion": "observation_package.v1",
            "packageId": packageId,
            "sourceType": "civilian_report",
            "packageKind": "observation_package",
            "createdAt": isoString(endedAt),
            "captureSession": [
                "captureSessionId": captureSessionId,
                "captureMode": "guided_camera",
                "startedAt": isoString(startedAt),
                "endedAt": isoString(endedAt),
                "appPlatform": "ios",
                "device": [
                    "deviceClass": "iphone",
                    "appVersion": "0.1.0"
                ]
            ],
            "humanReport": [
                "observationType": "unknown_airborne_object",
                "observerConfidence": "medium",
                "countEstimate": 1
            ],
            "evidence": [
                "tracking": [
                    "trackingStatus": trackingStatus,
                    "targetTrackId": "track_local_preview",
                    "trackStartedAt": isoString(startedAt),
                    "trackEndedAt": isoString(endedAt),
                    "durationMs": durationMs,
                    "frameCount": max(trackingFrameCount, durationMs / 33, 1),
                    "continuityScore": rounded(continuityScore),
                    "targetLostEvents": serializedTargetLostEvents(),
                    "reacquisitionEvents": [],
                    "boundingBoxTrace": boundingBoxTrace(startedAt: startedAt, endedAt: endedAt)
                ],
                "motion": motion
            ],
            "derivedEvidence": [
                "qualityScore": rounded(qualityScore),
                "qualityTier": tier,
                "insufficiencyReasons": insufficiencyReasons(for: tier),
                "reasonCodes": reasonCodes(for: tier),
                "qualitySignals": [
                    "continuityScore": rounded(continuityScore),
                    "visualConfidence": rounded(visualConfidence),
                    "headingConfidence": rounded(stabilityScore * 0.9),
                    "motionStability": rounded(stabilityScore)
                ],
                "featureFlags": [
                    "hasBoundingBoxTrace": true,
                    "hasDevicePoseTrace": true,
                    "hasObserverLocation": latestLocation != nil,
                    "hasAudioFeatures": false
                ],
                "mlReadiness": tier == "strong" && trackingStatus == "tracked" ? "ready" : "partial",
                "compactFeatureSummary": [
                    "durationMs": durationMs,
                    "frameCount": max(trackingFrameCount, durationMs / 33, 1),
                    "locationAccuracyMeters": latestLocation.map { max(0, $0.horizontalAccuracy) } ?? spatialUncertaintyMeters()
                ]
            ],
            "validationJoin": validationJoin,
            "privacy": [
                "containsRawMedia": false,
                "retentionPolicy": "short_term_review",
                "locationPrecision": latestLocation == nil ? "none" : "exact"
            ]
        ]

        guard JSONSerialization.isValidJSONObject(package),
              let data = try? JSONSerialization.data(withJSONObject: package, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "Could not render local Observation Package preview."
        }

        return text
    }

    private func qualityTier(for score: Double) -> String {
        if score >= 0.75 {
            return "strong"
        }
        if score >= 0.5 {
            return "moderate"
        }
        if score >= 0.25 {
            return "weak"
        }
        return "insufficient"
    }

    private func reasonCodes(for tier: String) -> [String] {
        var codes: [String]

        switch tier {
        case "strong":
            codes = ["sufficient_continuous_track", "stable_heading", "audio_not_required"]
        case "moderate":
            codes = ["sufficient_continuous_track", "duration_below_strong", "audio_not_required"]
        default:
            codes = ["duration_below_strong", "continuity_low", "audio_not_required"]
        }

        codes.append(latestLocation == nil ? "no_location" : "observer_location_available")
        if !targetLostEvents.isEmpty {
            codes.append("tracking_lost")
        }
        if averageTrackingConfidence() < 0.35 {
            codes.append("low_visual_confidence")
        }
        return codes
    }

    private func insufficiencyReasons(for tier: String) -> [String] {
        switch tier {
        case "strong", "moderate":
            var reasons: [String] = []
            if latestLocation == nil {
                reasons.append("no_location")
            }
            if !targetLostEvents.isEmpty {
                reasons.append("tracking_lost")
            }
            return reasons
        default:
            var reasons = ["tracking_too_short", "continuity_low"]
            if latestLocation == nil {
                reasons.append("no_location")
            }
            if !targetLostEvents.isEmpty {
                reasons.append("tracking_lost")
            }
            if averageTrackingConfidence() < 0.35 {
                reasons.append("low_visual_confidence")
            }
            return reasons
        }
    }

    private func startLocationCapture() {
        guard CLLocationManager.locationServicesEnabled() else {
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startLocationCapture()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        latestLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        latestHeading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location is useful evidence, but the prototype can still generate a package without it.
    }

    private func markUnavailable(_ message: String) {
        state = .unavailable
        guidanceText = "Camera unavailable"
        errorText = message
    }

    private func prepareVisionTracker(for displayBox: CGRect) {
        let clampedBox = clamp(box: displayBox)
        let observation = VNDetectedObjectObservation(boundingBox: visionBox(fromDisplayBox: clampedBox))
        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
        request.trackingLevel = .accurate

        sessionQueue.async { [weak self] in
            self?.sequenceRequestHandler = VNSequenceRequestHandler()
            self?.trackingRequest = request
        }
    }

    private func applyTrackingUpdate(box: CGRect, confidence: Double, timestamp: Date) {
        guard state == .ready || state == .tracking else {
            return
        }

        let clampedBox = clamp(box: box)
        trackingBox = clampedBox
        targetCenter = CGPoint(x: clampedBox.midX, y: clampedBox.midY)
        trackingConfidence = max(0, min(1, confidence))
        lastTrackingUpdateAt = timestamp
        trackingFrameCount += 1

        if state == .tracking {
            if shouldRecordTraceSample(at: timestamp) {
                trackingTrace.append(TrackingTraceSample(timestamp: timestamp, box: clampedBox, confidence: trackingConfidence))
                lastTraceSampleAt = timestamp
            }

            if trackingConfidence < 0.18 || !isUseful(box: clampedBox) {
                consecutiveLowConfidenceFrames += 1
            } else {
                consecutiveLowConfidenceFrames = 0
            }

            if consecutiveLowConfidenceFrames >= 3 {
                markTargetLost(reason: isUseful(box: clampedBox) ? "tracker_uncertain" : "out_of_frame")
            }
        }
    }

    private func markTargetLost(reason: String) {
        guard state == .tracking else {
            return
        }

        captureEndedAt = Date()
        timer?.invalidate()
        timer = nil
        state = .targetLost
        qualityLabel = "Lost"
        guidanceText = "Target lost. Find the object and tap it again."
        progress = min(progress, 0.99)
        stabilityScore = 0.08
        trackingConfidence = min(trackingConfidence, 0.12)
        targetLostEvents.append(TargetLostEvent(timestamp: Date(), reason: reason))
    }

    private func resetTrackingRuntime() {
        timer?.invalidate()
        timer = nil
        captureStartedAt = nil
        captureEndedAt = nil
        resetTrackingEvidence()
    }

    private func resetTrackingEvidence() {
        trackingTrace = []
        targetLostEvents = []
        trackingFrameCount = 0
        lastTraceSampleAt = nil
        lastTrackingUpdateAt = nil
        consecutiveLowConfidenceFrames = 0
    }

    private func shouldRecordTraceSample(at timestamp: Date) -> Bool {
        guard let lastTraceSampleAt else {
            return true
        }
        return timestamp.timeIntervalSince(lastTraceSampleAt) >= 0.2
    }

    private func continuityScore() -> Double {
        guard let captureStartedAt else {
            return trackingConfidence
        }
        let endedAt = captureEndedAt ?? Date()
        let elapsed = max(0.1, endedAt.timeIntervalSince(captureStartedAt))
        let expectedSamples = max(1, Int(elapsed / 0.2))
        let sampleContinuity = min(1, Double(trackingTrace.count) / Double(expectedSamples))
        let lostPenalty = targetLostEvents.isEmpty ? 1.0 : 0.55
        return max(0, min(1, sampleContinuity * lostPenalty))
    }

    private func averageTrackingConfidence() -> Double {
        guard !trackingTrace.isEmpty else {
            return trackingConfidence
        }
        let total = trackingTrace.reduce(0) { $0 + $1.confidence }
        return max(0, min(1, total / Double(trackingTrace.count)))
    }

    private func trackingStatus(continuityScore: Double, visualConfidence: Double) -> String {
        if !targetLostEvents.isEmpty {
            return "lost"
        }
        if continuityScore < 0.5 || visualConfidence < 0.35 {
            return "weak"
        }
        return "tracked"
    }

    private func serializedTargetLostEvents() -> [[String: Any]] {
        targetLostEvents.map { event in
            [
                "timestamp": isoString(event.timestamp),
                "reason": event.reason
            ]
        }
    }

    private func box(around point: CGPoint) -> CGRect {
        let width = 0.44
        let height = 0.26
        let x = min(max(point.x - width / 2, 0.03), 1 - width - 0.03)
        let y = min(max(point.y - height / 2, 0.08), 1 - height - 0.08)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func clamp(box: CGRect) -> CGRect {
        let width = min(max(box.width, 0.06), 0.9)
        let height = min(max(box.height, 0.06), 0.9)
        let x = min(max(box.origin.x, 0), 1 - width)
        let y = min(max(box.origin.y, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func clamp(point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0.08), 0.92),
            y: min(max(point.y, 0.12), 0.88)
        )
    }

    private func visionBox(fromDisplayBox box: CGRect) -> CGRect {
        // Vision uses lower-left normalized coordinates; SwiftUI overlay boxes use top-left.
        CGRect(
            x: box.origin.x,
            y: 1 - box.origin.y - box.height,
            width: box.width,
            height: box.height
        )
    }

    private func displayBox(fromVisionBox box: CGRect) -> CGRect {
        CGRect(
            x: box.origin.x,
            y: 1 - box.origin.y - box.height,
            width: box.width,
            height: box.height
        )
    }

    private func isUseful(box: CGRect) -> Bool {
        box.width > 0.04 &&
            box.height > 0.04 &&
            box.minX >= -0.02 &&
            box.minY >= -0.02 &&
            box.maxX <= 1.02 &&
            box.maxY <= 1.02
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func spatialUncertaintyMeters() -> Double {
        guard let latestLocation, latestLocation.horizontalAccuracy >= 0 else {
            return 1000
        }
        return max(25, rounded(latestLocation.horizontalAccuracy))
    }

    private func boundingBoxTrace(startedAt: Date, endedAt: Date) -> [[String: Any]] {
        if !trackingTrace.isEmpty {
            return trackingTrace.map { sample in
                [
                    "timestamp": isoString(sample.timestamp),
                    "box": normalizedBoxDictionary(sample.box),
                    "confidence": rounded(sample.confidence)
                ]
            }
        }

        let box = trackingBox ?? box(around: targetCenter)
        return [
            [
                "timestamp": isoString(startedAt),
                "box": normalizedBoxDictionary(box),
                "confidence": rounded(max(0.1, trackingConfidence))
            ],
            [
                "timestamp": isoString(endedAt),
                "box": normalizedBoxDictionary(box),
                "confidence": rounded(max(0.1, trackingConfidence))
            ]
        ]
    }

    private func normalizedBoxDictionary(_ box: CGRect) -> [String: Double] {
        [
            "x": rounded(box.origin.x),
            "y": rounded(box.origin.y),
            "width": rounded(box.width),
            "height": rounded(box.height)
        ]
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
