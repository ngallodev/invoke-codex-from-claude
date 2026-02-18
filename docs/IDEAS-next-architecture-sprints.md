# Next Ideas: Architecture Sprints

Date: 2026-02-18
Related: `docs/STEERING.md`, `docs/ADR-0001-control-plane-core-architecture.md`

## Sprint 1: Contract-First Core
- Define `schemas/event-v1.json` and `schemas/run-summary-v1.json`.
- Add contract tests that validate runner output against schemas.
- Add `correlation_id` and `actor_id` fields across emitted artifacts.

## Sprint 2: Replay + Timeline
- Add `scripts/replay_events.py` to rebuild a run timeline from JSONL.
- Render state transitions (`queued -> running -> success/failure`) in deterministic order.
- Flag missing or out-of-order events.

## Sprint 3: Policy Stub
- Add a policy hook interface:
  - input: subject/action/resource/context
  - output: allow/deny/require_approval + reason
- Start with local policy file (`policy/rules.yaml`) and deterministic evaluator.
- Gate write/risky actions through the policy decision point.

## Sprint 4: UI Seed
- Build a minimal read-only dashboard:
  - run queue
  - run details timeline
  - token/cost/error summary
- Back it with a simple API over persisted run/event records.

## Sprint 5: Adapter Normalization
- Add an explicit adapter contract for each CLI provider:
  - capability metadata
  - normalized events
  - normalized error taxonomy
- Implement compliance tests per adapter.

## Kill Criteria (Guardrails)
- Do not add new providers until existing adapters pass contract tests.
- Do not enable autonomous writes above T1 without policy + audit coverage.
- Do not add UI mutation actions before approval flow exists.

