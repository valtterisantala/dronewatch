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
                    colors: [.black.opacity(0.12), .clear, .black.opacity(0.4)],
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
        VStack(spacing: 14) {
            stabilityPill

            captureControls

            if showsBottomStatusCard {
                bottomStatusCard
            }

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
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
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

                Text(centerHint)
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .foregroundColor(targetAccent)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(targetAccent.opacity(0.35), lineWidth: 1))
                    .position(x: box.midX * size.width, y: max(72, box.minY * size.height - 24))

                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        targetAccent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: box.width * size.width, height: box.height * size.height)
                    .position(x: box.midX * size.width, y: box.midY * size.height)
                    .shadow(color: targetAccent.opacity(0.32), radius: 5)
                    .animation(.easeInOut(duration: 0.18), value: box)

                if visualState == .readyToTrack {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(targetAccent)
                        .position(x: box.midX * size.width, y: box.midY * size.height)
                }
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
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.caption.weight(.medium))
                .foregroundColor(whitePrimary)

            HStack(spacing: 5) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(index < filledStabilitySegments ? statusAccent : inactiveBar)
                        .frame(width: 16, height: 4)
                }
            }

            Text(stabilityShortLabel)
                .font(.caption2.weight(.semibold))
                .foregroundColor(statusAccent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: 230)
        .onLongPressGesture {
            #if DEBUG
            cyclePreviewState()
            #endif
        }
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
                            .frame(width: 84, height: 84)
                        if coordinator.canCompleteTracking {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(recordRed)
                                .frame(width: 36, height: 36)
                        } else {
                            Circle()
                                .fill(recordRed)
                                .frame(width: 60, height: 60)
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
        .padding(.horizontal, 18)
        .frame(maxWidth: 340)
    }

    private var bottomStatusCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusAccent)
                    .frame(width: 34, height: 34)
                Image(systemName: bottomIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(bottomTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(whitePrimary)
                Text(bottomMessage)
                    .font(.caption)
                    .foregroundColor(whiteSecondary)
                    .lineLimit(2)
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
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: 340)
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
                            .font(.system(size: 15, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(selectedTab == tab ? primaryGreen : whiteSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Capsule()
                                .fill(primaryGreen)
                                .frame(width: 16, height: 3)
                                .offset(y: 4)
                        }
                    }
                    .accessibilityLabel(tab.title)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: 330)
        .opacity(selectedTab == .capture && coordinator.state == .tracking ? 0.52 : 0.9)
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

    private var stabilityShortLabel: String {
        switch visualState {
        case .readyToTrack:
            return "Ready"
        case .targetNominated:
            return "Locking"
        case .targetLost:
            return "Lost"
        case .tracking:
            return "Good"
        case .almostDone:
            return "Almost"
        case .captureComplete:
            return "Saved"
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

    private var showsBottomStatusCard: Bool {
        switch visualState {
        case .readyToTrack, .targetLost, .captureComplete:
            return true
        case .targetNominated, .tracking, .almostDone:
            return false
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
            return "Ready"
        case .targetNominated:
            return "Target selected"
        case .tracking:
            return "Good tracking"
        case .almostDone:
            return "Almost there"
        case .targetLost:
            return "Target lost"
        case .captureComplete:
            return "Capture saved"
        }
    }

    private var bottomMessage: String {
        switch visualState {
        case .readyToTrack:
            return "Tap the object to select it."
        case .targetNominated:
            return "Hold steady."
        case .tracking:
            return "Keep it in the box."
        case .almostDone:
            return "Just a little more."
        case .targetLost:
            return "Find it and tap again."
        case .captureComplete:
            return "Review or start a new capture."
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
        Image(systemName: icon)
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(whitePrimary)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .accessibilityLabel(label)
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
        let gap: CGFloat = 10
        let length: CGFloat = 42

        path.move(to: CGPoint(x: center.x - gap - length, y: center.y))
        path.addLine(to: CGPoint(x: center.x - gap, y: center.y))
        path.move(to: CGPoint(x: center.x + gap, y: center.y))
        path.addLine(to: CGPoint(x: center.x + gap + length, y: center.y))

        path.move(to: CGPoint(x: center.x, y: center.y - gap - length))
        path.addLine(to: CGPoint(x: center.x, y: center.y - gap))
        path.move(to: CGPoint(x: center.x, y: center.y + gap))
        path.addLine(to: CGPoint(x: center.x, y: center.y + gap + length))

        return path
    }
}
