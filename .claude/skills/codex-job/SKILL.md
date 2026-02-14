---
name: codex-job
description: Delegate implementation-ready work to Codex with async execution, smart failure handling, and session resume. Invoke via /codex-job.
disable-model-invocation: false
---

# Purpose

Use `/codex-job` to offload implementation-ready tasks to Codex while minimizing Claude token burn.

## Use When

- Acceptance criteria are clear.
- Design decisions are finalized.
- Test/verification strategy is defined.
- Task is execution-heavy (tests, multi-file changes, refactors, wiring).

## Do Not Use When

- Requirements are exploratory or ambiguous.
- Architecture/design is still changing.
- You need tight real-time interactive iteration.

## Core Workflow

1. Validate readiness (all four checks above must pass).
2. Choose model:
- `gpt-5.1-codex-mini`: simple deterministic work.
- `gpt-5.1-codex-max`: default for most implementation work.
- `gpt-5.2-codex`: complex reasoning.
- `gpt-5.3-codex`: highest-complexity tasks.
3. Launch Codex with `scripts/invoke_codex_with_review.sh` and prefer `--notify-cmd`.
4. Read summary JSON on completion; verify if risk/impact requires it.
5. If additional fixes are needed, resume with `--resume <session_id>`.

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
- `assets/templates/delegation-metrics-entry.json`
