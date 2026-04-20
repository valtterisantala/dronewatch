# apps/mobile

This folder contains the DroneWatch cross-platform mobile product.

Core user-facing modes:
- Report
- Map
- Fly

Responsibilities:
- shared mobile UI and navigation
- shared app state
- backend API client
- map presentation
- drone registration and flight session UX

This layer should remain vendor-agnostic.
Drone-specific telemetry access belongs behind provider abstractions and native platform bridges.
