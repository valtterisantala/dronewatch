import Foundation
import DJISDK
import ExternalAccessory
import CoreLocation
import UIKit

struct DJIBootstrapConnectionSnapshot {
    var sdkManagerState: String = "idle"
    var registrationState: String = "pending"
    var baseProductConnected: Bool = false
    var connectedProductClass: String = "none"
    var connectedProductModel: String = "none"
    var supportedProductClasses: Set<String> = ["AIRCRAFT"]
    var usbAccessoryVisible: Bool = false
    var usbAccessoryNames: [String] = []
    var keyManagerConnection: Bool = false
    var keyManagerConnectionKnown: Bool = false
    var connectionAttempts: Int = 0
    var sdkVersion: String = DJISDKManager.sdkVersion()
    var telemetryLatitude: Double?
    var telemetryLongitude: Double?
    var telemetryAltitudeMeters: Double?
    var telemetryHeadingDegrees: Double?
    var telemetrySpeedMetersPerSecond: Double?
    var telemetryBatteryPercent: Int?
    var telemetrySatelliteCount: Int?
    var telemetryGPSSignalLevel: Int?
    var telemetryLocationSource: String = "none"
    var telemetryUpdatedAt: Date?
    var lastError: String?

    func asEnvFile() -> String {
        let classes = supportedProductClasses.sorted().joined(separator: " ")
        let telemetryKnown = telemetryLatitude != nil && telemetryLongitude != nil && telemetryAltitudeMeters != nil
        var lines = [
            "DJI_SDK_MANAGER_STATE=\(sdkManagerState)",
            "DJI_REGISTRATION_STATE=\(registrationState)",
            "DJI_BASE_PRODUCT_CONNECTED=\(baseProductConnected ? "true" : "false")",
            "DJI_CONNECTED_PRODUCT_CLASS=\(connectedProductClass)",
            "DJI_CONNECTED_PRODUCT_MODEL=\(connectedProductModel)",
            "DJI_SUPPORTED_PRODUCT_CLASSES=\"\(classes)\"",
            "DJI_USB_ACCESSORY_VISIBLE=\(usbAccessoryVisible ? "true" : "false")",
            "DJI_USB_ACCESSORY_NAMES=\"\(usbAccessoryNames.joined(separator: ","))\"",
            "DJI_KEYMANAGER_CONNECTION_KNOWN=\(keyManagerConnectionKnown ? "true" : "false")",
            "DJI_KEYMANAGER_CONNECTION=\(keyManagerConnection ? "true" : "false")",
            "DJI_CONNECTION_ATTEMPTS=\(connectionAttempts)",
            "DJI_SDK_VERSION=\(sdkVersion)",
            "DJI_TELEMETRY_KNOWN=\(telemetryKnown ? "true" : "false")",
            "DJI_TELEMETRY_LATITUDE=\(formatDouble(telemetryLatitude, decimals: 7))",
            "DJI_TELEMETRY_LONGITUDE=\(formatDouble(telemetryLongitude, decimals: 7))",
            "DJI_TELEMETRY_ALTITUDE_M=\(formatDouble(telemetryAltitudeMeters, decimals: 2))",
            "DJI_TELEMETRY_HEADING_DEG=\(formatDouble(telemetryHeadingDegrees, decimals: 1))",
            "DJI_TELEMETRY_SPEED_MPS=\(formatDouble(telemetrySpeedMetersPerSecond, decimals: 2))",
            "DJI_TELEMETRY_BATTERY_PERCENT=\(telemetryBatteryPercent.map(String.init) ?? "unknown")",
            "DJI_TELEMETRY_SATELLITE_COUNT=\(telemetrySatelliteCount.map(String.init) ?? "unknown")",
            "DJI_TELEMETRY_GPS_SIGNAL_LEVEL=\(telemetryGPSSignalLevel.map(String.init) ?? "unknown")",
            "DJI_TELEMETRY_LOCATION_SOURCE=\(telemetryLocationSource)",
            "DJI_TELEMETRY_UPDATED_AT=\(formatDate(telemetryUpdatedAt))"
        ]

        if let lastError, !lastError.isEmpty {
            let sanitized = lastError
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\"", with: "'")
            lines.append("DJI_LAST_ERROR=\"\(sanitized)\"")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func formatDouble(_ value: Double?, decimals: Int) -> String {
        guard let value else {
            return "unknown"
        }
        return String(format: "%.\(decimals)f", value)
    }

    private func formatDate(_ value: Date?) -> String {
        guard let value else {
            return "unknown"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}

protocol DJIBootstrapConnectionSink: AnyObject {
    func didUpdateDJIBootstrapSnapshot(_ snapshot: DJIBootstrapConnectionSnapshot)
}

final class DJIDirectBootstrapProbe: NSObject, DJISDKManagerDelegate, DJIFlightControllerDelegate, DJIBatteryDelegate {
    weak var sink: DJIBootstrapConnectionSink?
    private(set) var snapshot: DJIBootstrapConnectionSnapshot
    private var connectionRetryTimer: Timer?
    private var connectionAttemptCount = 0
    private var connectionKey: DJIProductKey?
    private var aircraftLocationKey: DJIFlightControllerKey?
    private weak var flightController: DJIFlightController?
    private weak var battery: DJIBattery?
    private var lastTelemetryEmitAt: Date?
    private var telemetryWatchdogTimer: Timer?
    private var lastWatchdogReconnectAt: Date?
    private var lastObserverResetAt: Date?
    private var lastRegistrationKickAt: Date?
    private var sdkListenersStarted = false
    private var lastWillEnterForegroundAt: Date?
    private var lastDidBecomeActiveAt: Date?
    private var lastDidEnterBackgroundAt: Date?
    private let telemetryEmitInterval: TimeInterval = 1.0
    private let telemetryStaleInterval: TimeInterval = 4.0
    private let telemetryWatchdogInterval: TimeInterval = 2.0
    private let watchdogReconnectCooldown: TimeInterval = 8.0
    private let lifecycleDebounceInterval: TimeInterval = 1.0
    private let observerResetCooldown: TimeInterval = 5.0
    private let registrationKickCooldown: TimeInterval = 20.0

    init(supportedProductClasses: Set<String> = ["AIRCRAFT"]) {
        self.snapshot = DJIBootstrapConnectionSnapshot(supportedProductClasses: supportedProductClasses)
        super.init()
    }

    deinit {
        detachTelemetryDelegates()
        stopConnectionRetryTimer()
        stopTelemetryWatchdogTimer()
        NotificationCenter.default.removeObserver(self)
        EAAccessoryManager.shared().unregisterForLocalNotifications()
    }

    func start() {
        // DJI SDK default is to close connection when entering background.
        // For this spike we keep connection management explicit to improve foreground recovery.
        DJISDKManager.closeConnection(whenEnteringBackground: false)

        EAAccessoryManager.shared().registerForLocalNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDidConnect(_:)),
            name: .EAAccessoryDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDidDisconnect(_:)),
            name: .EAAccessoryDidDisconnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForegroundNotification(_:)),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActiveNotification(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackgroundNotification(_:)),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        startTelemetryWatchdogTimer()
        refreshAccessoryState()
        startSDKManagerListenersIfNeeded()

        snapshot.sdkManagerState = "initializing"
        snapshot.registrationState = "pending"
        emitSnapshot(reason: "starting iOS DJI SDK bootstrap")
        DJISDKManager.registerApp(with: self)
    }

