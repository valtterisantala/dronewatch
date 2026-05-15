# DroneWatch

DroneWatch is a cross-platform mobile product for shared drone awareness.

It combines three core modes:

- **Report** — civilians can quickly report a possible drone sighting
- **Map** — the app visualizes reported sightings and voluntary drone activity
- **Fly** — hobby drone operators can register a drone, start a flight session, and voluntarily share live location while flying

## Product boundary

DroneWatch is the upstream source system for:

- civilian reports
- cooperative drone telemetry
- drone registry
- flight sessions
- normalized map-facing read models

Adaptive UI CUAS is a downstream consumer of DroneWatch APIs and read models.
DroneWatch publishes. Adaptive UI CUAS consumes.

## Architecture principles

- one shared cross-platform app core
- telemetry integrations are pluggable
- vendor-specific logic stays behind provider adapters and native platform bridges
- backend contracts are normalized
- civilian reports and cooperative telemetry remain distinct source types

## Repo structure

```text
docs/
  prd/
  architecture/
  integration/
  decisions/

apps/
  mobile/

services/
  backend/

packages/
  domain/
  contracts/
  telemetry-core/

integrations/
  providers/

infra/
  cloudflare/
```

## Current focus

This repository begins with semantic foundation first:

- PRD
- architecture docs
- integration boundary docs
- key architectural decisions
- git strategy for pivot execution (`docs/architecture/git-strategy.md`)

Code scaffolding comes after those foundations are locked.
