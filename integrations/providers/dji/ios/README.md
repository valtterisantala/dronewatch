# DJI iOS direct bootstrap + telemetry read (Issue #2 + #3)

This folder defines the direct iOS DJI Mobile SDK path for POC 1/4 and 2/4.

Goals of this slice:

- register DJI SDK successfully
- start product connection through `DJISDKManager`
- detect supported DJI chain (`SDKManager -> BaseProduct -> AIRCRAFT`)
- read live aircraft telemetry (lat/lon/alt minimum)
- emit developer-visible state for verification

Out of scope:

- telemetry normalization into shared app/backend contracts
- backend ingest
- UI polish
- Bridge App mode dependency

## Files

- `DJIDirectBootstrapProbe.swift`: direct iOS DJI SDK probe using `DJISDKManagerDelegate`
  - attaches `DJIFlightControllerDelegate` for live flight-controller state
  - attaches `DJIBatteryDelegate` for optional battery %

## Integration direction

This spike intentionally uses the direct iOS DJI Mobile SDK path:

1. register with `DJISDKManager.registerApp(with:)`
2. on successful registration, call `DJISDKManager.startConnectionToProduct()`
3. consume `productConnected`, `productChanged`, and `productDisconnected`
4. classify product (`AIRCRAFT` supported in this slice)
5. when connected, listen to flight controller + battery state and capture:
   - required: lat/lon/altitude
   - optional: heading/speed/battery
6. output snapshot in env-file format consumed by:
   - `integrations/providers/dji/bootstrap/run-bootstrap-check.sh`

## Setup assumptions

- iOS app target with DJI Mobile SDK integrated (`DJI-SDK-iOS`)
- `DJISDKAppKey` exists in `Info.plist`
- `UISupportedExternalAccessoryProtocols` includes:
  - `com.dji.video`
  - `com.dji.protocol`
  - `com.dji.common`
  - `com.dji.logiclink`
- bundle id and app key are registered in DJI developer console
- first registration requires network connectivity
- test hardware path for this issue is Mavic Air 2

## Minimal host-app wiring example

Use the probe from app startup (for example `AppDelegate`) and write snapshots to disk:

```swift
let probe = DJIDirectBootstrapProbe(supportedProductClasses: ["AIRCRAFT"])
probe.start()

let snapshotURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("dji-connection-state.env")
try? probe.writeSnapshotEnvFile(to: snapshotURL)
```

Then verify:

```bash
./integrations/providers/dji/bootstrap/run-bootstrap-check.sh --env-file /tmp/dji-connection-state.env
```

## Notes for next issue

Next task should map this raw telemetry output into DroneWatch's normalized cooperative telemetry contract and wire it to app/backend paths.
