# ADR 0001: Use a single DroneWatch monorepo

## Status
Accepted

## Decision
DroneWatch will start as a single monorepo.

## Context
The product currently has tightly related concerns:
- mobile app
- backend
- contracts
- telemetry provider abstractions
- vendor adapters
- integration docs

Splitting these into separate repositories too early would increase contract drift and coordination overhead.

## Consequences
- shared domain and contracts can evolve coherently
- backend and app boundaries remain explicit inside one repo
- future extraction remains possible if scale later justifies it
