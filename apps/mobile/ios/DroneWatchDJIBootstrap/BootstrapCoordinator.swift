import AVFoundation
import Combine
import Foundation

enum GuidedCaptureState: String {
    case previewStarting = "preview_starting"
    case ready = "ready"
    case tracking = "tracking"
    case complete = "complete"
    case unavailable = "unavailable"
}

final class GuidedCaptureCoordinator: NSObject, ObservableObject {
    @Published private(set) var state: GuidedCaptureState = .previewStarting
    @Published private(set) var guidanceText = "Starting camera..."
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var progress = 0.0
    @Published private(set) var qualityLabel = "Not started"
    @Published private(set) var stabilityScore = 0.0
    @Published private(set) var trackingBox: CGRect?
    @Published private(set) var observationPackagePreview = ""
    @Published private(set) var errorText: String?

    let cameraSession = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "dronewatch.guided-capture.camera")
    private var cameraConfigured = false
    private var captureStartedAt: Date?
    private var captureEndedAt: Date?
    private var timer: Timer?
    private var targetCenter = CGPoint(x: 0.5, y: 0.5)

    var canStartTracking: Bool {
        state == .ready || state == .complete
    }

    var canCompleteTracking: Bool {
        state == .tracking
    }

    func startPreview() {
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
        trackingBox = box(around: targetCenter)

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
        stabilityScore = 0.72
        observationPackagePreview = ""
        trackingBox = box(around: targetCenter)
        state = .tracking
        guidanceText = "Keep the object inside the box."

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

        let drift = sin(elapsed * 1.7) * 0.015
        let verticalDrift = cos(elapsed * 1.2) * 0.01
        trackingBox = box(around: CGPoint(x: targetCenter.x + drift, y: targetCenter.y + verticalDrift))

        stabilityScore = max(0.45, min(0.94, 0.72 + (elapsed / 30)))

        if elapsed >= 10 {
            qualityLabel = "Strong"
            guidanceText = "Strong observation. You can finish now."
        } else if elapsed >= 6 {
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

    private func makeObservationPackagePreview() -> String {
        let startedAt = captureStartedAt ?? Date()
        let endedAt = captureEndedAt ?? Date()
        let durationMs = max(0, Int(endedAt.timeIntervalSince(startedAt) * 1000))
        let continuityScore = min(0.95, max(0.35, progress * stabilityScore))
        let qualityScore = min(0.95, (progress * 0.55) + (stabilityScore * 0.35) + 0.05)
        let tier = qualityTier(for: qualityScore)

        let package: [String: Any] = [
            "schemaVersion": "observation_package.v1",
            "sourceType": "civilian_report",
            "packageKind": "observation_package",
            "captureSession": [
                "captureMode": "guided_camera",
                "startedAt": isoString(startedAt),
                "endedAt": isoString(endedAt),
                "appPlatform": "ios"
            ],
            "evidence": [
                "tracking": [
                    "trackingStatus": "tracked",
                    "durationMs": durationMs,
                    "frameCount": max(1, durationMs / 33),
                    "continuityScore": rounded(continuityScore),
                    "targetLostEvents": [],
                    "reacquisitionEvents": []
                ],
                "motion": [
                    "motionSummary": [
                        "stability": stabilityScore > 0.75 ? "stable" : "some_jitter",
                        "motionSmoothnessScore": rounded(stabilityScore),
                        "headingStabilityScore": rounded(stabilityScore * 0.9)
                    ]
                ]
            ],
            "derivedEvidence": [
                "qualityScore": rounded(qualityScore),
                "qualityTier": tier,
                "reasonCodes": reasonCodes(for: tier),
                "qualitySignals": [
                    "continuityScore": rounded(continuityScore),
                    "visualConfidence": 0.6,
                    "headingConfidence": rounded(stabilityScore * 0.9),
                    "motionStability": rounded(stabilityScore)
                ]
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
        switch tier {
        case "strong":
            return ["sufficient_continuous_track", "stable_heading", "audio_not_required"]
        case "moderate":
            return ["sufficient_continuous_track", "duration_below_strong", "audio_not_required"]
        default:
            return ["duration_below_strong", "continuity_low", "audio_not_required"]
        }
    }

    private func markUnavailable(_ message: String) {
        state = .unavailable
        guidanceText = "Camera unavailable"
        errorText = message
    }

    private func box(around point: CGPoint) -> CGRect {
        let width = 0.28
        let height = 0.18
        let x = min(max(point.x - width / 2, 0.03), 1 - width - 0.03)
        let y = min(max(point.y - height / 2, 0.08), 1 - height - 0.08)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func clamp(point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0.08), 0.92),
            y: min(max(point.y, 0.12), 0.88)
        )
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
