import AVFoundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var coordinator: GuidedCaptureCoordinator
    @State private var selectedTab: AppTab = .capture

    private enum AppTab: String, CaseIterable {
        case capture
        case map
        case profile

        var title: String {
            switch self {
            case .capture:
                return "Capture"
            case .map:
                return "Map"
            case .profile:
                return "Profile"
            }
        }

        var icon: String {
            switch self {
            case .capture:
                return "viewfinder"
            case .map:
                return "map"
            case .profile:
                return "person.crop.circle"
            }
        }
    }

    private enum CaptureVisualState {
        case readyToTrack
        case targetNominated
        case tracking
        case almostDone
        case targetLost
        case captureComplete
    }

    private let primaryGreen = Color(red: 0.54, green: 0.95, blue: 0.37)
    private let acquiringYellow = Color(red: 1.0, green: 0.85, blue: 0.29)
    private let lostRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    private let overlayBlack = Color.black.opacity(0.58)
    private let deeperOverlay = Color.black.opacity(0.72)
    private let inactiveBar = Color.white.opacity(0.16)
    private let whitePrimary = Color.white.opacity(0.96)
    private let whiteSecondary = Color.white.opacity(0.72)

    var body: some View {
        Group {
            switch selectedTab {
            case .capture:
                captureScreen
            case .map:
                placeholderScreen(
                    title: "Map",
                    message: "Civilian awareness map will appear here.",
                    icon: "map"
                )
            case .profile:
                placeholderScreen(
                    title: "Profile",
                    message: "Your capture history and preferences will appear here.",
                    icon: "person.crop.circle"
                )
            }
        }
        .background(Color.black)
    }

    private var captureScreen: some View {
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
                    Spacer()
                    stabilityCard
                        .padding(.bottom, 22)
                    captureControls
                    bottomGuidanceCard
                        .padding(.top, 18)
                    bottomNavigationBar
                        .padding(.top, 12)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
        }
    }

    private func placeholderScreen(title: String, message: String, icon: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.04, green: 0.07, blue: 0.08), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(primaryGreen)
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(whitePrimary)
                Text(message)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(whiteSecondary)
                    .padding(.horizontal, 36)

                Spacer()

                bottomNavigationBar
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
            }
        }
    }

    private func targetNominationLayer(size: CGSize) -> some View {
        ZStack {
            CrosshairView()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                .ignoresSafeArea()

            if visualState == .captureComplete {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .stroke(targetAccent, lineWidth: 4)
                            .frame(width: 118, height: 118)
                        Image(systemName: "checkmark")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(targetAccent)
                    }
                    Text(centerHint)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(targetAccent)
                    Text("Good observation captured.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(whitePrimary)
                }
                .position(x: size.width / 2, y: size.height * 0.34)
            } else {
                let box = displayBox

                VStack(spacing: 7) {
                    Image(systemName: visualState == .readyToTrack ? "plus" : "chevron.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(targetAccent)
                    Text(centerHint)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(targetAccent)
                }
                .position(x: box.midX * size.width, y: max(84, box.minY * size.height - 42))

                BoundingBoxView()
                    .stroke(targetAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: box.width * size.width, height: box.height * size.height)
                    .position(x: box.midX * size.width, y: box.midY * size.height)
                    .shadow(color: targetAccent.opacity(0.68), radius: 10)
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

    private var stabilityCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)

                Text("STABILITY")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(whitePrimary)

                Spacer()

                Text(stabilityLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(statusAccent)
            }

            HStack(spacing: 7) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(index < filledStabilitySegments ? statusAccent : inactiveBar)
                        .frame(height: 8)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(overlayBlack)
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
                        .fill(statusAccent)
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
                    .fill(statusAccent)
                    .frame(width: 58, height: 58)
                Image(systemName: bottomIcon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(bottomTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(0.4)
                    .foregroundColor(whitePrimary)
                Text(bottomMessage)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(whiteSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            if let bottomActionTitle {
                Button(action: bottomAction) {
                    Text(bottomActionTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(visualState == .captureComplete ? primaryGreen : whitePrimary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(deeperOverlay)
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32))
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
            .tint(primaryGreen)
        }
        .foregroundColor(.white)
        .padding(24)
        .background(deeperOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(22)
    }

    private var visualState: CaptureVisualState {
        if coordinator.state == .complete {
            return .captureComplete
        }
        if coordinator.state == .tracking && coordinator.stabilityScore < 0.3 {
            return .targetLost
        }
        if coordinator.state == .tracking && coordinator.progress >= 0.78 {
            return .almostDone
        }
        if coordinator.state == .tracking {
            return .tracking
        }
        if coordinator.trackingBox != nil {
            return .targetNominated
        }
        return .readyToTrack
    }

    private var displayBox: CGRect {
        coordinator.trackingBox ?? CGRect(x: 0.29, y: 0.34, width: 0.42, height: 0.25)
    }

    private var targetAccent: Color {
        visualState == .targetLost ? lostRed : primaryGreen
    }

    private var statusAccent: Color {
        switch visualState {
        case .targetNominated:
            return acquiringYellow
        case .targetLost:
            return lostRed
        default:
            return primaryGreen
        }
    }

    private var centerHint: String {
        switch visualState {
        case .readyToTrack:
            return "TAP TARGET"
        case .targetNominated:
            return "HOLD STEADY"
        case .tracking, .almostDone:
            return "KEEP STEADY"
        case .targetLost:
            return "FIND TARGET"
        case .captureComplete:
            return "COMPLETED"
        }
    }

    private var stabilityLabel: String {
        switch visualState {
        case .readyToTrack:
            return "READY"
        case .targetNominated:
            return "ACQUIRING"
        case .targetLost:
            return "POOR"
        case .tracking, .almostDone, .captureComplete:
            return "GOOD"
        }
    }

    private var filledStabilitySegments: Int {
        switch visualState {
        case .readyToTrack:
            return 0
        case .targetNominated:
            return 4
        case .targetLost:
            return 1
        case .almostDone, .captureComplete:
            return 5
        case .tracking:
            return min(5, max(3, Int((coordinator.progress * 6).rounded())))
        }
    }

    private var primaryButtonColor: Color {
        switch visualState {
        case .targetLost:
            return lostRed
        default:
            return primaryGreen
        }
    }

    private var elapsedText: String {
        let minutes = coordinator.elapsedSeconds / 60
        let seconds = coordinator.elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var bottomIcon: String {
        switch visualState {
        case .readyToTrack:
            return "scope"
        case .targetLost:
            return "scope"
        default:
            return "checkmark"
        }
    }

    private var bottomTitle: String {
        switch visualState {
        case .readyToTrack:
            return "READY TO TRACK"
        case .targetNominated:
            return "TRACKING STARTED"
        case .tracking:
            return "GOOD TRACKING"
        case .almostDone:
            return "ALMOST THERE"
        case .targetLost:
            return "TARGET LOST"
        case .captureComplete:
            return "CAPTURE SAVED"
        }
    }

    private var bottomMessage: String {
        switch visualState {
        case .readyToTrack:
            return "Tap the object, then start tracking."
        case .targetNominated:
            return "Keep the object in the box and try to hold steady."
        case .tracking:
            return "Keep tracking for a few more seconds."
        case .almostDone:
            return "Just a little more."
        case .targetLost:
            return "Find the object and put it back in the box."
        case .captureComplete:
            return "You can review your capture or start a new one."
        }
    }

    private var bottomActionTitle: String? {
        switch visualState {
        case .readyToTrack, .targetLost:
            return "RESET"
        case .captureComplete:
            return "VIEW"
        default:
            return nil
        }
    }

    private func bottomAction() {
        if visualState == .captureComplete {
            return
        }
        coordinator.cancelTracking()
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
                    .foregroundColor(whitePrimary)
            }
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(whitePrimary)
        }
    }

    private var bottomNavigationBar: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(selectedTab == tab ? primaryGreen : whiteSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(selectedTab == tab ? Color.white.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background((selectedTab == .capture && coordinator.state == .tracking) ? Color.black.opacity(0.42) : overlayBlack)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .opacity(selectedTab == .capture && coordinator.state == .tracking ? 0.76 : 1)
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
