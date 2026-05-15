import AVFoundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var coordinator: GuidedCaptureCoordinator

    private let accentGreen = Color(red: 0.58, green: 0.96, blue: 0.39)
    private let glassBlack = Color.black.opacity(0.58)

    var body: some View {
        ZStack {
            CameraPreviewView(session: coordinator.cameraSession)
                .ignoresSafeArea()

            if coordinator.state == .unavailable {
                unavailableOverlay
            } else {
                captureOverlay
            }
        }
        .background(Color.black)
        .onAppear {
            coordinator.startPreview()
        }
    }

    private var captureOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [.black.opacity(0.42), .clear, .black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                targetNominationLayer(size: proxy.size)

                VStack(spacing: 0) {
                    topGuidanceCard
                        .padding(.top, 28)
                    Spacer()
                    stabilityCard
                        .padding(.bottom, 28)
                    captureControls
                    bottomGuidanceCard
                        .padding(.top, 20)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
    }

    private func targetNominationLayer(size: CGSize) -> some View {
        ZStack {
            CrosshairView()
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                .ignoresSafeArea()

            let box = coordinator.trackingBox ?? CGRect(x: 0.28, y: 0.36, width: 0.44, height: 0.26)

            VStack(spacing: 8) {
                Image(systemName: coordinator.state == .complete ? "checkmark" : "chevron.up")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(accentGreen)
                Text(targetHint)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundColor(accentGreen)
            }
            .position(x: box.midX * size.width, y: max(92, box.minY * size.height - 48))

            BoundingBoxView()
                .stroke(accentGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: box.width * size.width, height: box.height * size.height)
                .position(x: box.midX * size.width, y: box.midY * size.height)
                .shadow(color: accentGreen.opacity(0.74), radius: 12)
                .animation(.easeInOut(duration: 0.18), value: box)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    let normalized = CGPoint(
                        x: value.location.x / max(size.width, 1),
                        y: value.location.y / max(size.height, 1)
                    )
                    coordinator.nominateTarget(at: normalized)
                }
        )
    }

    private var topGuidanceCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(accentGreen.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 58, height: 58)
                ReticleView()
                    .stroke(accentGreen, lineWidth: 2)
                    .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TRACK THE OBJECT")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(.white)
                Text("Keep the object in the box")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer(minLength: 10)

            Image(systemName: "info.circle")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(glassBlack)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var stabilityCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)

                Text("STABILITY")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))

                Spacer()

                Text(stabilityLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(accentGreen)
            }

            HStack(spacing: 7) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(index < filledStabilitySegments ? accentGreen : Color.white.opacity(0.12))
                        .frame(height: 8)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(glassBlack)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: 620)
    }

    private var captureControls: some View {
        HStack(alignment: .center) {
            quietControl(icon: "mic.slash.fill", label: "AUDIO")

            Spacer()

            VStack(spacing: 8) {
                Button(action: primaryCaptureAction) {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 5)
                            .frame(width: 92, height: 92)
                        Circle()
                            .fill(primaryButtonColor)
                            .frame(width: 54, height: 54)
                    }
                }
                .disabled(!coordinator.canStartTracking && !coordinator.canCompleteTracking)

                HStack(spacing: 8) {
                    Circle()
                        .fill(coordinator.state == .tracking ? Color.red : accentGreen)
                        .frame(width: 10, height: 10)
                    Text(elapsedText)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            }

            Spacer()

            quietControl(icon: "bolt.slash.fill", label: "LIGHT")
        }
        .padding(.horizontal, 4)
    }

    private var bottomGuidanceCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentGreen)
                    .frame(width: 58, height: 58)
                Image(systemName: bottomIcon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(bottomTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(0.4)
                    .foregroundColor(.white)
                Text(bottomMessage)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Button(action: {
                coordinator.cancelTracking()
            }) {
                Text(coordinator.state == .tracking ? "CANCEL" : "RESET")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.68))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private var unavailableOverlay: some View {
        VStack(spacing: 18) {
            Text("Camera unavailable")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(coordinator.errorText ?? "DroneWatch needs camera access for guided capture.")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.78))
            Button("Try Again") {
                coordinator.startPreview()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentGreen)
        }
        .foregroundColor(.white)
        .padding(24)
        .background(glassBlack)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(22)
    }

    private var targetHint: String {
        switch coordinator.state {
        case .complete:
            return "CAPTURED"
        case .tracking:
            return "KEEP STEADY"
        default:
            return "TAP TARGET"
        }
    }

    private var stabilityLabel: String {
        if coordinator.state == .complete {
            return "DONE"
        }
        if coordinator.stabilityScore >= 0.72 || coordinator.progress >= 0.45 {
            return "GOOD"
        }
        return "READY"
    }

    private var filledStabilitySegments: Int {
        let value = max(coordinator.progress, coordinator.stabilityScore)
        return min(6, max(1, Int((value * 6).rounded())))
    }

    private var primaryButtonColor: Color {
        switch coordinator.state {
        case .tracking:
            return Color.red
        case .complete:
            return accentGreen
        default:
            return Color.red.opacity(0.92)
        }
    }

    private var elapsedText: String {
        let minutes = coordinator.elapsedSeconds / 60
        let seconds = coordinator.elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var bottomIcon: String {
        coordinator.state == .complete ? "checkmark" : "checkmark"
    }

    private var bottomTitle: String {
        switch coordinator.state {
        case .complete:
            return "PACKAGE READY"
        case .tracking:
            return "GOOD TRACKING"
        default:
            return "READY TO TRACK"
        }
    }

    private var bottomMessage: String {
        switch coordinator.state {
        case .complete:
            return "Observation evidence has been captured."
        case .tracking:
            return "Keep tracking for a few more seconds."
        default:
            return "Tap the object, then start tracking."
        }
    }

    private func primaryCaptureAction() {
        if coordinator.canCompleteTracking {
            coordinator.completeTracking()
        } else {
            coordinator.startTracking()
        }
    }

    private func quietControl(icon: String, label: String) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.38))
                    .frame(width: 66, height: 66)
                    .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.86))
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CrosshairView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        path.move(to: CGPoint(x: rect.minX, y: center.y))
        path.addLine(to: CGPoint(x: center.x - 120, y: center.y))
        path.move(to: CGPoint(x: center.x + 120, y: center.y))
        path.addLine(to: CGPoint(x: rect.maxX, y: center.y))

        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addLine(to: CGPoint(x: center.x, y: center.y - 90))
        path.move(to: CGPoint(x: center.x, y: center.y + 90))
        path.addLine(to: CGPoint(x: center.x, y: rect.maxY))

        return path
    }
}

struct ReticleView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addEllipse(in: rect.insetBy(dx: 9, dy: 9))
        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.38, dy: rect.height * 0.38))
        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addLine(to: CGPoint(x: center.x, y: rect.minY + 11))
        path.move(to: CGPoint(x: center.x, y: rect.maxY - 11))
        path.addLine(to: CGPoint(x: center.x, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: center.y))
        path.addLine(to: CGPoint(x: rect.minX + 11, y: center.y))
        path.move(to: CGPoint(x: rect.maxX - 11, y: center.y))
        path.addLine(to: CGPoint(x: rect.maxX, y: center.y))
        return path
    }
}

struct BoundingBoxView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = min(rect.width, rect.height) * 0.18
        let tick = min(rect.width, rect.height) * 0.035

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 18))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 18, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 18, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 18), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 18))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 18, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 18, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 18), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - corner))

        path.move(to: CGPoint(x: rect.midX - tick, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + tick, y: rect.minY))
        path.move(to: CGPoint(x: rect.midX - tick, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + tick, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - tick))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + tick))
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY - tick))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + tick))

        return path
    }
}
