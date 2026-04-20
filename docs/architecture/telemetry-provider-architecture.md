# Telemetry provider architecture

## Why this exists

Drone telemetry access is fragmented across manufacturers and protocols.
Cross-platform product logic should not depend directly on DJI, MAVLink, Autel, or other vendor-specific APIs.

The architecture therefore uses:

- shared product core
- provider facade
- native iOS and Android bridges
- vendor / protocol adapters

## Principle

The app depends on **capabilities**, not directly on **brands**.

The shared product logic should ask:

- can this provider connect?
- can it start a session?
- can it stream live position?
- can it expose model / battery / heading?
- what capabilities are unavailable?

It should not branch everywhere on vendor names.

## Provider facade responsibilities

Example interface responsibilities:

- `connect()`
- `disconnect()`
- `startSession()`
- `stopSession()`
- `subscribeTelemetry()`
- `getCapabilities()`
- `getConnectedVehicleInfo()`

## Native bridge layer

A cross-platform app core does not eliminate the need for native integration work.

The architecture must assume:
- iOS bridge
- Android bridge

Vendor SDKs or telemetry protocol clients live behind these platform bridges.

## Vendor / protocol adapters

Initial adapter targets:

- DJI
- MAVLink / MAVSDK

Planned-for-later adapters:

- Autel
- Parrot

## Backend normalization

The backend must receive one normalized telemetry contract regardless of provider.

Example normalized fields:

- provider type
- manufacturer
- model
- drone id
- session id
- timestamp
- lat
- lon
- altitude
- speed
- heading
- battery
- metadata

## Non-goal

The provider architecture is not meant to support every vendor in v1.
It is meant to ensure that supporting new vendors later does not require rewriting the app core.
