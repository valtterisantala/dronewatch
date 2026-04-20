# AGENTS.md

This file defines the standing working rules for DroneWatch.

## 1. Project context

DroneWatch is a cross-platform product with three user-facing modes:

- **Report**
- **Map**
- **Fly**

It combines two core source types that must remain distinct:

- `civilian_report`
- `cooperative_telemetry`

The repo is intentionally structured as a monorepo with:
- mobile app
- backend
- contracts
- telemetry abstraction layer
- provider integrations
- integration-ready read APIs and contracts for downstream consumers

## 2. Human roles

The human owner of this repo is not acting as a hands-on coder.
He is the product designer, orchestrator, and tester.

Implications:
- do not assume the human wants CLI-heavy workflows
- do not assume the human will manually patch code after implementation
- prefer GitHub issues, draft PRs, and clear verification steps
- keep implementation handoff and review flow easy to follow in GitHub

## 3. Core workflow rule

The GitHub issue is the primary implementation prompt.

Do not require a separate long custom Codex prompt by default.
Only create or rely on a custom prompt when the work is unusually ambiguous, risky, exploratory, or architectural.

Standing repo rules belong here in `AGENTS.md`.
Task-specific instructions belong in the GitHub issue.

## 4. Two work modes

### A. Spike Mode

Use Spike Mode when the main goal is to reduce uncertainty.
Examples:
- vendor SDK proof-of-concept
- difficult debugging with unclear root cause
- architecture seam validation
- protocol feasibility testing

In Spike Mode:
- optimize for proof, not polish
- keep scope narrow
- answer one technical question at a time
- stop when the question is answered
- document what was proven, what was not, and what the next step should be
- do not silently expand a spike into broad product work

A spike is successful if it clearly shows one of:
- yes
- no
- yes, but only if
- no, because

### B. Delivery Mode

Use Delivery Mode when the path is already known well enough to implement.

In Delivery Mode:
- implement the GitHub issue as written
- keep scope tight
- respect acceptance criteria
- prepare a **draft PR** when the work is ready for review
- do not merge without explicit human approval

## 5. Scope discipline

Always:
- prefer one implementable slice per issue
- avoid bundling unrelated concerns
- avoid opportunistic refactors unless the issue clearly requires them
- avoid changing product semantics without calling it out explicitly
- avoid introducing vendor-specific logic into shared product/domain layers unless that boundary decision is intentional

If the issue starts expanding beyond its original goal:
- stop
- document the reason
- suggest the next task instead of silently broadening scope

## 6. Architecture guardrails

### Shared core vs vendor logic

- shared product code must stay vendor-agnostic where possible
- telemetry integrations must stay behind provider abstractions and native bridges
- vendor/protocol-specific logic belongs in provider integration areas, not scattered across the app core

### Source semantics

Do not flatten these into one generic marker model:
- `civilian_report`
- `cooperative_telemetry`

These source types must stay distinct in:
- domain models
- contracts
- backend read models
- UI semantics
- downstream consumer integrations

### External integration boundary

DroneWatch should expose versioned APIs and read models for downstream consumers.

External integrations should happen through explicit contracts, not:
- shared database access
- hidden internal coupling
- direct import of product internals into external systems

## 7. GitHub issue expectations

When implementing from an issue, treat these as the preferred sections:
- Goal
- Scope
- Non-goals
- Acceptance criteria
- UX / product constraints
- Technical notes
- Verification
- Dependencies / sequencing

Not every issue needs every section, but do not ignore the issue structure.

If a task is clearly too large for one PR, split it before implementation continues.

## 8. Build, test, and run expectations

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

## 9. Branch and PR expectations

- prefer small, reviewable PRs
- implementation should surface in a **draft PR** first
- the draft PR is the review quarantine
- do not assume code is ready for merge just because the implementation works locally
- no merge without explicit human approval

For spike work, the draft PR should make clear:
- what was proven
- what remains uncertain
- whether the code is disposable, promotable, or needs cleanup first

## 10. Review expectations

Review should be critical and concrete.
The question is not only “does it run?” but also:
- does it meet the issue goal?
- does it meet acceptance criteria?
- does it preserve UX/product intent?
- does it respect repo architecture?
- should the next step be another implementation task, a fix task, or a rethink?

## 11. When to stop and ask

Stop and surface a decision instead of guessing when:
- the issue depends on a missing product decision
- vendor/platform constraints contradict the current plan
- a requested change would break an existing architecture guardrail
- the implementation requires a broad restructure not implied by the task

Do **not** stop for minor choices that can be resolved reasonably from repo context.

## 12. Preferred implementation mindset

Default mindset:

> Implement the GitHub issue according to its acceptance criteria and this `AGENTS.md`. Keep scope tight and prepare a draft PR when the work is ready for review.

Spike mindset:

> Prove or disprove the technical question with the smallest useful change. Document what was learned and stop once the uncertainty is reduced enough for the next decision.
