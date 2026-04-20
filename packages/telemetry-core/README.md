# packages/telemetry-core

This folder contains the shared telemetry abstraction layer.

Responsibilities:
- provider facade
- capability model
- normalized telemetry model
- session lifecycle model
- telemetry normalization helpers
- integration-facing error model

This package must stay vendor-agnostic.
DJI, MAVLink, and other vendor/protocol-specific implementations belong outside this package.
