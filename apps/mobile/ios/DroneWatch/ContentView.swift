import AVFoundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var coordinator: GuidedCaptureCoordinator
    @State private var selectedTab: AppTab = .capture
    @State private var previewStateOverride: CaptureVisualState?

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

    private enum CaptureVisualState: CaseIterable {
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
    private let recordRed = Color(red: 1.0, green: 0.18, blue: 0.16)
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
        .preferredColorScheme(.dark)
    }

    private var captureScreen: some View {
        GeometryReader { proxy in
            ZStack {
                CameraPreviewView(session: coordinator.cameraSession)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.18), .clear, .black.opacity(0.58)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                targetNominationLayer(size: proxy.size)

                VStack(spacing: 0) {
                    Spacer()
                    captureBottomStack
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(8, proxy.safeAreaInsets.bottom + 2))
                }
                .ignoresSafeArea()

                if coordinator.state == .unavailable {
                    unavailableOverlay
                }
            }
        }
        .background(Color.black)
        .onAppear {
            coordinator.startPreview()
        }
        .onChange(of: coordinator.state) { _ in
            previewStateOverride = nil
        }
    }

    private var captureBottomStack: some View {
        VStack(spacing: 10) {
            stabilityPill

            captureControls

            bottomStatusCard

            bottomNavigationBar
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

            VStack(spacing: 14) {
                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(primaryGreen)
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundColor(whitePrimary)
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(whiteSecondary)
                    .padding(.horizontal, 36)

                Spacer()

                bottomNavigationBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
    }

    private func targetNominationLayer(size: CGSize) -> some View {
        ZStack {
            CrosshairView()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                .ignoresSafeArea()

            if visualState == .captureComplete {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(targetAccent, lineWidth: 3)
                            .frame(width: 104, height: 104)
                        Image(systemName: "checkmark")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundColor(targetAccent)
                    }
                    Text(centerHint)
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .foregroundColor(targetAccent)
                    Text("Good observation captured.")
                        .font(.footnote)
                        .foregroundColor(whitePrimary)
                }
                .position(x: size.width / 2, y: size.height * 0.34)
            } else {
                let box = displayBox

                VStack(spacing: 6) {
                    Image(systemName: visualState == .readyToTrack ? "plus" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(targetAccent)
                    Text(centerHint)
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .foregroundColor(targetAccent)
                }
                .position(x: box.midX * size.width, y: max(82, box.minY * size.height - 34))

                BoundingBoxView()
                    .stroke(targetAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: box.width * size.width, height: box.height * size.height)
                    .position(x: box.midX * size.width, y: box.midY * size.height)
                    .shadow(color: targetAccent.opacity(0.5), radius: 8)
                    .animation(.easeInOut(duration: 0.18), value: box)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    previewStateOverride = nil
                    let normalized = CGPoint(
                        x: value.location.x / max(size.width, 1),
                        y: value.location.y / max(size.height, 1)
                    )
                    coordinator.nominateTarget(at: normalized)
                }
        )
    }

    private var stabilityPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.subheadline.weight(.medium))
                .foregroundColor(whitePrimary)

            Text("Stability")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(whitePrimary)

            HStack(spacing: 5) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(index < filledStabilitySegments ? statusAccent : inactiveBar)
                        .frame(width: 22, height: 5)
                }
            }
            .padding(.leading, 2)

            Spacer(minLength: 4)

            Text(stabilityLabel)
                .font(.caption.weight(.semibold))
                .foregroundColor(statusAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: 360)
    }

    private var captureControls: some View {
        HStack(alignment: .center) {
            secondaryControl(icon: "mic.slash.fill", label: "Audio")

            Spacer()

            VStack(spacing: 7) {
                Button(action: primaryCaptureAction) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.88), lineWidth: 4)
                            .frame(width: 76, height: 76)
                        if coordinator.canCompleteTracking {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(recordRed)
                                .frame(width: 34, height: 34)
                        } else {
                            Circle()
                                .fill(recordRed)
                                .frame(width: 48, height: 48)
                        }
                    }
                }
                .disabled(!coordinator.canStartTracking && !coordinator.canCompleteTracking)
                .opacity((coordinator.canStartTracking || coordinator.canCompleteTracking) ? 1 : 0.42)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusAccent)
                        .frame(width: 8, height: 8)
                    Text(elapsedText)
                        .font(.callout.monospacedDigit())
                        .foregroundColor(whitePrimary)
                }
            }

            Spacer()

            secondaryControl(icon: "flashlight.off.fill", label: "Light")
        }
        .padding(.horizontal, 8)
    }

    private var bottomStatusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusAccent)
                    .frame(width: 44, height: 44)
                Image(systemName: bottomIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(bottomTitle)
                    .font(.headline)
                    .foregroundColor(whitePrimary)
                Text(bottomMessage)
                    .font(.subheadline)
                    .foregroundColor(whiteSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let bottomActionTitle {
                Button(action: bottomAction) {
                    Text(bottomActionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(visualState == .captureComplete ? primaryGreen : whitePrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onLongPressGesture {
            #if DEBUG
            cyclePreviewState()
            #endif
        }
    }

    private var bottomNavigationBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(selectedTab == tab ? primaryGreen : whiteSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Capsule()
                                .fill(primaryGreen)
                                .frame(width: 18, height: 3)
                                .offset(y: 4)
                        }
                    }
                    .accessibilityLabel(tab.title)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .opacity(selectedTab == .capture && coordinator.state == .tracking ? 0.68 : 1)
    }

    private var unavailableOverlay: some View {
        VStack(spacing: 16) {
            Text("Camera unavailable")
                .font(.title2.weight(.semibold))
            Text(coordinator.errorText ?? "DroneWatch needs camera access for guided capture.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(whiteSecondary)
            Button("Try Again") {
                coordinator.startPreview()
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryGreen)
        }
        .foregroundColor(whitePrimary)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(22)
    }

    private var visualState: CaptureVisualState {
        if let previewStateOverride {
            return previewStateOverride
        }
        if coordinator.state == .complete {
            return .captureComplete
        }
        if coordinator.state == .targetLost {
            return .targetLost
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
        coordinator.trackingBox ?? CGRect(x: 0.31, y: 0.35, width: 0.38, height: 0.23)
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
            return "Tap target"
        case .targetNominated:
            return "Hold steady"
        case .tracking, .almostDone:
            return "Keep steady"
        case .targetLost:
            return "Find target"
        case .captureComplete:
            return "Completed"
        }
    }

    private var stabilityLabel: String {
        switch visualState {
        case .readyToTrack:
            return "Ready"
        case .targetNominated:
            return "Acquiring"
        case .targetLost:
            return "Poor"
        case .tracking, .almostDone, .captureComplete:
            return "Good"
        }
    }

    private var filledStabilitySegments: Int {
        switch visualState {
        case .readyToTrack:
            return 0
        case .targetNominated:
            return 3
        case .targetLost:
            return 1
        case .almostDone, .captureComplete:
            return 5
        case .tracking:
            return min(5, max(2, Int((coordinator.stabilityScore * 6).rounded())))
        }
    }

    private var elapsedText: String {
        let minutes = coordinator.elapsedSeconds / 60
        let seconds = coordinator.elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var bottomIcon: String {
        switch visualState {
        case .readyToTrack, .targetLost:
            return "viewfinder"
        default:
            return "checkmark"
        }
    }

    private var bottomTitle: String {
        switch visualState {
        case .readyToTrack:
            return "Ready to Capture"
        case .targetNominated:
            return "Target Acquired"
        case .tracking:
            return "Good Tracking"
        case .almostDone:
            return "Almost There"
        case .targetLost:
            return "Target Lost"
        case .captureComplete:
            return "Capture Saved"
        }
    }

    private var bottomMessage: String {
        switch visualState {
        case .readyToTrack:
            return "Tap the object, then start capture."
        case .targetNominated:
            return "Keep the object in the box and hold steady."
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
            return "Reset"
        case .captureComplete:
            return "View"
        default:
            return nil
        }
    }

    private func bottomAction() {
        if visualState == .captureComplete {
            return
        }
        previewStateOverride = nil
        coordinator.cancelTracking()
    }

    private func primaryCaptureAction() {
        previewStateOverride = nil
        if coordinator.canCompleteTracking {
            coordinator.completeTracking()
        } else {
            coordinator.startTracking()
        }
    }

    private func secondaryControl(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(whitePrimary)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(whiteSecondary)
        }
    }

    private func cyclePreviewState() {
        let states = CaptureVisualState.allCases
        guard let index = states.firstIndex(of: visualState) else {
            previewStateOverride = .readyToTrack
            return
        }
        previewStateOverride = states[(index + 1) % states.count]
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
        path.addLine(to: CGPoint(x: center.x - 96, y: center.y))
        path.move(to: CGPoint(x: center.x + 96, y: center.y))
        path.addLine(to: CGPoint(x: rect.maxX, y: center.y))

        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addLine(to: CGPoint(x: center.x, y: center.y - 76))
        path.move(to: CGPoint(x: center.x, y: center.y + 76))
        path.addLine(to: CGPoint(x: center.x, y: rect.maxY))

        return path
    }
}

struct BoundingBoxView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = min(rect.width, rect.height) * 0.2
        let radius: CGFloat = 16

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - corner))

        return path
    }
}
