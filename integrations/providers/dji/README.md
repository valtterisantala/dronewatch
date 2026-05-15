# integrations/providers/dji

This folder contains the DJI-specific telemetry integration path.

## Priority

This is the **first MVP / proof-of-concept telemetry integration** for DroneWatch.

The first success criterion is not a full end-to-end product.
It is a minimal technical spike that proves DroneWatch can read live aircraft telemetry through the DJI integration path.

## First POC target

Minimal proof point:
- initialize the DJI integration path
- establish product connection through the supported DJI chain
- read live aircraft position
- map raw vendor telemetry into the DroneWatch normalized telemetry model
- make the telemetry available to the app/backend path

## Non-goal of the first POC

The first POC is not:
- full drone registry
- polished UX
- full live map productization
- multi-provider support

It is the smallest useful proof that the DJI telemetry path works.

## Current POC slice status

The DJI POC is intentionally split into narrow issues.

- **POC 1/4 (bootstrap + connected-state confirmation)** is implemented in:
  - `integrations/providers/dji/bootstrap/run-bootstrap-check.sh`
  - `integrations/providers/dji/bootstrap/README.md`
  - `integrations/providers/dji/ios/DJIDirectBootstrapProbe.swift`
  - `integrations/providers/dji/ios/README.md`
- Direction for this slice is explicit:
  - direct iOS DJI Mobile SDK path
  - no dependency on deprecated iOS Bridge App path
- **POC 2/4 (live telemetry read on connected aircraft)** is implemented in:
  - `integrations/providers/dji/ios/DJIDirectBootstrapProbe.swift`
  - archived spike UI code from the former `apps/mobile/ios/DroneWatchDJIBootstrap` app path
  - `apps/mobile/ios/README.md`
- Remaining POC slices should focus on telemetry normalization + backend/app integration.
