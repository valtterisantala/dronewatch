# Map-Based Civilian Awareness MVP

Updated: May 15, 2026

## Status

MVP product/architecture spec for GitHub issue #12.

This document defines the first civilian-facing map interpretation layer for guided observations. It aligns with PRD v2, Observation Package v1 and the deterministic quality scoring baseline.

## Goal

Turn structured observations into simple map-based awareness for civilians.

The map should answer:

- where recent observations are appearing
- how recent they are
- how useful the captured evidence is
- what rough direction the observation indicates when known

The map should not require expert interpretation and should not expose raw sensor traces by default.

## Non-goals

The MVP map does not include:

- military/operator workflows
- Adaptive UI CUAS implementation
- official sensor fusion
- clustering engine
- advanced analytics dashboard
- real-time alerting
- object classification

## Source Data

The map uses structured Observation Package data, not raw free-text reports.

Minimum map-feed item:

```json
{
  "observationId": "obs_pkg_20260515_0001",
  "sourceType": "civilian_report",
  "observedAt": "2026-05-15T11:04:10Z",
  "qualityScore": 0.84,
  "qualityTier": "strong",
  "reasonCodes": ["sufficient_continuous_track", "stable_heading"],
  "location": {
    "lat": 60.1699,
    "lon": 24.9384,
    "accuracyMeters": 12
  },
  "roughBearingDegrees": 90.5,
  "spatialUncertaintyMeters": 120
}
```

This shape is already reflected by the prototype backend `GET /map-feed` endpoint.

## Civilian Map Semantics

Default marker language should describe observation usefulness, not certainty of object identity.

| Quality | Marker label | Civilian meaning | Suggested visual |
| --- | --- | --- | --- |
| strong | Captured well | The observation has useful supporting evidence | solid marker |
| moderate | Usable with limits | The observation is useful but has limitations | semi-solid marker |
| weak | Limited evidence | The observation is uncertain and should be interpreted cautiously | faint marker |
| insufficient | Not enough evidence | Store for review, normally hidden from default map | hidden by default |

Avoid labels like:

- confirmed drone
- threat
- hostile
- verified aircraft

## Marker Design

Each marker should communicate three things at a glance:

- quality
- recency
- rough direction when available

Recommended MVP marker components:

- color or fill strength for quality
- opacity decay for recency
- small heading wedge or arrow for rough bearing
- uncertainty ring for location/spatial uncertainty

Quality should be more prominent than technical score. The numeric score can appear in details, but the default map should use readable labels.

## Recency Rules

MVP default map window:

- show observations from the last 24 hours
- emphasize observations from the last 2 hours
- fade observations older than 6 hours
- hide observations older than 24 hours by default

Suggested recency labels:

- "Just now": less than 5 minutes
- "Recent": 5 to 60 minutes
- "Earlier today": 1 to 6 hours
- "Older": 6 to 24 hours

## Direction Rules

When `roughBearingDegrees` exists:

- render a small directional wedge/arrow from the marker
- label details as "Observed facing roughly east" or similar
- show uncertainty as approximate language, not precise navigation truth

When bearing is missing or low confidence:

- do not invent direction
- show "Direction unclear" in details
- use scoring reason codes to explain why

## Default Detail View

The detail view should stay civilian-readable.

Recommended fields:

- observation quality: "Captured well", "Usable with limits" or "Limited evidence"
- observed time: relative and absolute
- approximate location/area
- rough direction when available
- why this quality was assigned, translated from reason codes
- optional "technical details" disclosure for raw quality score and evidence summary

Do not show raw trace arrays by default.

## Reason Code Translation

Reason codes should be converted into plain language.

Examples:

| Reason code | Civilian text |
| --- | --- |
| `sufficient_continuous_track` | Object stayed in view long enough |
| `stable_heading` | Phone direction was stable |
| `observer_location_available` | Location was available |
| `duration_below_strong` | Tracking time was limited |
| `continuity_low` | Tracking was interrupted |
| `tracking_lost` | Object was lost during capture |
| `low_visual_confidence` | Visual tracking was uncertain |
| `unstable_heading` | Direction estimate was unstable |
| `poor_device_motion` | Phone movement made the capture harder to use |
| `no_location` | Location was unavailable |

## Filtering

MVP filters should be minimal:

- recency: last 2 hours, 6 hours, 24 hours
- quality: show weak observations on/off
- direction: show direction wedges on/off

Default:

- last 24 hours
- strong and moderate visible
- weak visible but faint, or behind a simple "show limited evidence" toggle if the map feels noisy
- insufficient hidden

## How The Map Uses Structured Observations

The map should use:

- `validationJoin.observerLocation` for marker placement
- `validationJoin.spatialUncertaintyMeters` for uncertainty ring
- `validationJoin.roughBearingDegrees` for direction
- `derivedEvidence.qualityTier` for marker prominence
- `derivedEvidence.reasonCodes` for plain-language explanations
- `validationJoin.timeWindow.startedAt` or equivalent for recency
- `sourceType` to preserve civilian-report semantics

It should not use:

- raw bounding-box trace as default UI
- raw gyro/accelerometer samples as default UI
- raw audio features as default UI
- any object-type claim that the package does not support

## Downstream Integration Path

The map-feed shape can later become a downstream integration surface.

Future consumers may need:

- stable observation ids
- source type
- quality score and label
- time window
- location and uncertainty
- rough bearing and confidence
- reason codes
- join keys for retrospective validation

This should remain a versioned API/read model boundary. Downstream systems should consume explicit map/read contracts, not internal database tables or app internals.

## Review Checklist

- The map is civilian-readable.
- Quality, recency and direction are clear without raw sensor metadata.
- Weak/moderate/strong observations have distinct semantics.
- Insufficient observations are not presented as normal map truth.
- The map uses structured Observation Package fields.
- Future downstream integration is preserved without becoming a current dependency.