    func applicationWillEnterForeground() {
        if shouldDebounceLifecycleEvent(lastWillEnterForegroundAt) {
            return
        }
        lastWillEnterForegroundAt = Date()

        resetKeyObserversIfNeeded(reason: "application will enter foreground")
        synchronizeProductConnectionState()
        refreshAccessoryState()
        rebindTelemetryDelegatesIfPossible(reason: "application will enter foreground")
        if snapshot.registrationState == "success" {
            attemptStartConnection(reason: "application will enter foreground")
        }
        emitSnapshot(reason: "application will enter foreground")
    }

    func applicationDidBecomeActive() {
        if shouldDebounceLifecycleEvent(lastDidBecomeActiveAt) {
            return
        }
        lastDidBecomeActiveAt = Date()

        resetKeyObserversIfNeeded(reason: "application became active")
        synchronizeProductConnectionState()
        refreshAccessoryState()
        rebindTelemetryDelegatesIfPossible(reason: "application became active")
        if snapshot.registrationState == "success" {
            // Only force reconnect when telemetry stream appears stale after app switch.
            if isTelemetryStale() {
                forceReconnect(reason: "application became active (telemetry stale)")
            } else {
                startConnectionRetryTimer()
                attemptStartConnection(reason: "application became active")
            }
        }
        emitSnapshot(reason: "application became active")
    }

    func applicationDidEnterBackground() {
        if shouldDebounceLifecycleEvent(lastDidEnterBackgroundAt) {
            return
        }
        lastDidEnterBackgroundAt = Date()

        refreshAccessoryState()
        emitSnapshot(reason: "application entered background")
    }

