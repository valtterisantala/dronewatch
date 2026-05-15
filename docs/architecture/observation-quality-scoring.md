# Deterministic Observation Quality Scoring

Updated: May 15, 2026

## Status

Baseline scoring note for the guided-capture prototype.

This document supports GitHub issue #11 and depends on Observation Package v1. It defines observation-quality scoring only. It does not identify whether the observed object is a drone, bird, aircraft or anything else.

## Goal

Score how useful a captured observation is based on evidence collected by DroneWatch.

The score should answer:

> Was this observation captured well enough to support map awareness, review and later validation?

It should not answer:

> What object type was observed?

## Inputs

The first baseline uses fields already present in Observation Package v1:

- `evidence.tracking.durationMs`
- `evidence.tracking.frameCount`
- `evidence.tracking.continuityScore`
- `evidence.tracking.targetLostEvents`
- `evidence.tracking.reacquisitionEvents`
- `evidence.tracking.boundingBoxTrace[].confidence`
- `evidence.motion.bearingEstimate.uncertaintyDegrees`
- `evidence.motion.motionSummary.headingStabilityScore`
- `evidence.motion.motionSummary.motionSmoothnessScore`
- `validationJoin.observerLocation`
- `humanReport.observerConfidence`
- optional `evidence.audio.features`

Audio is optional and should not be required for a moderate or strong observation.

## Outputs

The scoring layer writes to `derivedEvidence`:

- `qualityScore`: number from `0` to `1`
- `qualityTier`: `weak`, `moderate` or `strong`
- `qualitySignals`: normalized component scores
- `reasonCodes`: explainable positive and negative reason codes
- `insufficiencyReasons`: reasons the package may be too weak for normal map display
- `compactFeatureSummary`: small review/debug summary

Observation Package v1 also allows `insufficient` as a pre-quality state for captures that should be stored for review but generally not shown as useful map observations.

## Component Scores

| Component | Weight | Description |
| --- | ---: | --- |
| Duration | 0.25 | Whether the target stayed tracked long enough |
| Continuity | 0.25 | Whether the track stayed continuous without frequent loss |
| Visual confidence | 0.20 | Confidence from bounding-box tracking samples |
| Heading confidence | 0.15 | Whether the heading estimate is stable enough to matter |
| Motion stability | 0.10 | Whether phone motion remained coherent during capture |
| Location availability | 0.05 | Whether observer location is available for map/validation use |

Audio can add positive reason codes, but it does not currently change the numeric score. This avoids punishing valid observations when microphone permission is unavailable or intentionally disabled.

## Baseline Rules

### Duration Score

| Evidence | Score |
| --- | ---: |
| `durationMs >= 10000` | 1.0 |
| `durationMs >= 6000` | 0.75 |
| `durationMs >= 3000` | 0.45 |
| `durationMs >= 1500` | 0.2 |
| otherwise | 0.0 |

### Continuity Score

Use `evidence.tracking.continuityScore` directly when present.

Apply a small penalty for repeated target loss:

```text
continuity = max(0, continuityScore - (targetLostEvents.length * 0.08))
```

### Visual Confidence

Use the mean of available `boundingBoxTrace[].confidence` values.

If no confidence values exist:

- use `0.35` when a non-empty bounding-box trace exists
- use `0` when no bounding-box trace exists

### Heading Confidence

Prefer `derivedEvidence.qualitySignals.headingConfidence` if already computed by native/shared capture logic.

Otherwise derive a rough score from `bearingEstimate.uncertaintyDegrees`:

| Uncertainty | Score |
| --- | ---: |
| `<= 15` degrees | 0.9 |
| `<= 30` degrees | 0.65 |
| `<= 60` degrees | 0.35 |
| missing or worse | 0.1 |

### Motion Stability

Use `motionSummary.motionSmoothnessScore` when present.

Fallback from `motionSummary.stability`:

| Stability | Score |
| --- | ---: |
| `stable` | 0.85 |
| `some_jitter` | 0.55 |
| `unstable` | 0.2 |
| missing | 0.3 |

### Location Availability

| Evidence | Score |
| --- | ---: |
| `observerLocation` with accuracy `<= 50m` | 1.0 |
| `observerLocation` with accuracy `<= 250m` | 0.7 |
| `observerLocation` without accuracy | 0.5 |
| missing location | 0.0 |

## Quality Labels

| Quality score | Label | Product meaning |
| --- | --- | --- |
| `>= 0.75` | `strong` | Useful, continuous observation with stable evidence |
| `>= 0.50` | `moderate` | Useful but has clear limitations |
| `>= 0.25` | `weak` | Stored and reviewable, but map display should be cautious |
| `< 0.25` | `insufficient` | Evidence is too limited for normal map awareness |

For civilian UX, labels should be explained as observation usefulness:

- strong: "Captured well"
- moderate: "Usable with limits"
- weak: "Limited evidence"
- insufficient: "Not enough evidence"

## Reason Codes

Positive reason codes:

- `sufficient_continuous_track`
- `stable_heading`
- `observer_location_available`
- `audio_supporting_evidence`
- `audio_not_required`

Limiting reason codes:

- `duration_below_strong`
- `tracking_too_short`
- `continuity_low`
- `tracking_lost`
- `low_visual_confidence`
- `unstable_heading`
- `poor_device_motion`
- `no_location`
- `audio_unavailable`
- `observer_low_confidence`

Reason codes should be deterministic and user-explainable. They are not hidden model features.

## Sample Logic

```text
score =
  durationScore * 0.25 +
  continuityScore * 0.25 +
  visualConfidence * 0.20 +
  headingConfidence * 0.15 +
  motionStability * 0.10 +
  locationAvailability * 0.05

if score >= 0.75:
  qualityTier = "strong"
else if score >= 0.50:
  qualityTier = "moderate"
else if score >= 0.25:
  qualityTier = "weak"
else:
  qualityTier = "insufficient"
```

## Example Coverage

The contract examples cover:

- strong: `packages/contracts/observation-package/v1/examples/successful-tracked-observation.json`
- moderate: `packages/contracts/observation-package/v1/examples/observation-without-audio.json`
- weak: `packages/contracts/observation-package/v1/examples/weak-scored-observation.json`
- insufficient: `packages/contracts/observation-package/v1/examples/weak-insufficient-observation.json`

## What Scoring Does Not Claim

Scoring does not claim:

- the object is a drone
- the object is hostile
- the object matches an official track
- the observation is confirmed truth
- the user is correct about what they saw

Scoring only claims that the captured evidence is more or less useful for awareness, review and later validation.

## Review Checklist

- Scoring uses captured DroneWatch evidence only.
- Outputs include quality label and reason codes.
- Weak, moderate and strong examples exist.
- Documentation is civilian-readable.
- The baseline avoids object identification and ML claims.
