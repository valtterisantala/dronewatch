import AVFoundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var coordinator: GuidedCaptureCoordinator

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
                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                targetNominationLayer(size: proxy.size)

                VStack(spacing: 0) {
                    header
                    Spacer()
                    captureControls
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
    }

    private func targetNominationLayer(size: CGSize) -> some View {
        ZStack {
            ReticleView()
                .stroke(Color.white.opacity(0.65), lineWidth: 1.5)
                .frame(width: 92, height: 92)

            if let box = coordinator.trackingBox {
                BoundingBoxView()
                    .stroke(boxColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: box.width * size.width, height: box.height * size.height)
                    .position(x: box.midX * size.width, y: box.midY * size.height)
                    .shadow(color: boxColor.opacity(0.8), radius: 10)
                    .animation(.easeInOut(duration: 0.18), value: box)
            }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DroneWatch")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Guided Capture")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                Text(coordinator.qualityLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(boxColor)
                    .clipShape(Capsule())
            }

            Text(coordinator.guidanceText)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Evidence progress")
                    Spacer()
                    Text("\(coordinator.elapsedSeconds)s")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

                ProgressView(value: coordinator.progress)
                    .tint(boxColor)

                HStack {
                    metricPill("State", coordinator.state.rawValue)
                    metricPill("Stability", String(format: "%.0f%%", coordinator.stabilityScore * 100))
                }
            }

            if !coordinator.observationPackagePreview.isEmpty {
                ScrollView {
                    Text(coordinator.observationPackagePreview)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 180)
                .background(.black.opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            HStack(spacing: 12) {
                Button(action: {
                    coordinator.cancelTracking()
                }) {
                    Text("Reset")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button(action: {
                    if coordinator.canCompleteTracking {
                        coordinator.completeTracking()
                    } else {
                        coordinator.startTracking()
                    }
                }) {
                    Text(coordinator.canCompleteTracking ? "Finish Observation" : "Start Tracking")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(boxColor)
                .disabled(!coordinator.canStartTracking && !coordinator.canCompleteTracking)
            }
        }
        .padding(16)
        .background(.black.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 24))
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
            .tint(.orange)
        }
        .foregroundColor(.white)
        .padding(24)
    }

    private var boxColor: Color {
        switch coordinator.qualityLabel {
        case "Strong":
            return Color(red: 0.45, green: 0.95, blue: 0.56)
        case "Moderate":
            return Color(red: 1.0, green: 0.78, blue: 0.35)
        case "Weak":
            return Color(red: 1.0, green: 0.52, blue: 0.35)
        default:
            return Color(red: 0.55, green: 0.85, blue: 1.0)
        }
    }

    private func metricPill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundColor(.white.opacity(0.58))
            Text(value)
                .foregroundColor(.white)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.12))
        .clipShape(Capsule())
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

struct ReticleView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addEllipse(in: rect.insetBy(dx: 16, dy: 16))
        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addLine(to: CGPoint(x: center.x, y: rect.minY + 22))
        path.move(to: CGPoint(x: center.x, y: rect.maxY - 22))
        path.addLine(to: CGPoint(x: center.x, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: center.y))
        path.addLine(to: CGPoint(x: rect.minX + 22, y: center.y))
        path.move(to: CGPoint(x: rect.maxX - 22, y: center.y))
        path.addLine(to: CGPoint(x: rect.maxX, y: center.y))
        return path
    }
}

struct BoundingBoxView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = min(rect.width, rect.height) * 0.22

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - corner))

        return path
    }
}
