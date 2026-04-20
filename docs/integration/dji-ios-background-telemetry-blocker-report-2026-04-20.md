# DJI iOS Background Telemetry Blocker Report (as of April 20, 2026)

## 1. Executive Summary

This report documents an iOS DJI Mobile SDK investigation in DroneWatch focused on one concrete use case:

- read live aircraft telemetry (`lat/lon/alt` minimum)
- continue reading and uploading telemetry while our app is in background
- allow pilot to keep DJI consumer app in foreground for camera feed and flight UX

Current conclusion from real-device testing:

- We can read telemetry in our app when our app owns the DJI connection.
- Our app can continue background telemetry updates in some conditions.
- When DJI consumer app is brought to foreground, our app telemetry stream stops.
- Returning to our app after that handoff can leave SDK connection recovery in a wedged state (improved with manual reset, not fully eliminated in all first-return scenarios).

This strongly suggests a connection ownership/foreground control boundary on a single iPhone + single RC link.

## 2. Product Use Case Being Pursued

### 2.1 Primary user story

A pilot wants to:

1. fly with DJI consumer app in foreground (for stable camera feed and familiar control UX)
2. run DroneWatch in background on the same iPhone
3. continuously stream cooperative telemetry (`lat/lon/alt` + optional extras) from drone to server in near real-time

### 2.2 Why this matters

DroneWatch requires live cooperative telemetry publishing. If this cannot run while DJI app is foreground on the same phone, product architecture must change (single-app SDK integration or multi-device setup).

## 3. Test Environment

- Date window: April 20, 2026
- Hardware:
  - DJI Mavic Air 2
  - DJI remote controller (USB to iPhone)
  - physical iPhone
- SDK/app:
  - DJI Mobile SDK iOS 4.16.2
  - DroneWatch iOS probe app (`DroneWatchDJIBootstrap`)
- Connection mode: direct iOS DJI SDK path (no bridge app dependency)

## 4. What Was Implemented

### 4.1 Telemetry read implementation

Probe can now read and emit:

- required: `lat`, `lon`, `altitude`
- optional: `heading`, `speed`, `battery`
- diagnostics: `satellite count`, `GPS signal`, `location source`

Output paths:

- on-screen telemetry panel
- env snapshot file (`dji-connection-state.env`)

### 4.2 Lifecycle and recovery work

Implemented progressively:

- foreground/background lifecycle hooks
- key-manager connection listener + product listeners
- accessory connect/disconnect handling
- watchdog reconnect when no product/stale telemetry
- key observer reset/rebind logic
- optional registration refresh kicks in wedged states
- manual UI action: `Reset DJI Session`

## 5. Verified Findings (Real Device)

### 5.1 Confirmed successes

1. DJI SDK registration can succeed and product can connect (`AIRCRAFT`, `Mavic_Air_2`).
2. Live telemetry (`lat/lon`) can be read in our app in active ownership state.
3. Our app can continue telemetry updates while backgrounded in at least some intervals.

### 5.2 Confirmed failure mode

When DJI consumer app is brought to foreground:

- DroneWatch background telemetry updates stop.
- Returning to DroneWatch can result in no live updates or no reconnect in first return path.
- In stuck runs, repeated `startConnectionToProduct=true` retries do not produce product object.

Observed stuck signature (representative):

- `DJI_USB_ACCESSORY_VISIBLE=true`
- `DJI_REGISTRATION_STATE=success`
- `DJI_BASE_PRODUCT_CONNECTED=false`
- `DJI_KEYMANAGER_CONNECTION_KNOWN=false`
- repeated high attempt counts

This indicates the physical accessory is visible but SDK-level product/key-manager state is not recovering.

## 6. Blocking Question

Can a third-party DJI Mobile SDK iOS app reliably maintain telemetry ingestion in background while DJI consumer app is foreground on the same iPhone and same RC USB link?

Current evidence indicates "not reliably" in this setup.

## 7. Most Likely Technical Constraint (Working Hypothesis)

A single-accessory/single-link ownership boundary exists at runtime:

- foreground DJI app appears to claim and/or reconfigure the link such that our app’s SDK session no longer receives updates
- session re-acquisition by our app is not guaranteed immediately after app switch, even when DJI app is later closed, without explicit recovery actions (sometimes app relaunch)

This aligns with iOS external accessory behavior expectations and practical single-owner access patterns, but needs deeper confirmation from official DJI/iOS specifics.

## 8. Mitigations Attempted and Outcome

1. Disable DJI auto-close-on-background in SDK manager:
- Outcome: not sufficient.

2. Aggressive foreground reconnect (`stopConnectionToProduct` + retry loop):
- Outcome: helps some cases, not all.

3. Key-manager observer reset/rebind:
- Outcome: helps some stuck states, not fully deterministic.

4. Product/registration listener subscriptions:
- Outcome: improved visibility, still not a guaranteed handoff recovery.

5. Watchdog reconnect and periodic registration kick:
- Outcome: partial recovery in some scenarios, not complete.

6. Manual `Reset DJI Session` UI action:
- Outcome: operationally useful field workaround; does not prove underlying foreground coexistence is possible.

## 9. Why This Is a Product Blocker

The target use case requires:

- pilot stays in DJI app foreground
- DroneWatch remains background telemetry producer continuously

If this is platform- or SDK-constrained, this architecture is invalid on single-phone operation.

## 10. Research Tasks for GPT-5.4 Pro / Deep Investigation

Please investigate with source-backed conclusions:

1. **Definitive capability answer**
- Is simultaneous operation (DJI consumer app foreground + third-party DJI SDK app background telemetry) officially supported, unsupported, or undefined on iOS?

2. **Ownership model details**
- On iOS with external accessory protocols, can two apps hold practical concurrent access to the same DJI RC channel?
- If not, what exactly happens on handoff (session invalidation, stream pause, key-manager teardown)?

3. **DJI-specific guidance**
- Any official DJI notes on coexistence with DJI Fly/DJI GO and third-party apps.
- Any recommended handshake/recovery sequence after foreground handoff.

4. **Background execution limits**
- exact iOS policy constraints relevant to this scenario (`external-accessory`, app suspension, foreground competition)
- whether any entitlement/mode combination can make this reliable

5. **Feasible architecture options**
- If single-device coexistence is impossible/unreliable, provide ranked alternatives:
  - single-app DJI SDK foreground integration (video + telemetry in one app)
  - split-device strategy
  - any supported inter-app data sharing path from DJI app (if exists)

6. **Hard recommendation**
- Based on evidence, what architecture should DroneWatch choose for MVP telemetry streaming reliability?

## 11. Evidence Artifacts Available

- Env snapshots with connection/telemetry fields and attempt counters
- console logs showing retry loops and stuck key-manager known=false states
- implemented recovery mechanisms in `DJIDirectBootstrapProbe.swift`

## 12. Current Operational Workaround

For field tests today:

- run DroneWatch directly when telemetry is needed
- use `Reset DJI Session` if app appears wedged after handoff
- avoid relying on DJI app foreground + DroneWatch background concurrent telemetry as a dependable production flow

