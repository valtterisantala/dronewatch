# packages/contracts

This folder contains versioned contracts and DTO definitions.

Examples:
- report payloads
- observation package payloads
- map-feed payloads
- evidence ingest payloads
- downstream read-model payloads

This package is the main semantic boundary between:
- mobile app
- backend
- downstream consumers such as Adaptive UI CUAS

Contracts should be explicit, stable, and version-aware.

## Current contracts

- `observation-package/v1`: guided civilian Observation Package contract for camera-based capture evidence.
