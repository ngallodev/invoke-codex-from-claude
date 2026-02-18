# Steering Document: Multi-Agent Multi-CLI Orchestration

Last updated: 2026-02-18
Owner: `invoke-codex-from-claude` maintainers
Architecture ADR: `docs/ADR-0001-control-plane-core-architecture.md`

## Why This Exists
This repo started as command wrappers, evolved into a skill, and is now moving toward an application.
This document keeps implementation choices aligned to the target product and prevents random feature drift.

## North Star
Build a policy-first orchestration control plane for AI coding agents that can:
- Assign tasks across multiple CLIs/models (Claude, Codex, Gemini, Kilo, etc.)
- Run tasks across multiple repositories with isolated execution contexts
- Track cost/tokens/errors/permissions/trust decisions per action
- Maintain a complete auditable timeline of what every agent did, where, and why
- Support human approval gates for high-risk actions

## Product Thesis
Most teams can run agents; few can govern them.
Our value is not another chat UI. Our value is safe multi-agent operations with observability and enforceable policy.

## Scope Boundaries
In scope:
- Orchestrating existing CLIs and local/remote agents
- Unified event schema and audit logging
- Policy enforcement (authorization, trust levels, action controls)
- Multi-repo task routing and workspace isolation
- Operator UI for queue, status, approvals, replay, and diagnostics

Out of scope (for now):
- Training custom foundation models
- Replacing provider-specific IDE/chat UX
- Generic enterprise IAM product
- Full Kubernetes platform abstraction

## Guiding Principles
1. Policy before autonomy.
2. Observable by default.
3. Deterministic replay for every critical run.
4. Least privilege everywhere (repo, command, network, secrets).
5. Stable contracts first, adapters second, UI third.
6. Start narrow and deepen reliability before expanding provider count.

## Canonical Runtime Contract
Treat orchestration as three layers:
1. Adapter layer: provider/CLI-specific invocation and output normalization
2. Orchestrator core: task graph, scheduling, retries, approvals, state transitions
3. Control plane UI/API: operators, policy admins, audit consumers

All new implementation should preserve this separation.

## Minimal Data Model (Must Exist Early)
- `Task`: requested goal + constraints + target repo/context
- `Run`: one execution attempt for a task step
- `Agent`: logical executor identity (model/CLI/tooling profile)
- `PolicyDecision`: allow/deny/require-approval with reason
- `Event`: append-only timeline records (state changes, tool calls, errors, approvals)
- `Artifact`: logs, summaries, patches, diffs, metrics, outputs

## Policy Model (Initial)
Evaluate every sensitive action against a policy tuple:
`subject(agent/profile) x action(command/tool/op) x resource(repo/path/secret/network) x context(trust_level, environment, owner)`

Default posture:
- Unknown action => deny or require approval
- Write actions require explicit scope
- Secret access is explicit and time-bounded

## Trust Levels (Initial Draft)
- `T0`: read-only exploration
- `T1`: constrained writes (allowed paths and commands)
- `T2`: broad repo writes with approvals for risky ops
- `T3`: autonomous workflows in approved sandboxes

## Success Metrics
- Task completion rate by provider/model profile
- Mean time to recovery after run failure
- Cost per successful task (tokens + external compute)
- Approval latency for gated actions
- Policy violation rate and prevented high-risk actions
- Replay fidelity (can we reproduce final artifact and timeline?)

## Phased Plan
Phase A: Orchestration Kernel
- Standardize event schema and run state machine
- Normalize CLI output into one summary/event contract
- Add durable task/run persistence and queue execution

Phase B: Policy + Governance
- Implement policy engine integration (allow/deny/approval)
- Add trust-level profiles and action categories
- Ship immutable audit log views

Phase C: Control Plane UI
- Task board, run timeline, approval inbox
- Token/cost/error dashboards
- Per-agent and per-repo policy views

Phase D: Advanced Routing
- Dynamic model/provider routing by task type and SLO
- Reliability-based fallback chains
- Policy-aware auto-retry and escalation

## Decision Rubric (Use For PRs/ADRs)
Every non-trivial PR should answer:
1. Which north-star capability does this improve?
2. Which principle does it reinforce?
3. Which layer does it belong to (adapter/core/UI)?
4. What policy/observability impact does it have?
5. What is the rollback path?

## Build vs Buy: Recommended Prior Art
Use existing projects for primitives; keep custom code for orchestration semantics and policy UX.

Agent orchestration frameworks:
- LangGraph (`https://github.com/langchain-ai/langgraph`)
- Microsoft AutoGen (`https://github.com/microsoft/autogen`)
- CrewAI (`https://github.com/crewAIInc/crewAI`)

Workflow durability/scheduling:
- Temporal (`https://github.com/temporalio/temporal`)
- Argo Workflows (`https://github.com/argoproj/argo-workflows`)

LLM gateway/routing:
- LiteLLM (`https://github.com/BerriAI/litellm`)

Observability:
- OpenTelemetry Collector (`https://github.com/open-telemetry/opentelemetry-collector`)
- Langfuse (`https://github.com/langfuse/langfuse`)
- Grafana Loki (`https://github.com/grafana/loki`)
- Grafana Tempo (`https://github.com/grafana/tempo`)

Policy/authorization:
- Open Policy Agent (`https://github.com/open-policy-agent/opa`)
- OpenFGA (`https://github.com/openfga/openfga`)
- Casbin (`https://github.com/casbin/casbin`)

UI/agent interaction patterns:
- OpenHands (`https://github.com/All-Hands-AI/OpenHands`)
- CopilotKit (`https://github.com/CopilotKit/CopilotKit`)
- Flowise (`https://github.com/FlowiseAI/Flowise`)
- Langflow (`https://github.com/langflow-ai/langflow`)

## Explicit Anti-Patterns
- Adding provider-specific logic directly into core orchestration state machine
- Storing logs without correlation IDs and actor identity
- Shipping autonomy features without policy enforcement and audit trail
- Expanding provider count before stability metrics are acceptable

## Immediate Next Steps For This Repo
1. Add an ADR template and require ADRs for core architecture changes.
2. Define a versioned event schema (`task.*`, `run.*`, `policy.*`, `artifact.*`).
3. Introduce a policy decision interface stub (allow/deny/approval) even before full engine integration.
4. Add correlation IDs across runner, parser, invoke wrapper, and notifications.
5. Stand up a small JSONL replay tool for run/event timelines.
