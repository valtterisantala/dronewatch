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

enum TrackingPhase: String {
    case ready
    case nominated
    case acquiring
    case tracking
    case recovering
    case lost
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

private struct TargetCandidate {
    let box: CGRect
    let score: Double
    let scoreReasons: [String]
    let source: String
}

private struct ReacquisitionAttempt {
    let timestamp: Date
    let searchBox: CGRect
    let candidateCount: Int
    let acceptedCandidate: Bool
}

private struct ReacquisitionEvent {
    let timestamp: Date
    let reason: String
    let durationMs: Int
}

private struct CameraZoomSample {
    let timestamp: Date
    let effectiveZoomFactor: Double
    let requestedZoomFactor: Double
    let lensClass: String
    let digitalZoomFactor: Double
    let digitalFallback: Bool
    let preset: String?
}

final class GuidedCaptureCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var state: GuidedCaptureState = .previewStarting
    @Published private(set) var guidanceText = "Starting camera..."
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var progress = 0.0
    @Published private(set) var qualityLabel = "Not started"
    @Published private(set) var stabilityScore = 0.0
    @Published private(set) var trackingPhase: TrackingPhase = .ready
    @Published private(set) var trackingBox: CGRect?
    @Published private(set) var trackingConfidence = 0.0
    @Published private(set) var zoomFactor = 1.0
    @Published private(set) var maxZoomFactor = 4.0
    @Published private(set) var activeLensClass = "wide"
    @Published private(set) var availableZoomPresets: [Double] = [1, 2, 4]
    @Published private(set) var observationPackagePreview = ""
    @Published private(set) var errorText: String?

    let cameraSession = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "dronewatch.guided-capture.camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let locationManager = CLLocationManager()
    private var cameraConfigured = false
    private var activeCameraInput: AVCaptureDeviceInput?
    private var activeCameraDevice: AVCaptureDevice?
    private var availableCameras: [CameraLens: AVCaptureDevice] = [:]
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
    private var reacquisitionAttempts: [ReacquisitionAttempt] = []
    private var reacquisitionEvents: [ReacquisitionEvent] = []
    private var trackingFrameCount = 0
    private var lastTraceSampleAt: Date?
    private var lastTrackingUpdateAt: Date?
    private var recoveryStartedAt: Date?
    private var lastRecoveryAttemptAt: Date?
    private var latestSaliencyBoxes: [CGRect] = []
    private var lastSaliencyAnalysisAt: Date?
    private var isRunningSaliencyAnalysis = false
    private var consecutiveLowConfidenceFrames = 0
    private var zoomTrace: [CameraZoomSample] = []
    private var lensSwitchCount = 0
    private var lastZoomSampleAt: Date?
    private var lastLensSwitchAt: Date?
    private var requestedZoomFactor = 1.0

    private enum CameraLens: String {
        case wide
        case telephoto
    }

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

    func setZoomFactor(_ factor: Double) {
        applyZoom(factor: factor, preset: nil)
    }

