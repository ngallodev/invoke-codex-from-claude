# ADR-0003: Persistence and Queue Strategy

Status: Proposed
Date: 2026-02-18
Deciders: `invoke-codex-from-claude` maintainers
Related: `docs/ADR-0001-control-plane-core-architecture.md`, `docs/ADR-0002-control-plane-language-selection.md`, `docs/STEERING.md`

## Decision
Use:
1. **Postgres** as the primary durable store for production.
2. **SQLite** as the local/dev single-node fallback.
3. **Internal database-backed worker queue** for initial orchestration execution.

Defer Temporal adoption to a later milestone with explicit scale/reliability triggers.

## Why
1. Fastest path to shipping without introducing workflow-platform overhead too early.
2. Keeps operational model simple while contracts and policy model stabilize.
3. Supports strong durability and replay requirements from the steering doc.
4. Gives a clear migration path to Temporal if scale/coordination complexity demands it.

## Scope of This Decision
Applies to the new TypeScript control-plane core only.
Does not change adapter execution scripts directly.

## Data Durability Requirements
Must persist at minimum:
- `Task` records
- `Run` records with state transitions
- `Event` timeline (append-only, correlated)
- `PolicyDecision` records
- `Artifact` metadata (log/summary references)

No in-memory-only execution path for production task/run lifecycle.

## Queue Model (Initial)
- Queue entries live in DB with explicit states:
  - `queued`, `claimed`, `running`, `waiting_approval`, `completed`, `failed`, `canceled`
- Workers claim tasks atomically.
- Worker claims have heartbeat + timeout/lease expiry.
- Retries use bounded attempts and backoff policy.
- Every transition emits an event with `correlation_id`.

## Alternatives Considered

### Temporal First
Pros:
- Strong workflow semantics, retries, timers, and visibility out of the box.

Cons:
- Additional infrastructure and operational complexity before core domain is stable.
- Slower early iteration while schemas/policy model are still moving.

### In-Memory Queue + Flat Files
Pros:
- Minimal setup.

Cons:
- Fails durability, replay, and auditability goals.
- Not acceptable for multi-agent governance requirements.

## Risks
- DB-backed queues can become contention hotspots under high concurrency.
- Homegrown worker semantics can drift toward ad hoc workflow logic.

## Mitigations
- Keep queue transitions explicit and contract-tested.
- Add idempotency keys for enqueue/run execution boundaries.
- Track queue lag, claim timeout rate, retry rate, and dead-letter volume.
- Reserve Temporal migration path behind stable event/state contracts.

## Revisit Triggers
Re-open this ADR if one or more are true:
1. Queue lag consistently exceeds SLO for two milestones.
2. Retry/dead-letter rates indicate orchestration complexity that internal queue cannot manage cleanly.
3. Multi-step long-running workflows require durable timers/compensation logic beyond current model.
4. Operational incident rate from queue mechanics exceeds acceptable threshold.

## Implementation Steps
1. Define DB schema for `tasks`, `runs`, `events`, `policy_decisions`, `artifacts`, `queue_items`.
2. Implement atomic claim/lease/heartbeat semantics.
3. Add queue and state-machine contract tests.
4. Add replay tooling that reconstructs full timeline from DB events.
5. Add metrics and alerts for queue health and transition failures.
