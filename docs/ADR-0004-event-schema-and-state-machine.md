# ADR-0004: Event Schema and Run State Machine

Status: Proposed
Date: 2026-02-18
Deciders: `invoke-codex-from-claude` maintainers
Related: `docs/ADR-0001-control-plane-core-architecture.md`, `docs/ADR-0002-control-plane-language-selection.md`, `docs/ADR-0003-persistence-and-queue-strategy.md`, `docs/STEERING.md`

## Decision
Define a versioned event contract (`v1`) and a strict run state machine as core platform invariants.

All adapters and control-plane components must emit/consume these contracts. Provider-specific fields are allowed only under namespaced metadata.

## Event Envelope (v1)
Every event must contain:
- `schema_version`: `"event.v1"`
- `event_id`: unique ID
- `event_type`: namespaced type (`task.*`, `run.*`, `policy.*`, `artifact.*`, `system.*`)
- `occurred_at`: ISO-8601 UTC timestamp
- `correlation_id`: end-to-end trace ID
- `task_id`: nullable
- `run_id`: nullable
- `agent_id`: nullable
- `actor_type`: `system | agent | user`
- `actor_id`: nullable
- `payload`: object
- `meta`: object (optional; provider-specific data only)

## Event Type Taxonomy (v1)
Required initial types:
- `task.created`
- `task.queued`
- `task.canceled`
- `run.created`
- `run.claimed`
- `run.started`
- `run.progress`
- `run.waiting_approval`
- `run.approval_granted`
- `run.approval_denied`
- `run.retry_scheduled`
- `run.completed`
- `run.failed`
- `run.canceled`
- `policy.evaluated`
- `artifact.recorded`
- `system.warning`
- `system.error`

## Run State Machine (v1)
Canonical run states:
- `queued`
- `claimed`
- `running`
- `waiting_approval`
- `retry_scheduled`
- `completed`
- `failed`
- `canceled`

Allowed transitions:
1. `queued -> claimed`
2. `claimed -> running`
3. `running -> waiting_approval`
4. `waiting_approval -> running` (on approval)
5. `waiting_approval -> failed` (on denial)
6. `running -> retry_scheduled`
7. `retry_scheduled -> queued`
8. `running -> completed`
9. `running -> failed`
10. `queued|claimed|running|waiting_approval|retry_scheduled -> canceled`

Invalid transitions must be rejected and logged as `system.error`.

## Policy Event Contract (v1)
`policy.evaluated.payload` must include:
- `decision`: `allow | deny | require_approval`
- `subject`: normalized subject identity
- `action`: normalized action identifier
- `resource`: normalized resource identifier
- `reason_code`: stable machine-readable reason
- `reason_text`: human-readable explanation

## Artifact Event Contract (v1)
`artifact.recorded.payload` must include:
- `artifact_type`: `log | summary | patch | diff | metrics | transcript | other`
- `uri`: stable artifact reference/path
- `checksum`: optional hash
- `size_bytes`: optional

## Idempotency and Ordering Rules
- `event_id` must be unique.
- Consumers must be idempotent on `event_id`.
- Ordering guarantee is per `run_id` by logical sequence number or monotonic `occurred_at` + tie-breaker.
- Cross-run ordering is best effort only.

## Validation Requirements
1. Add JSON schema files:
   - `schemas/event.v1.json`
   - `schemas/run-state-machine.v1.json` (or equivalent declarative transition rules)
2. Add contract tests:
   - adapter output event validation
   - transition validity tests
   - invalid transition rejection tests
3. Add replay tests that reconstruct a run timeline from stored events.

## Why
This prevents early architecture drift and lets UI/policy/queue work progress independently with stable contracts.

## Risks
- Over-constraining early event payloads can slow adapter evolution.
- Under-specifying fields weakens audit and replay fidelity.

## Mitigations
- Keep envelope strict, payloads extensible.
- Require schema-version increments for breaking changes.
- Allow provider-specific metadata only in `meta` namespace.

## Revisit Triggers
Re-open this ADR if:
1. Two or more adapters need incompatible payload semantics under current taxonomy.
2. Replay fidelity gaps appear in production incident reviews.
3. Approval/policy workflows require additional explicit state transitions.
