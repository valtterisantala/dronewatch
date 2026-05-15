# Git Strategy for DroneWatch Prototype Pivot

Updated: May 15, 2026

## Goal

Define a git workflow that:

- preserves DJI/provider spike work as parked research
- keeps active guided-capture MVP work visible and recoverable
- supports small logical commits on one prototype branch
- aligns with `AGENTS.md` working rules

## Guiding rules

1. The active milestone branch is `prototype/guided-capture-mvp`.
2. GitHub issues guide scope and acceptance criteria.
3. Completed slices should become commits, not stay only in stash or uncommitted local state.
4. No broad history rewrites unless explicitly approved.

## Role of `main`

`main` remains the reviewed trunk for accepted repository state.

During the guided-capture prototype phase, implementation work should happen on:

- `prototype/guided-capture-mvp`

The prototype branch is the reviewable place where issue slices accumulate until the first guided-capture MVP milestone is ready for a single draft PR.

## Parking DJI/provider research

Current DJI/provider work is valuable research and should be preserved as parked material, not deleted.

Parking strategy:

1. Create a long-lived parked branch from the research state.
2. Add one or more annotated tags for key milestones in that research line.
3. Keep parked branches read-mostly (no routine rebasing onto `main`).
4. If later product work needs a specific learning, copy it intentionally (small commit/cherry-pick), not by merging the full parked branch.

Recommended naming:

- parked branch: `parked/dji-provider-research-2026q2`
- tags: `archive/dji-poc-bootstrap-2026-04`, `archive/dji-poc-telemetry-2026-04`

## Active prototype branch

Use one active branch:

- `prototype/guided-capture-mvp`

Do not create a new branch or PR for every child issue during this prototype phase.

## Commit conventions

Use small commits that describe the completed slice.

Examples:

- `docs: add git strategy`
- `contracts: define observation package v1`
- `docs: define mobile capture architecture`
- `scoring: define deterministic quality baseline`
- `app: add guided capture prototype`
- `backend: add observation ingest foundation`
- `map: add awareness view MVP`

## Draft PR quarantine

Open one draft PR when the first working guided-capture MVP milestone is ready for review.

Draft PR purpose:

- review the milestone as an integrated prototype
- verify scope against issues #6 through #12
- keep `main` protected from incomplete prototype churn
- give the human owner one clear review surface

## Merge rules

1. Merge to `main` only after explicit human approval.
2. Prefer squash merge or curated merge for the prototype milestone.
3. Do not merge parked spike branches wholesale into `main`.
4. If parked spike code is promotable later, promote it intentionally in a separate delivery task.

## Prototype workflow

1. Work on `prototype/guided-capture-mvp`.
2. Use issues #7, #8, #11, #9, #10 and #12 as ordered scope references.
3. Complete one slice at a time.
4. Commit each completed slice with a focused message.
5. Keep parked DJI/provider work out of active implementation.
6. Open one draft PR when the first guided-capture MVP milestone is ready.

## Verification checklist

- DJI/provider spike work is explicitly parked (branch + tags), not deleted.
- Guided-capture work happens on `prototype/guided-capture-mvp`.
- New slices map to GitHub issue acceptance criteria.
- Completed slices become commits.
- One draft PR is used for the milestone review.

## What this enables

- DJI/provider work remains preserved and auditable.
- Guided-capture MVP work can move quickly without losing reviewability.
- Codex-assisted work remains visible, recoverable and low-friction for a non-coding product owner.
