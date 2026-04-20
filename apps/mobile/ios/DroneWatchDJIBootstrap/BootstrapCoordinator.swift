import Foundation
import Combine

final class BootstrapCoordinator: NSObject, ObservableObject, DJIBootstrapConnectionSink {
    @Published private(set) var snapshot = DJIBootstrapConnectionSnapshot()
    @Published private(set) var logLines: [String] = []
    @Published private(set) var snapshotFilePath = ""
    @Published private(set) var telemetryLastUpdatedText = "unknown"

    private var probe: DJIDirectBootstrapProbe?
    private let supportedProductClasses: Set<String> = ["AIRCRAFT"]
    private var lastLoggedConnectionSignature = ""

    func startBootstrap() {
        if probe != nil {
            return
        }

        let probe = DJIDirectBootstrapProbe(supportedProductClasses: supportedProductClasses)
        probe.sink = self
        self.probe = probe
        appendLog("Starting direct iOS DJI SDK bootstrap probe")
        probe.start()
    }

    func applicationWillEnterForeground() {
        appendLog("App will enter foreground; refreshing DJI accessory state")
        probe?.applicationWillEnterForeground()
    }

    func applicationDidBecomeActive() {
        appendLog("App became active; retrying DJI connection if needed")
        if probe == nil {
            startBootstrap()
            return
        }
        probe?.applicationDidBecomeActive()
    }

    func applicationDidEnterBackground() {
        appendLog("App entered background; keeping DJI probe state active")
        probe?.applicationDidEnterBackground()
    }

    func resetDJISession() {
        appendLog("Manual DJI session reset requested")
        if probe == nil {
            startBootstrap()
            return
        }
        probe?.manualResetSession()
    }

    func didUpdateDJIBootstrapSnapshot(_ snapshot: DJIBootstrapConnectionSnapshot) {
        DispatchQueue.main.async {
            let connectionSignature = self.connectionSignature(for: snapshot)
            self.snapshot = snapshot
            self.telemetryLastUpdatedText = self.telemetryAgeText(from: snapshot.telemetryUpdatedAt)
            self.persist(snapshot: snapshot)

            // Keep logs readable: connection-state changes are critical, telemetry updates are high-frequency.
            if connectionSignature != self.lastLoggedConnectionSignature {
                self.lastLoggedConnectionSignature = connectionSignature
                self.appendLog(
                    "State update: registration=\(snapshot.registrationState), " +
                    "connected=\(snapshot.baseProductConnected), " +
                    "product=\(snapshot.connectedProductClass) \(snapshot.connectedProductModel)"
                )
            }
        }
    }

    var snapshotText: String {
        snapshot.asEnvFile()
    }

    private func persist(snapshot: DJIBootstrapConnectionSnapshot) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documents else {
            appendLog("Could not resolve Documents directory for snapshot export")
            return
        }

        let fileURL = documents.appendingPathComponent("dji-connection-state.env")

        do {
            try snapshot.asEnvFile().write(to: fileURL, atomically: true, encoding: .utf8)
            snapshotFilePath = fileURL.path
        } catch {
            appendLog("Failed to write snapshot env file: \(error.localizedDescription)")
        }
    }

    private func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logLines.append("\(timestamp) \(message)")
        if logLines.count > 100 {
            logLines.removeFirst(logLines.count - 100)
        }
    }

    private func connectionSignature(for snapshot: DJIBootstrapConnectionSnapshot) -> String {
        [
            snapshot.sdkManagerState,
            snapshot.registrationState,
            snapshot.baseProductConnected ? "1" : "0",
            snapshot.keyManagerConnectionKnown ? "1" : "0",
            snapshot.keyManagerConnection ? "1" : "0",
            snapshot.connectedProductClass,
            snapshot.connectedProductModel,
            snapshot.usbAccessoryVisible ? "1" : "0",
            snapshot.usbAccessoryNames.joined(separator: ","),
            snapshot.lastError ?? "none",
            "\(snapshot.connectionAttempts)"
        ].joined(separator: "|")
    }

    private func telemetryAgeText(from date: Date?) -> String {
        guard let date else {
            return "unknown"
        }

        let ageSeconds = max(0, Int(Date().timeIntervalSince(date)))
        if ageSeconds < 1 {
            return "just_now"
        }
        return "\(ageSeconds)s_ago"
    }
}