    func writeSnapshotEnvFile(to url: URL) throws {
        try snapshot.asEnvFile().write(to: url, atomically: true, encoding: .utf8)
    }

    func appRegisteredWithError(_ error: Error?) {
        if let error {
            snapshot.sdkManagerState = "registration_failed"
            snapshot.registrationState = "failure"
            snapshot.lastError = error.localizedDescription
            emitSnapshot(reason: "DJI SDK registration failed")
            return
        }

        snapshot.sdkManagerState = "ready"
        snapshot.registrationState = "success"
        snapshot.lastError = nil
        emitSnapshot(reason: "DJI SDK registration succeeded")

        startKeyManagerConnectionObserver()
        startAircraftLocationObserver()
        startConnectionRetryTimer()
        attemptStartConnection(reason: "initial registration success")
    }

    func productConnected(_ product: DJIBaseProduct?) {
        applyConnectedProduct(product)
        attachTelemetryDelegates(for: product)
        stopConnectionRetryTimer()
        emitSnapshot(reason: "product connected")
    }

    func productDisconnected() {
        detachTelemetryDelegates()
        snapshot.baseProductConnected = false
        snapshot.connectedProductClass = "none"
        snapshot.connectedProductModel = "none"
        startConnectionRetryTimer()
        attemptStartConnection(reason: "product disconnected")
        emitSnapshot(reason: "product disconnected")
    }

    func productChanged(_ product: DJIBaseProduct?) {
        applyConnectedProduct(product)
        attachTelemetryDelegates(for: product)
        if snapshot.baseProductConnected {
            stopConnectionRetryTimer()
        } else {
            startConnectionRetryTimer()
        }
        emitSnapshot(reason: "product changed")
    }

    func didUpdateDatabaseDownloadProgress(_ progress: Progress) {
        print("DJI bootstrap: flysafe db progress \(Int(progress.fractionCompleted * 100))%")
    }

    @objc
    private func accessoryDidConnect(_ notification: Notification) {
        refreshAccessoryState()
        if snapshot.registrationState == "success" {
            // Accessory handoff from DJI consumer app can leave SDK in a stale transitional state.
            // Force a clean reconnect path instead of a single optimistic start call.
            forceReconnect(reason: "external accessory connected (handoff recovery)")
        } else {
            attemptStartConnection(reason: "external accessory connected")
        }
    }

    @objc
    private func accessoryDidDisconnect(_ notification: Notification) {
        refreshAccessoryState()
        emitSnapshot(reason: "external accessory disconnected")
    }

    @objc
    private func handleAppWillEnterForegroundNotification(_ notification: Notification) {
        applicationWillEnterForeground()
    }

    @objc
    private func handleAppDidBecomeActiveNotification(_ notification: Notification) {
        applicationDidBecomeActive()
    }

    @objc
    private func handleAppDidEnterBackgroundNotification(_ notification: Notification) {
        applicationDidEnterBackground()
    }

    private func applyConnectedProduct(_ product: DJIBaseProduct?) {
        guard let product else {
            snapshot.baseProductConnected = false
            snapshot.connectedProductClass = "none"
            snapshot.connectedProductModel = "none"
            return
        }

        snapshot.baseProductConnected = true
        snapshot.connectedProductClass = productClass(for: product)
        snapshot.connectedProductModel = productModel(for: product)
        snapshot.lastError = nil
    }

    private func productClass(for product: DJIBaseProduct) -> String {
        if product is DJIAircraft {
            return "AIRCRAFT"
        }

        return "UNSUPPORTED"
    }

    private func productModel(for product: DJIBaseProduct) -> String {
        if let modelObject = product.value(forKey: "model") {
            if let modelString = modelObject as? String, !modelString.isEmpty {
                return sanitizeModelName(modelString)
            }

            let modelDescription = String(describing: modelObject)
            if !modelDescription.isEmpty {
                return sanitizeModelName(modelDescription)
            }
        }

        return String(describing: type(of: product))
    }

