import SwiftUI

@main
struct DroneWatchDJIBootstrapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = BootstrapCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
                .onAppear {
                    appDelegate.attach(coordinator: coordinator)
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        coordinator.applicationDidBecomeActive()
                    case .background:
                        coordinator.applicationDidEnterBackground()
                    case .inactive:
                        coordinator.applicationWillEnterForeground()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
