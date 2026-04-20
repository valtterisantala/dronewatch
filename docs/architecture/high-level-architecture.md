# DroneWatch high-level architecture

## Overview

DroneWatch is a cross-platform mobile product with three user-facing modes:

- **Report**
- **Map**
- **Fly**

The product combines two distinct upstream source types:

- `civilian_report`
- `cooperative_telemetry`

These source types must remain distinct all the way through the backend and map layer.

## High-level system shape

- shared mobile app core
- shared domain models
- normalized backend contracts
- pluggable telemetry provider architecture
- downstream consumer integration through versioned APIs

## Key product boundary

DroneWatch is the producer of report and telemetry data.
Adaptive UI CUAS is a consumer of DroneWatch read APIs.
Integration happens through versioned APIs and read models, not shared database access.

## Mermaid diagram

```mermaid
flowchart LR

    A["Shared mobile app<br/>Report | Map | Fly"]
    B["Shared domain layer<br/>User | Drone | Flight Session<br/>Civilian Report | Live Drone State | Map Object"]
    C["Telemetry provider facade<br/>connect() | startSession() | stopSession()<br/>subscribeTelemetry() | getCapabilities()"]

    subgraph P["Native platform bridges"]
        direction TB
        D1["iOS bridge"]
        D2["Android bridge"]
    end

    E["Vendor / protocol adapters<br/>DJI | MAVLink/MAVSDK | later Autel | later Parrot"]
    F["Backend APIs<br/>Reports | Drones | Flight Sessions<br/>Telemetry | Map Feed"]
    G["Storage / read models<br/>Reports | Drone Registry | Active Sessions<br/>Latest Telemetry | Telemetry History"]
    H["Consumers<br/>DroneWatch map | Later Adaptive UI CUAS"]

    A --> B
    B --> F
    B --> C
    C --> D1 & D2
    D1 --> E
    D2 --> E
    E --> F
    F --> G --> H
```

## Core architectural rules

1. The product core is shared.
2. Telemetry integrations are modular.
3. The app depends on capabilities, not brands.
4. The backend receives normalized telemetry, not raw vendor-specific models.
5. Reports and cooperative telemetry remain distinct source types.
