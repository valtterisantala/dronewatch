# DJI bootstrap POC (Issue #2)

This folder contains the minimal DJI bootstrap verification path for:

- registration / initialization success confirmation
- supported product-chain detection
- developer-visible connection-state output
- direct iOS DJI Mobile SDK direction confirmation

Scope is intentionally narrow for POC 1/4.
It does **not** include telemetry read, normalization, backend ingest, or polished UX.

## Files

- `run-bootstrap-check.sh`: validates bootstrap + connected-state requirements
- `connection-state.example.env`: sample state input file

## How to run

From repo root:

```bash
./integrations/providers/dji/bootstrap/run-bootstrap-check.sh
```

Or with an iOS probe generated state file:

```bash
./integrations/providers/dji/bootstrap/run-bootstrap-check.sh --env-file /path/to/dji-connection-state.env
```

## Expected output

On success:

- logs SDK manager state, registration state, connected product class/model
- confirms supported chain detection:
  - `SDKManager -> BaseProduct -> AIRCRAFT (<model>)`
- confirms direct iOS SDK direction (no Bridge App requirement)
- exits `0`

On failure:

- prints which state checks failed
- exits non-zero

## Environment and setup assumptions

- direct iOS DJI Mobile SDK probe is responsible for producing connection state values
- this script consumes those values as an env file for deterministic developer verification
- required fields:
  - `DJI_SDK_MANAGER_STATE`
  - `DJI_REGISTRATION_STATE`
  - `DJI_BASE_PRODUCT_CONNECTED`
  - `DJI_CONNECTED_PRODUCT_CLASS`
  - `DJI_CONNECTED_PRODUCT_MODEL`
- `DJI_SUPPORTED_PRODUCT_CLASSES` is optional (defaults to `AIRCRAFT`)
- Bridge App mode is intentionally out of scope for this slice

## Hand-off to next integration task

This bootstrap establishes a stable connection-state contract for providers.
Telemetry-read is now implemented in the iOS probe and app UI. Next issue should:

- map raw DJI telemetry into the shared DroneWatch cooperative telemetry contract
- publish telemetry to the intended app/backend integration path
- keep this bootstrap verification step as a preflight check
