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
