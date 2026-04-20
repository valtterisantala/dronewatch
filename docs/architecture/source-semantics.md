# Source semantics

## Why this matters

DroneWatch combines multiple data sources, but they are not equivalent forms of truth.

Flattening all incoming objects into one generic marker model would make the product misleading.

## Core source types

### `civilian_report`
A human-submitted observation.

Characteristics:
- uncertain
- sparse
- user-declared
- not continuous
- may lack exact location

### `cooperative_telemetry`
Voluntarily shared live drone telemetry from an operator session.

Characteristics:
- structured
- session-based
- continuous or near-continuous
- machine-derived through provider integrations
- stronger than a report, but still not equivalent to official fused truth

## Product rule

These source types must remain distinct in:

- domain models
- backend contracts
- map read models
- UI semantics
- downstream Adaptive UI CUAS integration

## Implication for maps

The map should never imply that:

- a civilian report is the same as live cooperative telemetry
- either source type is automatically a confirmed threat
- all drone-related markers are interchangeable

## Implementation consequence

Source type must be first-class in:

- `packages/domain`
- `packages/contracts`
- backend read models
- map-visible object definitions
