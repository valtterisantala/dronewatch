# ADR 0004: Park DJI provider spike and pivot active product work to guided observation capture

## Status
Accepted

## Decision

DroneWatch will park the DJI / Mavic telemetry provider spike as valuable research and shift active product work toward guided civilian observation capture and map-based awareness.

## Context

The earlier DroneWatch direction included voluntary hobby drone telemetry, starting with a DJI / Mavic Air 2 proof of concept. That work remains useful as a future integration path, but it is no longer the active product foundation.

The stronger product direction is now:

- camera-first guided observation capture
- structured observation evidence packages
- deterministic reliability assessment
- civilian map-based situational awareness
- future machine learning based on collected evidence
- future convergence with official or military sensor systems through joinable data

## Consequences

- DJI/provider integration work should not drive the initial product roadmap
- existing DJI work should be preserved, not deleted
- active implementation issues should focus on capture, evidence, backend storage and map visualization
- future drone telemetry integrations may return later as a separate workstream
- PRD v2 supersedes the earlier broader product direction for current implementation planning
