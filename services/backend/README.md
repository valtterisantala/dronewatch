# DroneWatch Backend

This backend foundation stores guided civilian Observation Packages and exposes simple inspection/read endpoints for the prototype milestone.

It supports GitHub issue #10 and PRD v2.

## Active Scope

The backend stores evidence behind an observation, not only a final human report.

Stored sections:

- observation metadata
- human report/session data
- tracking, motion and optional audio evidence
- derived quality features and reason codes
- joinable validation metadata such as time window, location, bearing and session id
- privacy/retention hints

## Non-goals

This foundation does not include:

- production database scaling
- user accounts or auth
- raw video/audio storage by default
- official sensor integration
- advanced ML pipelines
- commercial-drone telemetry ingest

## Run

The service uses Node.js built-in modules only.

```bash
cd services/backend
npm run start
```

Default server:

- `http://127.0.0.1:3100`

Default local store:

- `services/backend/.local-data/observations.jsonl`

Override the store location:

```bash
DRONEWATCH_BACKEND_DATA_DIR=/tmp/dronewatch-backend npm run start
```

## API

### `GET /health`

Returns service status and the active store path.

### `POST /observations`

Receives an Observation Package v1 JSON payload.

Minimum required semantics:

- `schemaVersion = observation_package.v1`
- `sourceType = civilian_report`
- `packageKind = observation_package`
- `packageId`
- `captureSession`
- `humanReport`
- `evidence`
- `derivedEvidence`
- `validationJoin`

The stored backend record separates:

- `metadata`
- `humanReport`
- `evidence`
- `derivedFeatures`
- `validationJoin`
- `privacy`
- `originalPackage`

### `GET /observations`

Lists stored observations with metadata, derived features and joinable metadata.

### `GET /observations/:id`

Returns one full stored backend record.

### `GET /map-feed`

Returns a small map-facing read shape for observations that include observer location.

This is a foundation for issue #12, not the final map API.

## Seed and Inspect

In one terminal:

```bash
cd services/backend
DRONEWATCH_BACKEND_DATA_DIR=/tmp/dronewatch-backend npm run start
```

In another terminal:

```bash
cd services/backend
DRONEWATCH_BACKEND_URL=http://127.0.0.1:3100 npm run seed:observation
curl --silent http://127.0.0.1:3100/observations
curl --silent http://127.0.0.1:3100/map-feed
```

Expected result:

- seed returns `201` response data with `observationId`, `receivedAt`, `packageHash` and stored sections
- `observations.jsonl` contains one JSON record per ingested package
- `/observations` shows metadata and derived features separately from evidence
- `/map-feed` exposes quality/location/bearing fields for civilian awareness

## Alignment Notes

The backend keeps `civilian_report` observations distinct from future source types.

It stores joinable metadata now so later work can compare observations against trusted reference tracks without changing the capture contract.
