# DroneWatch — PRD v2: Guided observation capture and map-based awareness

## 1. Product summary

DroneWatch is a cross-platform mobile product for guided civilian airborne-observation capture and map-based situational awareness.

The core product is no longer centered on hobby drone registration or direct commercial-drone telemetry. The product now starts from a simpler and stronger foundation:

1. A civilian opens the app into a camera-first capture experience.
2. The app guides the user to track a flying object in the viewfinder.
3. The app captures a structured observation evidence package.
4. The system assesses the observation’s quality and usefulness.
5. The observation is visualized on a map for civilian awareness.
6. The same structured data can later support machine learning and defence / official-system convergence.

The first version does **not** need to identify whether the flying object is a drone, bird or aircraft. The first version needs to determine whether the observation was captured well enough to matter.

---

## 2. Product thesis

Raw civilian reports are noisy. DroneWatch makes them more useful by guiding the capture process and storing the evidence behind each observation.

The product value is not just that many people can report sightings. The value is that the system can help ordinary people capture better observations, validate their usefulness and turn them into a shared map-based awareness layer.

In one sentence:

**DroneWatch turns everyday phones into guided sensors for airborne observations.**

---

## 3. Core user experience

The core UX is camera-first.

The user:
- opens the app
- sees a camera view with a reticle / guidance layer
- points at a flying object
- starts or confirms tracking
- sees a bounding box or target indicator around the object
- keeps the object tracked while the app gives real-time feedback
- completes the observation when the app has enough usable evidence

The UX should feel simple enough for a non-expert user under stress or uncertainty.

The app should not initially ask the user to classify the object. The app should focus on helping the user keep the object in view long enough to create a valid observation.

---

## 4. Core product modules

## 4.1 Capture

The capture module is the product’s foundation.

It provides:
- camera-first observation flow
- target tracking / bounding box UX
- real-time capture guidance
- tracking duration and stability measurement
- heading and motion capture
- evidence package generation

## 4.2 Map

The map is the immediate civilian value layer.

It shows:
- where observations are appearing
- how recent they are
- which observations look stronger
- what direction observations may indicate
- potential emerging areas of activity

The map should make structured observation data understandable without requiring expert interpretation.

## 4.3 Observation detail

Each observation should have a compact detail view.

It should prioritize civilian-readable information:
- where
- when
- direction
- reliability / quality
- how many people may have reported related activity later

It should avoid overwhelming civilians with raw sensor metadata.

## 4.4 History

Users should be able to view their own captured observations and their current status.

History can later support:
- local review
- reclassification
- user feedback
- model improvement workflows

---

## 5. Observation evidence package

Every completed capture should produce an Observation Package.

This package is the central data object of DroneWatch.

It should contain enough structured evidence to support:
- immediate deterministic quality assessment
- map visualization
- future machine learning
- future matching against validated reference tracks

## 5.1 Human report layer

Explicit user/session data:
- observation id
- session id
- started_at
- ended_at
- device location
- location status
- optional note
- optional manual confidence
- app version
- device/platform metadata

## 5.2 Tracking layer

Camera/tracking-derived evidence:
- tracking duration
- target acquired timestamp
- target lost events
- bounding box trace
- target position trace
- target size trace
- tracking confidence trace
- continuity metrics
- reacquisition events

## 5.3 Motion and heading layer

Device sensor evidence:
- compass heading trace
- gyroscope trace
- accelerometer trace
- device orientation trace
- motion smoothness metrics
- heading stability metrics
- final heading estimate
- heading confidence

## 5.4 Optional audio layer

Audio is optional and secondary in v1.

If captured, store derived features before raw audio by default:
- audio capture active / inactive
- audio level summary
- relevant band-energy summaries
- noise / wind proxy if available

Raw audio should be optional and explicitly enabled for testing or later consented capture.

## 5.5 Derived evidence layer

Computed quality outputs:
- observation quality score
- observation quality label: weak / moderate / strong
- continuity score
- stability score
- heading confidence
- reason codes
- compact feature summary

---

## 6. Reliability first

The first intelligence layer should be deterministic and explainable.

Before advanced machine learning, DroneWatch should already assess whether an observation is weak, moderate or strong using rules such as:
- did the object stay tracked long enough?
- was the tracking stable?
- did the phone movement remain coherent?
- was the heading estimate stable enough to matter?
- was the observation interrupted or reacquired repeatedly?

This creates immediate value and avoids overclaiming model capability before real-world data exists.

---

## 7. Machine learning direction

Machine learning becomes meaningful only if DroneWatch first captures the right kind of data.

The first ML target should not be:
- what exact drone is this?

The first ML target should be:
- how reliable and useful was this observation?

Future models can learn from:
- tracking duration
- bounding box continuity
- heading stability
- device motion patterns
- audio-derived features
- repeated observations
- eventual matching against validated reference tracks

Over time this can support:
- filtering weak observations
- grouping related sightings
- confidence scoring
- correlation across multiple observations
- movement-pattern estimation

---

## 8. Future validation and official data convergence

DroneWatch does not need official sensor integration at the moment of capture.

The key requirement is that observations are stored with enough joinable metadata:
- timestamp / time window
- location
- heading estimate
- heading confidence
- tracking trace
- quality score
- source/session id
- uncertainty values where possible

Later, official or trusted sensor tracks can be joined retrospectively using:
- time overlap
- geographic proximity
- heading / bearing alignment
- movement consistency
- sensor confidence

Principle:

**No live official integration is required now. Future validation requires joinable evidence.**

---

## 9. Dual-use positioning

DroneWatch starts as a civilian-facing observation and awareness tool.

For civilians, the immediate value is:
- guided observation capture
- shared map-based awareness
- better understanding of nearby airborne activity

The larger value is the foundation it creates:

**structured, validated and geolocated observation data that can later converge with official or military sensor systems.**

Capture creates the data. The map gives it civilian meaning first — and a defence integration path later.

---

## 10. Cross-platform architecture requirement

DroneWatch should be designed for iOS and Android from the beginning.

The recommended architecture is:
- shared cross-platform app shell
- native capture/tracking engines per platform
- common evidence package contract
- common backend ingest and read models

The app shell can be shared, but the camera/tracking/sensor implementation should be treated as native platform work where needed.

---

## 11. Backend architecture requirement

The backend should store more than final reports.

It should support:
- observation session records
- evidence traces
- derived feature summaries
- deterministic quality outputs
- map-ready read models
- future ML/replay/labeling workflows

The backend should expose normalized APIs and avoid coupling downstream consumers to internal tables.

Suggested API direction:
- `POST /observations`
- `POST /observations/:id/evidence`
- `GET /observations/:id`
- `GET /observations`
- `GET /map-feed`

---

## 12. Explicit non-goals for current build direction

The current build direction does not prioritize:
- DJI / Mavic telemetry integration
- hobby drone registration
- cooperative drone operator flight sharing
- broad drone manufacturer support
- exact drone-type identification
- hostile intent classification
- production-grade military integration
- official sensor integration at capture time

These may return later, but they are not the active product foundation.

---

## 13. First product milestone

The first product milestone should prove:

**A user can track a flying object in a camera view, the app can generate a structured Observation Package and the backend can store enough evidence to support deterministic quality assessment and map visualization.**

This milestone proves the product direction before advanced ML, official integration or broad platform scaling.
