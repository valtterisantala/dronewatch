# AGENTS.md

This file defines the standing working rules for DroneWatch.

## 1. Project context

DroneWatch is a cross-platform product for guided civilian airborne-observation capture and map-based situational awareness.

The active product direction is defined in:

- `docs/prd/dronewatch-prd-v2-guided-capture-and-map.md`
- `docs/decisions/0004-park-dji-provider-spike.md`

DroneWatch now starts from:

- camera-first guided observation capture
- target tracking / bounding-box UX
- structured Observation Package generation
- deterministic observation quality assessment
- map-based civilian awareness
- future ML readiness through structured evidence
- future convergence with official or military systems through joinable data

The current build direction does **not** prioritize:

- DJI / Mavic telemetry integration
- hobby drone registration
- cooperative drone operator flight sharing
- broad drone manufacturer support
- exact drone-type identification
- official sensor integration at capture time

Those are parked or future workstreams unless explicitly reactivated.

## 2. Human roles

The human owner of this repo is not acting as a hands-on coder.
He is the product designer, orchestrator and tester.

Implications:

- do not assume the human wants CLI-heavy workflows
- do not assume the human will manually patch code after implementation
- prefer GitHub-visible state, clear commits and reviewable summaries
- keep implementation handoff and review flow easy to follow

## 3. Current prototype-phase workflow

Until the first working guided-capture prototype milestone is reached, this repo uses a lightweight prototype workflow.

Use one active prototype branch for the current milestone:

- `prototype/guided-capture-mvp`

Issues guide the work, but each issue does **not** need its own branch or PR during this phase.

Preferred prototype-phase flow:

1. Work on `prototype/guided-capture-mvp`.
2. Use GitHub issues as scope and acceptance-criteria references.
3. Make small, logical commits for each completed slice.
4. Keep the branch in a recoverable state.
5. Do not hide completed work only in a stash.
6. Open one draft PR when the first prototype milestone is ready for review.

The first milestone is:

> A user can track a flying object in a camera view, the app can generate a structured Observation Package and the backend can store enough evidence to support deterministic quality assessment and map visualization.

## 4. GitHub issue role

The GitHub issue is the primary task reference.

Do not require a long custom prompt by default.
Task-specific instructions belong in the GitHub issue.
Standing repo rules belong here.

For the guided-capture MVP, the main epic is:

- #6 Guided observation capture MVP

Key child issues:

- #7 Observation Package contract
- #8 mobile capture architecture
- #9 guided tracking capture prototype
- #10 backend observation/evidence ingest foundation
- #11 deterministic observation quality scoring baseline
- #12 map-based civilian awareness view MVP

## 5. Work modes

### A. Spike Mode

Use Spike Mode when the main goal is to reduce uncertainty.

Examples:

- camera tracking feasibility
- native capture architecture seam validation
- difficult debugging with unclear root cause
- protocol or SDK feasibility testing

In Spike Mode:

- optimize for proof, not polish
- keep scope narrow
- answer one technical question at a time
- stop when the question is answered
- document what was proven, what was not and what the next step should be
- do not silently expand a spike into broad product work

A spike is successful if it clearly shows one of:

- yes
- no
- yes, but only if
- no, because

### B. Delivery Mode

Use Delivery Mode when the path is known enough to implement.

In Delivery Mode:

- implement the issue as written
- keep scope tight
- respect acceptance criteria
- commit changes in a logical slice
- defer draft PR creation until the prototype milestone is ready, unless the human explicitly asks for a separate PR

## 6. Scope discipline

Always:

- prefer one implementable slice at a time
- avoid bundling unrelated concerns into one commit
- avoid opportunistic refactors unless the issue clearly requires them
- avoid changing product semantics without calling it out explicitly
- avoid reactivating parked DJI/provider work unless explicitly requested

If the work starts expanding beyond its original goal:

- stop
- document the reason
- suggest the next task instead of silently broadening scope

## 7. Architecture guardrails

### Guided capture first

The product is not currently a drone registration or commercial-drone telemetry product.
The active foundation is guided civilian observation capture.

### Observation Package as central object

The app must capture evidence behind the observation, not only a final report.

The Observation Package should preserve:

- human report/session metadata
- tracking evidence
- motion and heading evidence
- optional audio-derived evidence
- derived quality and reason-code outputs
- joinable metadata for future validation against trusted reference tracks

### Source semantics

Do not flatten product concepts into one vague marker or report model.
At minimum, keep these concepts distinct:

- captured observation evidence
- derived observation quality
- map-ready civilian awareness object
- future downstream consumer feed

### External integration boundary

DroneWatch should expose versioned APIs and read models for downstream consumers.

External integrations should happen through explicit contracts, not:

- shared database access
- hidden internal coupling
- direct import of product internals into external systems

## 8. Build, test and run expectations

When code exists:

- use the repo’s documented commands
- prefer repeatable scripts and documented commands over one-off local hacks
- update docs when commands or setup change materially

When code does **not** exist yet for a surface:

- do not invent fake commands
- add or update documentation instead of pretending the build/test path already exists

If a new runnable surface is introduced, document:

- how to run it
- how to test it
- key prerequisites
- key environment assumptions

## 9. Branch and commit expectations

During prototype phase:

- use `prototype/guided-capture-mvp` as the main working branch
- do not create a new branch/PR for every small issue unless explicitly asked
- commit completed slices rather than leaving them only in stash or uncommitted local state
- keep commits small enough to review later
- use commit messages that identify the slice, for example:
  - `docs: add git strategy`
  - `contracts: define observation package v1`
  - `docs: define mobile capture architecture`
  - `scoring: define deterministic quality baseline`
  - `app: add guided capture prototype`
  - `backend: add observation ingest foundation`
  - `map: add awareness view MVP`

A stash may be used temporarily, but completed task work should become visible as commits on the prototype branch before moving meaningfully to the next slice.

## 10. Review expectations

Review should be critical and concrete.
The question is not only “does it run?” but also:

- does it meet the issue goal?
- does it meet acceptance criteria?
- does it preserve UX/product intent?
- does it respect repo architecture?
- should the next step be another implementation task, a fix task or a rethink?

The first major review point is the draft PR for the guided-capture MVP milestone.

## 11. When to stop and ask

Stop and surface a decision instead of guessing when:

- the issue depends on a missing product decision
- platform constraints contradict the current plan
- a requested change would break an existing architecture guardrail
- implementation requires a broad restructure not implied by the task
- the work would reactivate parked DJI/provider scope

Do **not** stop for minor choices that can be resolved reasonably from repo context.

## 12. Preferred implementation mindset

Prototype-phase mindset:

> Work through the guided-capture MVP issues on `prototype/guided-capture-mvp`. Keep scope tight, make small logical commits and preserve visible repo state. Open one draft PR when the first prototype milestone is ready for review.

Spike mindset:

> Prove or disprove the technical question with the smallest useful change. Document what was learned and stop once the uncertainty is reduced enough for the next decision.
