# Adaptive UI CUAS integration

## Integration strategy

DroneWatch is the upstream producer.
Adaptive UI CUAS is the downstream consumer.

DroneWatch owns:
- civilian reports
- cooperative drone telemetry
- drone registry
- flight sessions
- normalized map-facing read models

Adaptive UI CUAS consumes DroneWatch data through versioned APIs and read models.

## Boundary rule

Adaptive UI CUAS should integrate with DroneWatch through APIs, not through:

- shared database access
- hidden internal imports
- direct coupling to backend internals

## Recommended v1 integration model

DroneWatch publishes read APIs such as:

- `GET /api/reports`
- `GET /api/live-drones`
- `GET /api/map-feed`

Adaptive UI CUAS consumes those APIs.

## Recommended read model semantics

DroneWatch read APIs should preserve explicit source types at minimum:

- `civilian_report`
- `cooperative_telemetry`

Adaptive UI CUAS may later:
- correlate
- group
- enrich
- prioritize

But that interpretation should happen inside CUAS, not by muddying DroneWatch source semantics.

## Direction of integration

For now, integration is one-way:

**DroneWatch -> Adaptive UI CUAS**

No write-back path is assumed in v1.

## Why this is the right split

This keeps ownership clear:

- DroneWatch is the source system for reports and cooperative telemetry
- Adaptive UI CUAS is the situational consumer and higher-level interpretation layer

This avoids:
- semantic confusion
- shared-internals drift
- accidental product entanglement
