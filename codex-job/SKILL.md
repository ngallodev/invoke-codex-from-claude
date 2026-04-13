---
name: codex-job
description: Delegate implementation-ready work to Codex (or other providers) with async execution, smart failure handling, and session resume. Invoke via /codex-job.
disable-model-invocation: false
---

# Purpose

Use `/codex-job` to offload implementation-ready tasks to Codex (or other model providers) while minimizing Claude token burn.

**Important**: This skill launches a **clean fork** - the delegated agent starts with NO conversation context. It receives ONLY:
- The task prompt you provide
- Any files explicitly specified
- The codebase itself (via the --repo path)

The delegated agent will NOT have access to:
- Prior conversation history from this Claude session
- Decisions or findings discussed earlier
- Context about why this task exists
- Your thought process or explorations

If the delegated agent needs context beyond the code, you must include it explicitly in the task prompt.

## Use When

- Acceptance criteria are clear.
- Design decisions are finalized.
- Test/verification strategy is defined.
- Task is execution-heavy (tests, multi-file changes, refactors, wiring).

## Do Not Use When

- Requirements are exploratory or ambiguous.
- Architecture/design is still changing.
- You need tight real-time interactive iteration.

## Delegation Guardrails

These rules apply to every delegated agent unless the task prompt explicitly overrides them:

- **No tests without explicit instruction.** Delegated agents must not write, edit, or run any test files unless the task prompt explicitly says to. This includes `tests/`, `test_*.py`, `*.spec.ts`, `*.test.ts`, and any other test file patterns.
- **Write set is authoritative.** The agent must only touch files listed in the task's write set. Any file outside that set is off-limits.
- **No scope expansion.** If a guardrail conflicts with code reality, the agent must stop and report before broadening scope.

## Core Workflow

1. Validate readiness (all four checks above must pass).
2. Choose model tier and provider:
   - Models are defined in `codex-job/references/available_models.jsonl`
   - Select by **tier** (low/medium/high) and optionally **provider** (openai/anthropic)
   
   **Available Providers:**
   - **OpenAI** (default): GPT-based Codex models optimized for code generation
     - Low: gpt-5.1-codex-mini (fast, cost-effective)
     - Medium: gpt-5.4-mini (balanced capability)
     - High: gpt-5.3-codex, gpt-5.4, gpt-5.1-codex-max
   - **Anthropic**: Claude models with different reasoning style
     - Low: claude-haiku-4-5 (fast, accurate)
     - Medium: claude-sonnet-4-6 (well-balanced)
     - High: claude-opus-4-6 (exceptional reasoning)
   - **Future**: Additional providers can be added to available_models.jsonl
   
   **Tier Guidelines:**
   - **Low tier**: Simple deterministic work
     - Single subsystem, clear write set, runnable tests
     - Example: "Fix typo in error message", "Add validation check"
   - **Medium tier**: Most implementation work (default recommended)
     - Cross-cutting changes, full-stack wiring, multiple coordinated files
     - Example: "Implement user authentication flow", "Add API endpoint with tests"
   - **High tier**: Complex reasoning (requires explicit user authorization)
     - Anything larger: break the task into smaller tickets first
     - If it genuinely cannot be split, ask the user before proceeding
     - Example: "Redesign database schema for performance", "Refactor core architecture"

3. Launch with: `scripts/invoke_codex_with_review.sh --repo <path> --task "<task>" --tier <low|medium|high> [--provider <openai|anthropic>]`
   - Add `--provider anthropic` to use Claude models instead of GPT (default: openai)
   - Prefer `--notify-cmd "scripts/notify_terminal.sh"` for feedback
   - Note: `scripts/` paths are skill-local runtime scripts
   - Override with `--model <model_id>` if you need a specific model (tier/provider recorded for telemetry)

4. Read summary JSON on completion; verify if risk/impact requires it.
5. If additional fixes are needed, resume with `--resume <session_id>` or `--resume latest`.
6. Append metrics using `scripts/write_delegation_metric.py`.

## Execution Mode: Fork vs Subagent

**Critical Distinction**: This skill launches a **CLEAN FORK** - no conversation context is shared.

### Use Forked Session (this skill) ✅
**What the delegated agent gets:**
- The task prompt you provide (--task flag)
- The codebase at --repo path
- Any files explicitly specified in the prompt
- Access to codebase-memory-mcp tools (graph, ADRs, architecture)

**What it does NOT get:**
- Your conversation history with Claude
- Findings from prior exploration or analysis
- Context about why this task exists or how you discovered it
- Your thought process, trade-offs considered, or decisions made

**Best for:**
- Task is **fully specified** in a self-contained prompt
- All necessary context can be expressed in the task description
- Implementation-heavy: writing code, running tests, multi-file refactors
- Can run async/background while you continue other work
- Want to minimize Claude token burn on execution work

**Example good use:**
```
Task: "Implement user login endpoint. 
Requirements: POST /api/login accepting {email, password}, 
validate against users table, return JWT token on success.
Write to src/routes/auth.ts. Include unit tests in tests/auth.test.ts.
Follow existing auth patterns in src/routes/register.ts."
```

### Use Subagent (via Agent tool) ✅
**What the subagent gets:**
- Full conversation context up to spawn point
- Your briefing in the Agent prompt
- Your findings, explorations, and decisions

**Best for:**
- Task needs **findings from current conversation** to proceed
- Research/exploration where results inform your next steps
- Code review requiring independent analysis
- Need synchronous results to make next decision
- Judgment calls depend on conversation context

**Example good use:**
"I found 3 possible places to add this validation. Review each approach 
(files A, B, C) and recommend which is most consistent with our patterns."

### Decision Tree

```
Does the task need context from our conversation?
├─ YES → Use Agent tool (subagent)
│         Cost: High (copies conversation)
│         Benefit: Has your context
│
└─ NO → Use this skill (fork)
          Cost: Low (clean start)
          Benefit: Fast, cheap, async
          Requirement: Task prompt must be self-contained
```

## Required Tracking

For each delegation:
- Append a brief entry to `work-log.md`.
- Append a detailed JSONL record to `delegation-metrics.jsonl`.
- Keep Claude and Codex token fields separate.

If rolling success rate for a task type drops below 70% (excluding environmental failures), tighten specs and reduce delegation scope until metrics recover.

## Quick Output Pattern

After launch, report:
- run id
- log path
- summary path (or pending)
- session id availability

## References

Load only what you need:
- `references/invocation-patterns.md`
- `references/failure-handling.md`
- `references/metrics-schema.md`
- `references/available_models.jsonl` (model registry)
- `assets/templates/delegation-metrics-entry.json`
