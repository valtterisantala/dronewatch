# ADR 0003: Use a provider abstraction for drone telemetry integrations

## Status
Accepted

## Decision
DroneWatch will use a telemetry provider abstraction with native iOS and Android bridges plus vendor and protocol adapters.

## Context
Drone telemetry access differs by vendor and platform.
The shared cross-platform app should not depend directly on a single manufacturer SDK.

## Consequences
- the app core depends on capabilities rather than brands
- iOS and Android integration remains an explicit architecture layer
- vendor-specific logic stays isolated behind adapters
- the backend receives normalized telemetry contracts