    func setZoomPreset(_ factor: Double) {
        applyZoom(factor: factor, preset: "\(formatZoom(factor))x")
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

        if state == .targetLost || state == .complete {
            resetTrackingRuntime()
            state = .ready
        }

        let candidates = targetCandidates(around: targetCenter, source: "tap")
        let selectedCandidate = bestCandidate(from: candidates, tapPoint: targetCenter)
        let selectedBox = selectedCandidate.box

        trackingBox = selectedBox
        trackingConfidence = max(0.34, min(0.72, selectedCandidate.score))
        trackingPhase = .nominated
        prepareVisionTracker(for: selectedBox)
        let selectedReasons = selectedCandidate.scoreReasons.joined(separator: ",")
        trackingDebug(
            "lock tap=\(normalizedPoint.debugDescription) box=\(selectedBox.debugDescription) score=\(rounded(selectedCandidate.score)) source=\(selectedCandidate.source) reasons=\(selectedReasons)"
        )

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
        recordCurrentZoomSampleIfNeeded(preset: nil)
        state = .tracking
        trackingPhase = .acquiring
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
        trackingPhase = .ready
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
        trackingPhase = .ready
        resetTrackingRuntime()
        resetCameraEvidence()
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

                self.discoverAvailableCameras()
                guard let camera = self.availableCameras[.wide] else {
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
                        self.activeCameraInput = input
                        self.activeCameraDevice = camera
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
                    self.updateZoomCapabilities(for: camera)
                    self.applyZoomToActiveDevice(requestedFactor: self.requestedZoomFactor, preset: "1x", shouldRecord: false)
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
                self.trackingPhase = .ready
                self.guidanceText = "Point at a flying object and tap to nominate it."
                self.qualityLabel = "Not started"
                self.errorText = nil
            }
        }
    }

    private func discoverAvailableCameras() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )

        var cameras: [CameraLens: AVCaptureDevice] = [:]
        for device in discovery.devices {
            switch device.deviceType {
            case .builtInTelephotoCamera:
                cameras[.telephoto] = device
            case .builtInWideAngleCamera:
                cameras[.wide] = device
            default:
                break
            }
        }

        if cameras[.wide] == nil,
           let fallback = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            cameras[.wide] = fallback
        }

        availableCameras = cameras
    }

    private func applyZoom(factor: Double, preset: String?) {
        let requestedFactor = max(1, min(factor, maxZoomFactor))
        requestedZoomFactor = requestedFactor

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard self.cameraConfigured else {
                DispatchQueue.main.async {
                    self.zoomFactor = requestedFactor
                }
                return
            }

            self.applyZoomToActiveDevice(requestedFactor: requestedFactor, preset: preset, shouldRecord: true)
        }
    }

    private func applyZoomToActiveDevice(requestedFactor: Double, preset: String?, shouldRecord: Bool) {
        discoverAvailableCameras()
        let targetLens = preferredLens(for: requestedFactor)
        let didSwitchLens = switchCameraIfNeeded(to: targetLens)

        guard let device = activeCameraDevice else {
            return
        }

        updateZoomCapabilities(for: device)

        let lensBase = baseZoomFactor(for: targetLens)
        let digitalZoom = max(1, requestedFactor / lensBase)
        let clampedDigitalZoom = min(max(1, digitalZoom), device.activeFormat.videoMaxZoomFactor)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedDigitalZoom
            device.unlockForConfiguration()
        } catch {
            // Zoom is helpful, but capture can continue at the current camera zoom.
        }

        if didSwitchLens, let box = trackingBox {
            prepareVisionTrackerOnSessionQueue(for: box)
        }

        let effectiveZoom = rounded(lensBase * clampedDigitalZoom)
        let lensClass = targetLens.rawValue
        let usesDigitalFallback = targetLens == .wide && requestedFactor >= telephotoEntryThreshold
        let sample = CameraZoomSample(
            timestamp: Date(),
            effectiveZoomFactor: effectiveZoom,
            requestedZoomFactor: rounded(requestedFactor),
            lensClass: lensClass,
            digitalZoomFactor: rounded(clampedDigitalZoom),
            digitalFallback: usesDigitalFallback,
            preset: preset
        )

        if shouldRecord && shouldRecordZoomSample(sample) {
            zoomTrace.append(sample)
            lastZoomSampleAt = sample.timestamp
        }

        DispatchQueue.main.async {
            self.zoomFactor = effectiveZoom
            self.activeLensClass = lensClass
        }
    }

    private var telephotoEntryThreshold: Double {
        1.85
    }

    private var telephotoExitThreshold: Double {
        1.45
    }

    private func preferredLens(for requestedFactor: Double) -> CameraLens {
        guard availableCameras[.telephoto] != nil else {
            return .wide
        }

        if activeLens() == .telephoto {
            return requestedFactor <= telephotoExitThreshold ? .wide : .telephoto
        }

        return requestedFactor >= telephotoEntryThreshold ? .telephoto : .wide
    }

    private func activeLens() -> CameraLens {
        activeCameraDevice?.deviceType == .builtInTelephotoCamera ? .telephoto : .wide
    }

    private func switchCameraIfNeeded(to lens: CameraLens) -> Bool {
        guard activeLens() != lens,
              let newCamera = availableCameras[lens],
              Date().timeIntervalSince(lastLensSwitchAt ?? .distantPast) > 0.35 else {
            return false
        }

        do {
            let newInput = try AVCaptureDeviceInput(device: newCamera)
            cameraSession.beginConfiguration()
            let oldInput = activeCameraInput
            if let oldInput {
                cameraSession.removeInput(oldInput)
            }
            if cameraSession.canAddInput(newInput) {
                cameraSession.addInput(newInput)
                activeCameraInput = newInput
                activeCameraDevice = newCamera
                lensSwitchCount += 1
                lastLensSwitchAt = Date()
            } else if let oldInput, cameraSession.canAddInput(oldInput) {
                cameraSession.addInput(oldInput)
            }
            cameraSession.commitConfiguration()
            return activeCameraDevice === newCamera
        } catch {
            return false
        }
    }

    private func updateZoomCapabilities(for device: AVCaptureDevice) {
        let wideMax = availableCameras[.wide]?.activeFormat.videoMaxZoomFactor ?? device.activeFormat.videoMaxZoomFactor
        let teleMax = availableCameras[.telephoto]?.activeFormat.videoMaxZoomFactor ?? 1
        let effectiveMax = max(4, min(8, max(wideMax, baseZoomFactor(for: .telephoto) * teleMax)))
        let presets = [1.0, 2.0, 4.0].filter { $0 <= effectiveMax + 0.01 }

        DispatchQueue.main.async {
            self.maxZoomFactor = effectiveMax
            self.availableZoomPresets = presets.isEmpty ? [1.0] : presets
        }
    }

    private func baseZoomFactor(for lens: CameraLens) -> Double {
        switch lens {
        case .wide:
            return 1
        case .telephoto:
            return 2
        }
    }

    private func shouldRecordZoomSample(_ sample: CameraZoomSample) -> Bool {
        guard let last = zoomTrace.last else {
            return true
        }
        if last.lensClass != sample.lensClass || last.preset != sample.preset {
            return true
        }
        if abs(last.effectiveZoomFactor - sample.effectiveZoomFactor) >= 0.08 {
            return true
        }
        guard let lastZoomSampleAt else {
            return true
        }
        return sample.timestamp.timeIntervalSince(lastZoomSampleAt) >= 1.0
    }

    private func recordCurrentZoomSampleIfNeeded(preset: String?) {
        let sample = CameraZoomSample(
            timestamp: Date(),
            effectiveZoomFactor: rounded(zoomFactor),
            requestedZoomFactor: rounded(requestedZoomFactor),
            lensClass: activeLensClass,
            digitalZoomFactor: rounded(Double(activeCameraDevice?.videoZoomFactor ?? 1)),
            digitalFallback: activeLens() == .wide && requestedZoomFactor >= telephotoEntryThreshold,
            preset: preset
        )

        if shouldRecordZoomSample(sample) {
            zoomTrace.append(sample)
            lastZoomSampleAt = sample.timestamp
        }
    }

    private func resetCameraEvidence() {
        zoomTrace = []
        lensSwitchCount = 0
        lastZoomSampleAt = nil
    }

    private func tickTracking() {
        guard let captureStartedAt else {
            return
        }

        let elapsed = Date().timeIntervalSince(captureStartedAt)
        elapsedSeconds = Int(elapsed)
        progress = min(1, elapsed / 10)

        if let lastTrackingUpdateAt, Date().timeIntervalSince(lastTrackingUpdateAt) > 1.2 {
            if trackingPhase == .recovering,
               Date().timeIntervalSince(recoveryStartedAt ?? lastTrackingUpdateAt) > 2.0 {
                markTargetLost(reason: "tracker_uncertain")
            } else {
                beginQuietRecovery(reason: "tracker_uncertain")
            }
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
        maybeUpdatePreTapSaliency(from: sampleBuffer)

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
                    self?.handleTrackingFailure(reason: "tracker_uncertain")
                }
            }
            return
        }

        guard let observation = trackingRequest.results?.first as? VNDetectedObjectObservation else {
            if state == .tracking {
                DispatchQueue.main.async { [weak self] in
                    self?.handleTrackingFailure(reason: "tracker_uncertain")
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
                    "reacquisitionEvents": serializedReacquisitionEvents(),
                    "boundingBoxTrace": boundingBoxTrace(startedAt: startedAt, endedAt: endedAt)
                ],
                "motion": motion,
                "camera": cameraEvidence()
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
                    "hasCameraZoomTrace": !zoomTrace.isEmpty,
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
        sessionQueue.async { [weak self] in
            self?.prepareVisionTrackerOnSessionQueue(for: displayBox)
        }
    }

    private func prepareVisionTrackerOnSessionQueue(for displayBox: CGRect) {
        let clampedBox = clamp(box: displayBox)
        let observation = VNDetectedObjectObservation(boundingBox: visionBox(fromDisplayBox: clampedBox))
        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
        request.trackingLevel = .accurate
        sequenceRequestHandler = VNSequenceRequestHandler()
        trackingRequest = request
    }

    private func applyTrackingUpdate(box: CGRect, confidence: Double, timestamp: Date) {
        guard state == .ready || state == .tracking else {
            return
        }

        let clampedBox = clamp(box: box)
        let usefulBox = isUseful(box: clampedBox)
        trackingBox = clampedBox
        targetCenter = CGPoint(x: clampedBox.midX, y: clampedBox.midY)
        trackingConfidence = max(0, min(1, confidence))
        lastTrackingUpdateAt = timestamp
        trackingFrameCount += 1

        if state == .ready {
            trackingPhase = trackingConfidence >= 0.24 && usefulBox ? .nominated : .acquiring
            return
        }

        if state == .tracking {
            if shouldRecordTraceSample(at: timestamp) {
                trackingTrace.append(TrackingTraceSample(timestamp: timestamp, box: clampedBox, confidence: trackingConfidence))
                lastTraceSampleAt = timestamp
            }

            if trackingConfidence < 0.18 || !usefulBox {
                consecutiveLowConfidenceFrames += 1
            } else {
                if trackingPhase == .recovering {
                    recordReacquisitionSuccess(reason: "tracker_uncertain")
                }
                trackingPhase = trackingConfidence < 0.32 ? .acquiring : .tracking
                recoveryStartedAt = nil
                lastRecoveryAttemptAt = nil
                consecutiveLowConfidenceFrames = 0
            }

            if consecutiveLowConfidenceFrames >= 2 {
                beginQuietRecovery(reason: usefulBox ? "tracker_uncertain" : "out_of_frame")
            }

            if consecutiveLowConfidenceFrames >= 8 ||
                (trackingPhase == .recovering && Date().timeIntervalSince(recoveryStartedAt ?? timestamp) > 2.0) {
                markTargetLost(reason: usefulBox ? "tracker_uncertain" : "out_of_frame")
            }
        }
    }

    private func handleTrackingFailure(reason: String) {
        guard state == .tracking else {
            return
        }

        consecutiveLowConfidenceFrames += 1
        beginQuietRecovery(reason: reason)
        if consecutiveLowConfidenceFrames >= 8 ||
            (trackingPhase == .recovering && Date().timeIntervalSince(recoveryStartedAt ?? Date()) > 2.0) {
            markTargetLost(reason: reason)
        }
    }

    private func beginQuietRecovery(reason: String) {
        guard state == .tracking else {
            return
        }

        if trackingPhase != .recovering {
            recoveryStartedAt = Date()
            trackingDebug("recovery start reason=\(reason) lastBox=\((trackingBox ?? box(around: targetCenter)).debugDescription)")
        }

        trackingPhase = .recovering
        qualityLabel = "Acquiring"
        guidanceText = "Keep the object in view."
        stabilityScore = max(0.12, min(stabilityScore, 0.35))

        guard Date().timeIntervalSince(lastRecoveryAttemptAt ?? .distantPast) > 0.35 else {
            return
        }

        lastRecoveryAttemptAt = Date()
        let searchBox = recoverySearchBox()
        let candidates = targetCandidates(in: searchBox, source: "local_recovery")
        let selected = bestCandidate(from: candidates, tapPoint: CGPoint(x: searchBox.midX, y: searchBox.midY))
        let acceptedCandidate = selected.score >= 0.38

        reacquisitionAttempts.append(
            ReacquisitionAttempt(
                timestamp: Date(),
                searchBox: searchBox,
                candidateCount: candidates.count,
                acceptedCandidate: acceptedCandidate
            )
        )

        let selectedReasons = selected.scoreReasons.joined(separator: ",")
        trackingDebug(
            "recovery attempt candidates=\(candidates.count) acceptedCandidate=\(acceptedCandidate) score=\(rounded(selected.score)) box=\(selected.box.debugDescription) reasons=\(selectedReasons)"
        )

        guard acceptedCandidate else {
            return
        }

        trackingBox = selected.box
        targetCenter = CGPoint(x: selected.box.midX, y: selected.box.midY)
        trackingConfidence = max(trackingConfidence, min(0.46, selected.score))
        prepareVisionTracker(for: selected.box)
    }

    private func recordReacquisitionSuccess(reason: String) {
        let now = Date()
        let durationMs = max(0, Int(now.timeIntervalSince(recoveryStartedAt ?? now) * 1000))
        reacquisitionEvents.append(ReacquisitionEvent(timestamp: now, reason: reason, durationMs: durationMs))
        trackingPhase = .tracking
        recoveryStartedAt = nil
        lastRecoveryAttemptAt = nil
        consecutiveLowConfidenceFrames = 0
        trackingDebug("recovery success durationMs=\(durationMs) reason=\(reason)")
    }

    private func markTargetLost(reason: String) {
        guard state == .tracking else {
            return
        }

        captureEndedAt = Date()
        timer?.invalidate()
        timer = nil
        state = .targetLost
        trackingPhase = .lost
        qualityLabel = "Lost"
        guidanceText = "Target lost. Find the object and tap it again."
        progress = min(progress, 0.99)
        stabilityScore = 0.08
        trackingConfidence = min(trackingConfidence, 0.12)
        targetLostEvents.append(TargetLostEvent(timestamp: Date(), reason: reason))
        trackingDebug("lost reason=\(reason) lowConfidenceFrames=\(consecutiveLowConfidenceFrames)")
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
        reacquisitionAttempts = []
        reacquisitionEvents = []
        trackingFrameCount = 0
        lastTraceSampleAt = nil
        lastTrackingUpdateAt = nil
        recoveryStartedAt = nil
        lastRecoveryAttemptAt = nil
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

    private func serializedReacquisitionEvents() -> [[String: Any]] {
        reacquisitionEvents.map { event in
            [
                "timestamp": isoString(event.timestamp),
                "reason": event.reason,
                "durationMs": event.durationMs
            ]
        }
    }

    private func targetCandidates(around point: CGPoint, source: String) -> [TargetCandidate] {
        let base = box(around: point)
        let zoomScale = min(1.45, max(0.75, sqrt(requestedZoomFactor) / 1.8))
        let sizes = [0.55, 0.72, 0.9, 1.1].map { factor in
            CGSize(width: base.width * factor / zoomScale, height: base.height * factor / zoomScale)
        }
        let offset = max(0.012, min(0.035, 0.045 / max(1, requestedZoomFactor)))
        let offsets = [
            CGPoint.zero,
            CGPoint(x: -offset, y: 0),
            CGPoint(x: offset, y: 0),
            CGPoint(x: 0, y: -offset),
            CGPoint(x: 0, y: offset)
        ]

        return sizes.flatMap { size in
            offsets.map { offsetPoint in
                let center = clamp(point: CGPoint(x: point.x + offsetPoint.x, y: point.y + offsetPoint.y))
                let rect = clamp(box: CGRect(
                    x: center.x - size.width / 2,
                    y: center.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ))
                return scoreCandidate(rect, tapPoint: point, source: source)
            }
        }
    }

    private func targetCandidates(in searchBox: CGRect, source: String) -> [TargetCandidate] {
        let searchCenter = CGPoint(x: searchBox.midX, y: searchBox.midY)
        var candidates = targetCandidates(around: searchCenter, source: source)

        let localSaliency = latestSaliencyBoxes
            .filter { $0.intersects(searchBox) }
            .map { clamp(box: $0.intersection(searchBox).isNull ? $0 : $0.intersection(searchBox)) }

        candidates.append(contentsOf: localSaliency.map { scoreCandidate($0, tapPoint: searchCenter, source: "saliency_recovery") })
        return candidates
    }

    private func bestCandidate(from candidates: [TargetCandidate], tapPoint: CGPoint) -> TargetCandidate {
        candidates.max { $0.score < $1.score } ??
            scoreCandidate(box(around: tapPoint), tapPoint: tapPoint, source: "fallback")
    }

    private func scoreCandidate(_ candidateBox: CGRect, tapPoint: CGPoint, source: String) -> TargetCandidate {
        let candidate = clamp(box: candidateBox)
        let center = CGPoint(x: candidate.midX, y: candidate.midY)
        let distance = hypot(center.x - tapPoint.x, center.y - tapPoint.y)
        let distanceScore = max(0, 1 - min(1, distance / 0.16))

        let base = box(around: tapPoint)
        let targetArea = base.width * base.height
        let candidateArea = candidate.width * candidate.height
        let sizeDelta = abs(candidateArea - targetArea) / max(targetArea, 0.001)
        let sizeScore = max(0, 1 - min(1, sizeDelta))

        let saliencyOverlap = latestSaliencyBoxes
            .map { intersectionRatio(candidate, $0) }
            .max() ?? 0
        let zoomFitScore = requestedZoomFactor >= 2 ? max(0, 1 - candidateArea / max(targetArea, 0.001)) : 0.5

        var score = 0.22
        score += distanceScore * 0.28
        score += sizeScore * 0.2
        score += min(1, saliencyOverlap * 2.4) * 0.22
        score += zoomFitScore * 0.08

        var reasons = [
            "tap_distance:\(rounded(distanceScore))",
            "roi_size:\(rounded(sizeScore))",
            "zoom_fit:\(rounded(zoomFitScore))"
        ]

        if saliencyOverlap > 0 {
            reasons.append("saliency_overlap:\(rounded(saliencyOverlap))")
        }

        if source.contains("recovery") {
            score += 0.05
            reasons.append("local_recovery")
        }

        return TargetCandidate(
            box: candidate,
            score: max(0, min(1, score)),
            scoreReasons: reasons,
            source: source
        )
    }

    private func recoverySearchBox() -> CGRect {
        let base = trackingBox ?? box(around: targetCenter)
        let expansion: CGFloat = 1.75
        let width = min(0.8, base.width * expansion)
        let height = min(0.8, base.height * expansion)
        return clamp(box: CGRect(
            x: base.midX - width / 2,
            y: base.midY - height / 2,
            width: width,
            height: height
        ))
    }

    private func box(around point: CGPoint) -> CGRect {
        let zoomScale = max(1, sqrt(requestedZoomFactor))
        let width = max(0.12, min(0.26, 0.26 / zoomScale))
        let height = max(0.08, min(0.17, 0.17 / zoomScale))
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

    private func intersectionRatio(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }
        let intersectionArea = intersection.width * intersection.height
        let lhsArea = max(lhs.width * lhs.height, 0.001)
        return Double(max(0, intersectionArea / lhsArea))
    }

    private func maybeUpdatePreTapSaliency(from sampleBuffer: CMSampleBuffer) {
        guard (state == .ready && trackingBox == nil) || trackingPhase == .recovering else {
            return
        }
        guard Date().timeIntervalSince(lastSaliencyAnalysisAt ?? .distantPast) > 1.0,
              !isRunningSaliencyAnalysis else {
            return
        }

        isRunningSaliencyAnalysis = true
        lastSaliencyAnalysisAt = Date()

        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right, options: [:])

        do {
            try handler.perform([request])
            let observations = request.results ?? []
            let boxes = observations
                .flatMap { $0.salientObjects ?? [] }
                .map { self.displayBox(fromVisionBox: $0.boundingBox) }
                .map { self.clamp(box: $0) }

            DispatchQueue.main.async { [weak self] in
                self?.latestSaliencyBoxes = boxes
                self?.isRunningSaliencyAnalysis = false
                if !boxes.isEmpty {
                    self?.trackingDebug("saliency boxes=\(boxes.count)")
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.latestSaliencyBoxes = []
                self?.isRunningSaliencyAnalysis = false
                self?.trackingDebug("saliency unavailable error=\(error.localizedDescription)")
            }
        }
    }

    private func trackingDebug(_ message: String) {
        #if DEBUG
        print("DroneWatch tracking: \(message)")
        #endif
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func formatZoom(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func spatialUncertaintyMeters() -> Double {
        guard let latestLocation, latestLocation.horizontalAccuracy >= 0 else {
            return 1000
        }
        return max(25, rounded(latestLocation.horizontalAccuracy))
    }

    private func cameraEvidence() -> [String: Any] {
        let trace = zoomTrace.isEmpty ? [
            CameraZoomSample(
                timestamp: captureStartedAt ?? Date(),
                effectiveZoomFactor: rounded(zoomFactor),
                requestedZoomFactor: rounded(requestedZoomFactor),
                lensClass: activeLensClass,
                digitalZoomFactor: rounded(Double(activeCameraDevice?.videoZoomFactor ?? 1)),
                digitalFallback: activeLens() == .wide && requestedZoomFactor >= telephotoEntryThreshold,
                preset: nil
            )
        ] : zoomTrace
        let zoomFactors = trace.map { $0.effectiveZoomFactor }

        return [
            "cameraDevice": [
                "position": "back",
                "lensClass": activeLensClass,
                "physicalLensSwitchingSupported": availableCameras[.telephoto] != nil
            ],
            "cameraSummary": [
                "minZoomFactor": rounded(zoomFactors.min() ?? zoomFactor),
                "maxZoomFactor": rounded(zoomFactors.max() ?? zoomFactor),
                "finalZoomFactor": rounded(zoomFactor),
                "lensSwitchCount": lensSwitchCount,
                "usedPhysicalLensSwitching": trace.contains { $0.lensClass == CameraLens.telephoto.rawValue },
                "usedDigitalFallback": trace.contains { $0.digitalFallback }
            ],
            "zoomTrace": trace.map { sample in
                var output: [String: Any] = [
                    "timestamp": isoString(sample.timestamp),
                    "effectiveZoomFactor": rounded(sample.effectiveZoomFactor),
                    "requestedZoomFactor": rounded(sample.requestedZoomFactor),
                    "lensClass": sample.lensClass,
                    "digitalZoomFactor": rounded(sample.digitalZoomFactor),
                    "digitalFallback": sample.digitalFallback
                ]
                if let preset = sample.preset {
                    output["preset"] = preset
                }
                return output
            }
        ]
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
