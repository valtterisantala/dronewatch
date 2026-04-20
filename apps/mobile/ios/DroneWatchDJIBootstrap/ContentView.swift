import SwiftUI

struct ContentView: View {
    @ObservedObject var coordinator: BootstrapCoordinator

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusSection
                    telemetrySection
                    snapshotSection
                    logSection
                }
                .padding(16)
            }
            .navigationTitle("DJI Bootstrap Check")
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection State")
                .font(.headline)

            keyValueRow("SDK manager", coordinator.snapshot.sdkManagerState)
            keyValueRow("Registration", coordinator.snapshot.registrationState)
            keyValueRow("Connected", coordinator.snapshot.baseProductConnected ? "true" : "false")
            keyValueRow("KeyManager conn", coordinator.snapshot.keyManagerConnectionKnown ? (coordinator.snapshot.keyManagerConnection ? "true" : "false") : "unknown")
            keyValueRow("Product class", coordinator.snapshot.connectedProductClass)
            keyValueRow("Product model", coordinator.snapshot.connectedProductModel)
            keyValueRow("USB accessory", coordinator.snapshot.usbAccessoryVisible ? "visible" : "not_visible")
            if !coordinator.snapshot.usbAccessoryNames.isEmpty {
                keyValueRow("Accessory names", coordinator.snapshot.usbAccessoryNames.joined(separator: ", "))
            }

            if let lastError = coordinator.snapshot.lastError, !lastError.isEmpty {
                keyValueRow("Last error", lastError)
            }
            keyValueRow("Attempts", "\(coordinator.snapshot.connectionAttempts)")
            keyValueRow("SDK version", coordinator.snapshot.sdkVersion)

            if !coordinator.snapshotFilePath.isEmpty {
                keyValueRow("Snapshot file", coordinator.snapshotFilePath)
            }

            Button(action: {
                coordinator.resetDJISession()
            }) {
                Text("Reset DJI Session")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Telemetry")
                .font(.headline)

            keyValueRow("Telemetry known", coordinator.snapshot.telemetryLatitude != nil &&
                coordinator.snapshot.telemetryLongitude != nil &&
                coordinator.snapshot.telemetryAltitudeMeters != nil ? "true" : "false")
            keyValueRow("Latitude", formatDouble(coordinator.snapshot.telemetryLatitude, decimals: 7))
            keyValueRow("Longitude", formatDouble(coordinator.snapshot.telemetryLongitude, decimals: 7))
            keyValueRow("Altitude (m)", formatDouble(coordinator.snapshot.telemetryAltitudeMeters, decimals: 2))
            keyValueRow("Heading (deg)", formatDouble(coordinator.snapshot.telemetryHeadingDegrees, decimals: 1))
            keyValueRow("Speed (m/s)", formatDouble(coordinator.snapshot.telemetrySpeedMetersPerSecond, decimals: 2))
            keyValueRow("Battery (%)", coordinator.snapshot.telemetryBatteryPercent.map(String.init) ?? "unknown")
            keyValueRow("Satellites", coordinator.snapshot.telemetrySatelliteCount.map(String.init) ?? "unknown")
            keyValueRow("GPS signal", coordinator.snapshot.telemetryGPSSignalLevel.map(String.init) ?? "unknown")
            keyValueRow("Location src", coordinator.snapshot.telemetryLocationSource)
            keyValueRow("Last update", coordinator.telemetryLastUpdatedText)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snapshot (env format)")
                .font(.headline)

            Text(coordinator.snapshotText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Log")
                .font(.headline)

            if coordinator.logLines.isEmpty {
                Text("Waiting for DJI SDK events...")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(coordinator.logLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .fontWeight(.semibold)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.footnote))
    }

    private func formatDouble(_ value: Double?, decimals: Int) -> String {
        guard let value else {
            return "unknown"
        }
        return String(format: "%.\(decimals)f", value)
    }
}
