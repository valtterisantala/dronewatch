# Observation Package Contract v1

The Observation Package is the v1 contract for DroneWatch guided observation capture.

It represents a human-submitted observation plus the structured evidence captured around that observation. It is intentionally vendor-agnostic and is not tied to DJI, Remote ID, ADS-B, or any commercial drone provider path.

## Contract files

- `schema.json`: machine-readable JSON Schema for the contract shape.
- `examples/successful-tracked-observation.json`: strong guided capture with tracking and optional audio.
- `examples/weak-insufficient-observation.json`: low-quality observation that should remain visibly uncertain.
- `examples/observation-without-audio.json`: valid package without optional audio.

## Source semantics

Observation Package v1 uses:

- `sourceType`: `civilian_report`
- `packageKind`: `observation_package`

This keeps guided observations distinct from `cooperative_telemetry`. A package may later be joined against trusted reference data, but the package itself is not trusted telemetry and must not be displayed as confirmed truth.

## Top-level required fields

- `schemaVersion`: fixed to `observation_package.v1`
- `packageId`: globally unique package id
- `sourceType`: fixed to `civilian_report`
- `packageKind`: fixed to `observation_package`
- `createdAt`: package creation timestamp
- `captureSession`: capture-session metadata
- `humanReport`: user-declared report data
- `evidence`: sensor and trace evidence captured by the app
- `derivedEvidence`: deterministic derived features and quality signals
- `validationJoin`: metadata for future retrospective matching to trusted tracks
- `privacy`: redaction and retention hints

## Layer model

### Human report layer

`humanReport` contains what the observer explicitly declared:

- `observationType`
- `observerConfidence`
- optional `countEstimate`
- optional `note`

This layer is human input. It should be preserved separately from trace evidence.

### Tracking layer

`evidence.tracking` contains camera tracking evidence:

- `trackingStatus`
- `targetTrackId`
- `trackStartedAt`
- `trackEndedAt`
- `durationMs`
- `frameCount`
- `boundingBoxTrace`

Each bounding-box trace point includes timestamp, normalized bounding box, and optional confidence.

### Motion and heading layer

`evidence.motion` contains motion and device-orientation evidence:

- `devicePoseTrace`
- optional `bearingEstimate`
- optional `motionSummary`

This layer supports deterministic quality scoring and later map visualization without pretending to be aircraft telemetry.

### Optional audio-derived layer

`evidence.audio` is optional. When present, it can contain:

- `captured`
- `sampleWindow`
- optional `features`
- optional `quality`

Packages remain valid without audio evidence.

### Derived evidence and quality layer

`derivedEvidence` contains deterministic, explainable summary data:

- `qualityScore`
- `qualityTier`
- `insufficiencyReasons`
- `featureFlags`
- `mlReadiness`

This is not final ML classification. It is a baseline evidence-quality summary that later scoring and ML tasks can build on.

### Validation join layer

`validationJoin` contains metadata needed to later compare an observation against trusted reference tracks:

- time window
- observer/capture location when available
- rough bearing when available
- spatial uncertainty
- join keys such as geohash/time bucket

Reference-track matching is explicitly future work. This contract only ensures the package carries enough joinable metadata.

## Required vs optional rule

Required fields identify the package, preserve source semantics, and provide enough capture/evidence metadata for downstream review.

Optional fields are allowed when the app cannot capture them reliably, especially:

- audio evidence
- observer note
- exact coordinates
- bearing estimate
- ML candidate metadata

Consumers must treat missing optional evidence as missing evidence, not as negative evidence.

## Verification against issue #7

- Guided capture: represented by `captureSession` plus tracking/motion evidence.
- Deterministic quality scoring: represented by `derivedEvidence.qualityScore`, `qualityTier`, and insufficiency reasons.
- Map visualization: supported by `validationJoin.observerLocation`, time window, and optional bearing estimate.
- Future ML readiness: supported by trace evidence, feature flags, and `mlReadiness`.
- Future validated-reference matching: supported by `validationJoin`.
- Provider neutrality: no DJI/provider-specific fields exist in the contract.
