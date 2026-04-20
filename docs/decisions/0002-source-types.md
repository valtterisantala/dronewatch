# ADR 0002: Preserve report and cooperative telemetry as distinct source types

## Status
Accepted

## Decision
DroneWatch will model at least two first-class source types:

- `civilian_report`
- `cooperative_telemetry`

## Context
The product combines uncertain human observations and structured live telemetry.
Treating them as one generic drone marker model would be misleading.

## Consequences
- domain models must preserve source type
- backend contracts must preserve source type
- map semantics must preserve source type
- Adaptive UI CUAS integration must preserve source type
