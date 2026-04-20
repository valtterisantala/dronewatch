# services/backend

This folder contains the DroneWatch backend.

Responsibilities:
- civilian report ingest and storage
- drone registry
- flight session lifecycle
- telemetry ingest
- normalized map-feed read models
- versioned APIs for downstream consumers such as Adaptive UI CUAS

This backend is the upstream source system for DroneWatch data.
Adaptive UI CUAS should consume versioned APIs from here rather than internal database structures.
