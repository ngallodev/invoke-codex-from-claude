---
name: codex-job
description: Delegate implementation-ready work to Codex
---

# Purpose

Use `/codex-job` to offload implementation-ready tasks to Codex.

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
2. Choose Interface and Model:

### Using Codex
- Choose Model: `gpt-5.1-codex-mini` (simple), `gpt-5.1-codex-max` (default), `gpt-5.2-codex` (complex)
- Launch with: `scripts/invoke_codex_with_review.sh --repo <path> --task "<task>"`
- Prefer `--notify-cmd "scripts/notify_terminal.sh"`.

3. Read summary JSON on completion; verify if risk/impact requires it.
4. If additional fixes are needed, resume with `--resume <session_id>` or `--resume latest`.
5. Append metrics using `scripts/write_delegation_metric.py`.

## Required Tracking

For each delegation:
- Append a brief entry to `work-log.md`.
- Append a detailed JSONL record to `delegation-metrics.jsonl`.
- Keep Claude and LLM token fields separate.

## Quick Output Pattern

After launch, report:
- run id
- log path
- summary path (or pending)
- session id availability

## References

- `references/invocation-patterns.md`
- `references/failure-handling.md`
- `references/metrics-schema.md`
- `assets/templates/delegation-metrics-entry.json`
- `scripts/run_codex_task.sh`
