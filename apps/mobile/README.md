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

## Current spike app

For Issue #2 (DJI POC 1/4), a narrow iOS bootstrap app lives in:

- `apps/mobile/ios`

It is intentionally limited to DJI connected-state confirmation and is not the full cross-platform product app.
