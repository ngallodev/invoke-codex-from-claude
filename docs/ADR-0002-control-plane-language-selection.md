# ADR-0002: Control Plane Language Selection

Status: Proposed
Date: 2026-02-18
Deciders: `invoke-codex-from-claude` maintainers
Related: `docs/ADR-0001-control-plane-core-architecture.md`, `docs/STEERING.md`

## Decision
Select **TypeScript** as the initial control-plane core language.

Keep Python/shell as adapter executors and normalization tooling, per ADR-0001.

## Why
1. Fastest path to a usable operator UI and API with shared types.
2. Strong event/API tooling for orchestration control-plane work.
3. Lower integration friction for dashboard, approvals, and real-time status views.
4. Keeps current adapters intact while moving state machine/policy logic into a typed service layer.

## What This Means
- Build control-plane API/workers in TypeScript.
- Define shared schema/types for `Task`, `Run`, `Event`, and `PolicyDecision`.
- Treat runners (`run_codex_task.sh`, provider adapters) as external executors.
- UI talks only to the control-plane API, never directly to adapter scripts.

## Rejected Alternative (For Now): Go Core
Go remains a valid fallback for later scale/perf hardening, but is not selected now because:
- UI and API iteration speed is the immediate bottleneck.
- Current phase values contract stabilization and product learning over raw runtime performance.

## Assumptions
- Team is comfortable operating Node services.
- Early deployment target is single-node or modest scale.
- Most near-term complexity is policy + observability + UX, not CPU-bound orchestration throughput.

## Risks
- Runtime reliability can degrade if worker concurrency/retry semantics are loosely implemented.
- TypeScript service boundaries can erode if adapter-specific logic leaks into core.

## Mitigations
- Enforce strict adapter/core boundaries via contract tests.
- Use explicit run state machine and idempotent event processing.
- Add queue backpressure and bounded concurrency from day one.
- Require ADR updates for any cross-layer exceptions.

## Revisit Triggers
Re-open this decision if one or more conditions are true:
1. Sustained queue pressure requires high-throughput worker tuning beyond acceptable complexity.
2. Control-plane memory/latency profiles become operationally unstable.
3. Team staffing shifts make Go materially faster to maintain than TypeScript.
4. Reliability SLOs are missed for two consecutive milestones.

## Next Implementation Steps
1. Create `schemas/` with versioned JSON schema for events and run summaries.
2. Scaffold control-plane service (`api`, `worker`, `store`) in TypeScript.
3. Add adapter contract tests that validate current runner outputs.
4. Build read-only timeline UI against control-plane event API.
