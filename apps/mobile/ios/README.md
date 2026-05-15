# DroneWatch iOS Guided Capture Prototype

This is the first iOS prototype path for guided civilian observation capture.

Official domain: `dronewatch.fi`

iOS bundle identifier: `fi.dronewatch`

It supports GitHub issue #9:

- opens a camera-first capture screen
- lets the user tap to nominate a target area
- shows a bounding-box style tracking indicator
- shows simple duration, progress and quality guidance
- generates a local mock Observation Package preview with tracking duration and quality state

The prototype intentionally does not:

- identify whether the object is a drone, bird or aircraft
- use production-grade computer vision
- ingest data into the backend
- use DJI or commercial-drone telemetry
- require CocoaPods or vendor SDK setup

## Prerequisites

- Xcode 26+
- physical iPhone recommended for camera testing

The simulator can build the app, but camera preview requires a real device.

## Run

Open the Xcode project:

```bash
open DroneWatch.xcodeproj
```

Select an iPhone target and run.

## Test Flow

1. Launch the app.
2. Grant camera permission.
3. Point the phone at a flying object or any visible test target.
4. Tap the camera view to nominate the target area.
5. Tap `Start Tracking`.
6. Keep the object in the box while the progress and quality label update.
7. Tap `Finish Observation`.
8. Review the local Observation Package preview shown in the app.

## Expected Result

The app should show:

- live camera preview
- center reticle
- target bounding box after nomination
- tracking duration
- weak / moderate / strong guidance
- local JSON preview aligned with Observation Package v1 concepts

This is a UX and evidence-capture prototype. The tracking box is currently guided/simulated after user nomination, not production computer vision.