    private func startConnectionRetryTimer() {
        guard connectionRetryTimer == nil else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.attemptStartConnection(reason: "periodic retry")
        }
        RunLoop.main.add(timer, forMode: .common)
        connectionRetryTimer = timer
    }

    private func stopConnectionRetryTimer() {
        connectionRetryTimer?.invalidate()
        connectionRetryTimer = nil
    }

    private func startTelemetryWatchdogTimer() {
        guard telemetryWatchdogTimer == nil else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: telemetryWatchdogInterval, repeats: true) { [weak self] _ in
            self?.runTelemetryWatchdog()
        }
        RunLoop.main.add(timer, forMode: .common)
        telemetryWatchdogTimer = timer
    }

    private func stopTelemetryWatchdogTimer() {
        telemetryWatchdogTimer?.invalidate()
        telemetryWatchdogTimer = nil
    }

    private func shouldDebounceLifecycleEvent(_ previousEventAt: Date?) -> Bool {
        guard let previousEventAt else {
            return false
        }
        return Date().timeIntervalSince(previousEventAt) < lifecycleDebounceInterval
    }

    private func startSDKManagerListenersIfNeeded() {
        guard !sdkListenersStarted else {
            return
        }

        DJISDKManager.startListeningOnRegistrationUpdates(withListener: self, andUpdate: { [weak self] registered, registrationError in
            guard let self else { return }
            if registered {
                self.snapshot.sdkManagerState = "ready"
                self.snapshot.registrationState = "success"
                self.snapshot.lastError = nil
                self.startKeyManagerConnectionObserver()
                self.startAircraftLocationObserver()
                self.emitSnapshot(reason: "registration listener update success")
            } else {
                self.snapshot.registrationState = "failure"
                self.snapshot.lastError = registrationError.localizedDescription
                self.emitSnapshot(reason: "registration listener update failure")
            }
        })

        DJISDKManager.startListeningOnProductConnectionUpdates(withListener: self, andUpdate: { [weak self] product in
            guard let self else { return }
            if let product {
                self.applyConnectedProduct(product)
                self.attachTelemetryDelegates(for: product)
                self.stopConnectionRetryTimer()
                self.emitSnapshot(reason: "product listener update connected")
            } else {
                self.detachTelemetryDelegates()
                self.snapshot.baseProductConnected = false
                self.snapshot.connectedProductClass = "none"
                self.snapshot.connectedProductModel = "none"
                if self.snapshot.registrationState == "success" {
                    self.startConnectionRetryTimer()
                }
                self.emitSnapshot(reason: "product listener update disconnected")
            }
        })

        sdkListenersStarted = true
    }

    private func resetKeyObserversIfNeeded(reason: String) {
        guard snapshot.registrationState == "success" else {
            return
        }

        let now = Date()
        if let lastObserverResetAt, now.timeIntervalSince(lastObserverResetAt) < observerResetCooldown {
            return
        }

        // Recover from app handoff states where key-manager listeners can stop delivering updates.
        DJISDKManager.keyManager()?.stopAllListening(ofListeners: self)
        connectionKey = nil
        aircraftLocationKey = nil
        snapshot.keyManagerConnectionKnown = false
        snapshot.keyManagerConnection = false
        lastObserverResetAt = now
        startKeyManagerConnectionObserver()
        startAircraftLocationObserver()
        emitSnapshot(reason: "\(reason) (key observers reset)")
    }

    private func runTelemetryWatchdog() {
        guard snapshot.registrationState == "success" else {
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            return
        }

        synchronizeProductConnectionState()

        if !snapshot.baseProductConnected {
            resetKeyObserversIfNeeded(reason: "watchdog key observer refresh")
            startConnectionRetryTimer()
            attemptStartConnection(reason: "watchdog reconnect (no product)")
            if !snapshot.keyManagerConnectionKnown, connectionAttemptCount > 0, connectionAttemptCount % 12 == 0 {
                kickRegistrationIfNeeded(reason: "watchdog registration refresh")
            }
            return
        }

        guard isTelemetryStale() else {
            return
        }

        let now = Date()
        if let lastWatchdogReconnectAt, now.timeIntervalSince(lastWatchdogReconnectAt) < watchdogReconnectCooldown {
            return
        }

        lastWatchdogReconnectAt = now
        forceReconnect(reason: "watchdog reconnect (stale telemetry)")
    }

    private func kickRegistrationIfNeeded(reason: String) {
        let now = Date()
        if let lastRegistrationKickAt, now.timeIntervalSince(lastRegistrationKickAt) < registrationKickCooldown {
            return
        }

        lastRegistrationKickAt = now
        snapshot.sdkManagerState = "re-registering"
        emitSnapshot(reason: reason)
        startSDKManagerListenersIfNeeded()
        DJISDKManager.beginAppRegistration()
        DJISDKManager.registerApp(with: self)
    }

    private func attemptStartConnection(reason: String) {
        guard snapshot.registrationState == "success" else {
            return
        }

        synchronizeProductConnectionState()

        if snapshot.baseProductConnected {
            stopConnectionRetryTimer()
            return
        }

        connectionAttemptCount += 1
        snapshot.connectionAttempts = connectionAttemptCount
        let started = DJISDKManager.startConnectionToProduct()

        if !started {
            snapshot.sdkManagerState = "connection_start_pending"
            snapshot.lastError = "startConnectionToProduct returned false (attempt \(connectionAttemptCount))"
        }

        if let product = DJISDKManager.product() {
            applyConnectedProduct(product)
            attachTelemetryDelegates(for: product)
        }

        if snapshot.baseProductConnected {
            stopConnectionRetryTimer()
        }

        emitSnapshot(
            reason: "\(reason), attempt=\(connectionAttemptCount), startConnectionToProduct=\(started)"
        )
    }

    private func emitSnapshot(reason: String) {
        print("DJI bootstrap (\(reason)):")
        print(snapshot.asEnvFile(), terminator: "")
        sink?.didUpdateDJIBootstrapSnapshot(snapshot)
    }

    private func startKeyManagerConnectionObserver() {
        guard connectionKey == nil else {
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            snapshot.lastError = "DJIKeyManager unavailable for connection observer"
            emitSnapshot(reason: "key manager unavailable")
            return
        }

        guard let key = DJIProductKey(param: DJIParamConnection) else {
            snapshot.lastError = "Failed to create DJIParamConnection key"
            emitSnapshot(reason: "key manager setup failed")
            return
        }

        // Match DJI sample behavior: watch key-manager connection state in addition to delegate callbacks.
        keyManager.startListeningForChanges(on: key, withListener: self, andUpdate: { [weak self] _, newValue in
            guard let self else { return }
            if let value = newValue {
                self.updateKeyManagerConnection(value.boolValue, reason: "key manager listener update")
            }
        })

        keyManager.getValueFor(key, withCompletion: { [weak self] value, _ in
            guard let self else { return }
            if let value {
                self.updateKeyManagerConnection(value.boolValue, reason: "key manager initial read")
            }
        })

        connectionKey = key
    }

    private func startAircraftLocationObserver() {
        guard aircraftLocationKey == nil else {
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            snapshot.lastError = "DJIKeyManager unavailable for aircraft location observer"
            emitSnapshot(reason: "location observer unavailable")
            return
        }

        guard let key = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
            snapshot.lastError = "Failed to create aircraft location key"
            emitSnapshot(reason: "flight key setup failed")
            return
        }

        keyManager.startListeningForChanges(on: key, withListener: self, andUpdate: { [weak self] _, newValue in
            guard let self else { return }
            self.applyLocationKeyedValue(newValue)
        })

        keyManager.getValueFor(key, withCompletion: { [weak self] value, _ in
            guard let self else { return }
            self.applyLocationKeyedValue(value)
        })

        aircraftLocationKey = key
    }

    private func updateKeyManagerConnection(_ connected: Bool, reason: String) {
        snapshot.keyManagerConnectionKnown = true
        snapshot.keyManagerConnection = connected

        if connected, let product = DJISDKManager.product() {
            applyConnectedProduct(product)
            attachTelemetryDelegates(for: product)
            stopConnectionRetryTimer()
        } else if connected {
            // Avoid false positives: treat key-manager true without product metadata as not fully connected.
            snapshot.baseProductConnected = false
            snapshot.connectedProductClass = "none"
            snapshot.connectedProductModel = "none"
            if snapshot.registrationState == "success" {
                // Keep retry loop alive until a concrete product object is available.
                startConnectionRetryTimer()
                attemptStartConnection(reason: "key manager connected without product")
            }
        } else {
            detachTelemetryDelegates()
            if snapshot.registrationState == "success" {
                startConnectionRetryTimer()
            }
        }

        emitSnapshot(reason: reason)
    }

    private func refreshAccessoryState() {
        let accessories = EAAccessoryManager.shared().connectedAccessories
        let relevant = accessories.filter { accessory in
            accessory.protocolStrings.contains("com.dji.video") ||
            accessory.protocolStrings.contains("com.dji.protocol") ||
            accessory.protocolStrings.contains("com.dji.common") ||
            accessory.protocolStrings.contains("com.dji.logiclink")
        }

        snapshot.usbAccessoryVisible = !relevant.isEmpty
        snapshot.usbAccessoryNames = relevant.map { accessory in
            if accessory.name.isEmpty {
                return "manufacturer=\(accessory.manufacturer),serial=\(accessory.serialNumber)"
            }
            return accessory.name
        }
    }

    private func synchronizeProductConnectionState() {
        if let product = DJISDKManager.product() {
            applyConnectedProduct(product)
            attachTelemetryDelegates(for: product)
            return
        }

        snapshot.baseProductConnected = false
        snapshot.connectedProductClass = "none"
        snapshot.connectedProductModel = "none"
    }

    private func rebindTelemetryDelegatesIfPossible(reason: String) {
        guard let product = DJISDKManager.product() else {
            return
        }
        attachTelemetryDelegates(for: product)
        emitSnapshot(reason: "\(reason) (telemetry delegates rebound)")
    }

    private func isTelemetryStale() -> Bool {
        guard let telemetryUpdatedAt = snapshot.telemetryUpdatedAt else {
            return false
        }
        return Date().timeIntervalSince(telemetryUpdatedAt) > telemetryStaleInterval
    }

    private func forceReconnect(reason: String) {
        DJISDKManager.stopConnectionToProduct()
        detachTelemetryDelegates()
        snapshot.baseProductConnected = false
        snapshot.connectedProductClass = "none"
        snapshot.connectedProductModel = "none"
        startConnectionRetryTimer()
        attemptStartConnection(reason: reason)
    }

    private func sanitizeModelName(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "_")
    }

    private func attachTelemetryDelegates(for product: DJIBaseProduct?) {
        guard let aircraft = product as? DJIAircraft else {
            detachTelemetryDelegates()
            return
        }

        if flightController !== aircraft.flightController {
            flightController?.delegate = nil
            flightController = aircraft.flightController
        }
        flightController?.delegate = self

        let nextBattery = aircraft.battery ?? product?.battery
        if battery !== nextBattery {
            battery?.delegate = nil
            battery = nextBattery
        }
        battery?.delegate = self
    }

    private func detachTelemetryDelegates() {
        flightController?.delegate = nil
        battery?.delegate = nil
        flightController = nil
        battery = nil
    }

    private func emitTelemetrySnapshotIfNeeded(force: Bool) {
        let now = Date()
        snapshot.telemetryUpdatedAt = now

        if force {
            lastTelemetryEmitAt = now
            emitSnapshot(reason: "telemetry update")
            return
        }

        if let lastTelemetryEmitAt, now.timeIntervalSince(lastTelemetryEmitAt) < telemetryEmitInterval {
            return
        }

        self.lastTelemetryEmitAt = now
        emitSnapshot(reason: "telemetry update")
    }

    private func applyCoordinate(_ coordinate: CLLocationCoordinate2D, source: String) {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return
        }
        snapshot.telemetryLatitude = coordinate.latitude
        snapshot.telemetryLongitude = coordinate.longitude
        snapshot.telemetryLocationSource = source
    }

    private func applyLocationKeyedValue(_ keyedValue: DJIKeyedValue?) {
        guard let value = keyedValue?.value else {
            return
        }

        if let location = value as? CLLocation {
            applyCoordinate(location.coordinate, source: "key_aircraft")
            emitTelemetrySnapshotIfNeeded(force: false)
        }
    }

    private func normalizedHeading(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 {
            value += 360
        }
        return value
    }

    func flightController(_ fc: DJIFlightController, didUpdate state: DJIFlightControllerState) {
        if let location = state.aircraftLocation {
            applyCoordinate(location.coordinate, source: "aircraft")
        } else if let homeLocation = state.homeLocation {
            // Fallback for pre-takeoff cases where aircraft location is nil but home point is available.
            applyCoordinate(homeLocation.coordinate, source: "home")
        }

        snapshot.telemetryAltitudeMeters = state.altitude
        snapshot.telemetryHeadingDegrees = normalizedHeading(Double(state.attitude.yaw))
        snapshot.telemetrySatelliteCount = Int(state.satelliteCount)
        snapshot.telemetryGPSSignalLevel = Int(state.gpsSignalLevel.rawValue)

        let vx = Double(state.velocityX)
        let vy = Double(state.velocityY)
        snapshot.telemetrySpeedMetersPerSecond = hypot(vx, vy)
        emitTelemetrySnapshotIfNeeded(force: false)
    }

    func battery(_ battery: DJIBattery, didUpdate state: DJIBatteryState) {
        snapshot.telemetryBatteryPercent = Int(state.chargeRemainingInPercent)
        emitTelemetrySnapshotIfNeeded(force: false)
    }
}
