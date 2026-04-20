import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private weak var coordinator: BootstrapCoordinator?
    private var started = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        startIfReady()
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        coordinator?.applicationWillEnterForeground()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        coordinator?.applicationDidBecomeActive()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        coordinator?.applicationDidEnterBackground()
    }

    func attach(coordinator: BootstrapCoordinator) {
        self.coordinator = coordinator
        startIfReady()
    }

    private func startIfReady() {
        guard !started, let coordinator else {
            return
        }

        started = true
        coordinator.startBootstrap()
    }
}
