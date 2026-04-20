# DroneWatch DJI iOS Bootstrap App

This is the minimal iOS app for DJI POC 1/4 + 2/4:

- direct DJI Mobile SDK bootstrap on iPhone
- product connection detection for Mavic Air 2 test hardware
- live telemetry read from the connected aircraft
- developer-visible output in UI and env snapshot format

The app keeps scope narrow:

- no telemetry normalization into shared domain contracts yet
- no backend integration
- no map UI

## Prerequisites

- Xcode 26+
- CocoaPods installed (`pod --version`)
- DJI App Key created in DJI developer console
- physical iPhone connected to Mavic Air 2 remote/aircraft chain

## Setup

1. Update DJI App Key in:
   - `DroneWatchDJIBootstrap/Info.plist` key `DJISDKAppKey`
2. Optional: update bundle id in `project.yml` to match your DJI app registration.
3. Generate project and install pods:

```bash
cd apps/mobile/ios
xcodegen generate
pod install
```

4. Open workspace:

```bash
open DroneWatchDJIBootstrap.xcworkspace
```

5. Select your iPhone and run.

## What to expect

- App starts direct DJI registration via `DJISDKManager`.
- On success it starts product connection.
- UI shows:
  - SDK manager state
  - registration state
  - connected product class/model
  - live telemetry values:
    - latitude
    - longitude
    - altitude (meters, relative to takeoff point from DJI flight-controller state)
    - heading (degrees, optional)
    - speed (m/s, optional)
    - battery percentage (optional)
  - event log

The app also writes an env snapshot to:

- app Documents: `dji-connection-state.env`

Use this file format with:

```bash
./integrations/providers/dji/bootstrap/run-bootstrap-check.sh --env-file /path/to/dji-connection-state.env
```

The snapshot now includes both:

- delegate-based product connection (`DJI_BASE_PRODUCT_CONNECTED`)
- key-manager connection (`DJI_KEYMANAGER_CONNECTION`)
- live telemetry fields:
  - `DJI_TELEMETRY_LATITUDE`
  - `DJI_TELEMETRY_LONGITUDE`
  - `DJI_TELEMETRY_ALTITUDE_M`
  - `DJI_TELEMETRY_HEADING_DEG`
  - `DJI_TELEMETRY_SPEED_MPS`
  - `DJI_TELEMETRY_BATTERY_PERCENT`
  - `DJI_TELEMETRY_SATELLITE_COUNT`
  - `DJI_TELEMETRY_GPS_SIGNAL_LEVEL`
  - `DJI_TELEMETRY_LOCATION_SOURCE`
- `DJI_TELEMETRY_UPDATED_AT`

## App focus / background behavior

- The app now retries `startConnectionToProduct()` automatically when returning to foreground/active.
- The probe disables DJI SDK auto-close-on-background and forces a clean stop/start reconnect on each active transition.
- `Info.plist` now enables `UIBackgroundModes = external-accessory` so the DJI accessory link can continue in background when iOS allows it.
- Practical caveat: iOS can still suspend background execution under system policy, so background telemetry is best-effort, not guaranteed continuous forever.
- Field-verified behavior on iPhone + Mavic Air 2 chain:
  - our app can continue background telemetry while no competing DJI foreground app takes over
  - when DJI consumer app becomes foreground, our app telemetry updates stop
  - after that handoff, reconnect may require a hard reset path

For testing:

1. Connect and wait for `Connected=true`.
2. Send app to background for a short interval.
3. Return to app and confirm:
   - `Connected` recovers to `true` automatically
   - `Last update` continues refreshing

## Manual recovery action

The UI includes a `Reset DJI Session` button for field recovery:

- stops current SDK product connection
- clears key-manager listeners and rebinds them
- restarts product connection retries without killing/relaunching the app

Use this when the app appears stuck after app handoff events.

## Deep-dive blocker report

A detailed use-case + blocker report for external research is available at:

- `docs/integration/dji-ios-background-telemetry-blocker-report-2026-04-20.md`

## Telemetry verification (Issue #3)

1. Confirm connection first:
   - `Registration = success`
   - `Connected = true`
   - product class/model shown as `AIRCRAFT / Mavic_Air_2`
2. Wait for `Live Telemetry` values to become known.
3. Move the aircraft carefully (props disarmed for bench checks) and verify:
   - `Latitude` or `Longitude` changes with GPS updates
   - `Altitude (m)` changes when the aircraft altitude changes
4. Confirm `Last update` keeps refreshing (not stale).

If heading/battery update but lat/lon stays unknown:

- check `Satellites` and `GPS signal` in the app
- move to open sky and wait for stronger GPS lock
- if `Location src` becomes `home`, coordinates are from home-point fallback before full aircraft location is available

## Telemetry caveats

- Altitude is DJI flight-controller relative altitude from takeoff, not MSL/terrain-corrected altitude.
- Telemetry availability depends on aircraft state and GPS quality; values can be `unknown` before a valid fix.
- This slice is read-only and local to the app. It does not normalize or publish telemetry to backend contracts yet.

## Troubleshooting: registration success but connected=false

If registration is `success` but `connected` stays `false`, check these first:

1. `Info.plist` contains:
   - `UISupportedExternalAccessoryProtocols` with:
     - `com.dji.video`
     - `com.dji.protocol`
     - `com.dji.common`
     - `com.dji.logiclink`
2. The app is in foreground before reconnecting USB to the RC.
3. Unplug and replug the iPhone cable to RC after app launch.
4. Ensure the DJI consumer app is fully closed while testing this app.
5. Confirm RC-to-aircraft link is active and cable is in RC data port.
6. If iOS keeps auto-launching the DJI consumer app on USB connect, temporarily uninstall that app for this spike test so accessory ownership cannot be stolen.
