# ADR-0001: Control Plane Core Architecture

Status: Draft
Date: 2026-02-18
Deciders: `invoke-codex-from-claude` maintainers
Related: `docs/STEERING.md`

## Context
The repository is evolving from script wrappers into a multi-agent, multi-CLI orchestration application with policy enforcement, auditability, and UI operations.

Current runtime is shell/Python-heavy, which is good for adapters and iteration speed, but may not be ideal as the long-term control-plane backbone.

We need an architecture that:
- Supports durable task/run state and replay
- Enforces policy/approval gates consistently
- Exposes stable API contracts for a UI
- Avoids lock-in to implementation details of current scripts

## Decision Drivers
1. Reliability under concurrent multi-repo, multi-agent runs
2. Type safety and maintainability of core orchestration state machine
3. Integration surface with existing shell/Python adapters
4. Operational simplicity for self-hosting
5. Ability to ship UI early without major rewrites later

## Options Considered

### Option A: Python-First Monolith
Keep orchestration core, adapters, and API in Python.

Pros:
- Fast iteration with existing code
- Minimal immediate rewrite

Cons:
- Higher risk of control-plane complexity spreading into scripting style
- Harder to enforce strict boundaries between adapter and orchestration layers

### Option B: TypeScript Control Plane + Python/Shell Adapters
Build core orchestrator/API/UI backend in TypeScript; keep current runners as adapter executors.

Pros:
- Strong ecosystem for APIs + real-time UI
- Shared types between backend and frontend contracts
- Good fit for event-driven orchestration and developer tooling

Cons:
- Requires dual-runtime operations (Node + Python/shell)
- Some reliability concerns if job execution primitives are not rigorously designed

### Option C: Go Control Plane + Python/Shell Adapters
Build core orchestrator/API in Go; keep current runners as adapter executors.

Pros:
- Strong concurrency model and predictable deployment
- Good fit for long-running workers and queue processors
- Easy static binaries for operators

Cons:
- Slower UI/backend iteration than TypeScript
- More effort for full-stack speed if frontend team is JS-oriented

## Proposed Direction
Adopt a hybrid approach now:
1. Keep Python/shell as Adapter Layer only.
2. Introduce a new Control Plane Core in either TypeScript or Go behind stable contracts.
3. Build UI against the control-plane API, never directly against adapter scripts.

This preserves current momentum while creating an explicit migration boundary.

## Non-Negotiable Contracts
Before core-language choice, lock these contracts:
- Versioned Event Schema (`task.*`, `run.*`, `policy.*`, `artifact.*`)
- Policy Decision API (`allow`, `deny`, `require_approval`, reason metadata)
- Run State Machine (queued, running, waiting_approval, success, failure, canceled)
- Correlation IDs spanning task, run, agent, and artifacts

## Implementation Plan (Incremental)
Phase 1:
- Extract and formalize adapter outputs into versioned JSON schema.
- Add contract tests around runner/parser wrappers.

Phase 2:
- Scaffold control-plane service with persistent task/run store.
- Ingest adapter events and expose read API for UI.

Phase 3:
- Add policy decision points and approval workflow.
- Add operator UI (timeline, queue, approvals, cost/error dashboards).

Phase 4:
- Shift orchestration logic from scripts into control-plane core.
- Keep adapters thin and provider-specific.

## Consequences
Positive:
- UI can ship early with stable contracts.
- Core can evolve independently from provider adapters.
- Future language pivot remains practical without replacing adapters first.

Negative:
- Temporary complexity while two layers coexist.
- Requires discipline to prevent script-level feature creep.

## Open Questions
1. Core language choice: TypeScript vs Go for phase-2 scaffold.
2. Persistence default: SQLite/Postgres for task/run/event durability.
3. Queue primitive: internal worker queue vs Temporal-backed workflows.
4. Policy engine integration timing: stub first vs OPA/OpenFGA early.

## Review Trigger
Revisit this ADR when:
- First control-plane scaffold is merged, or
- A second CLI/provider adapter is added with advanced policy gating.
