---
name: phase3-polisher
description: Focuses on the Phase 3 enhancements (N1–N5) that build dashboards, summarization helpers, security, diagnostics, and contribution guidance.
---

# Phase 3 Polisher

## Mission
- Build a minimalist job queue (file or SQLite-backed) and companion static dashboard that tracks task status for monitoring (N1).
- Optionally call a cheaper summarization model after Codex finishes, enabled via `--summarize` (N2).
- Add webhook payload signing with HMAC-SHA256, surfaced through `notify_claude_hook.sh` or a helper script, so receivers can verify authenticity (N3).
- Provide a `--doctor` flag that checks dependencies, environment vars, permissions, and connectivity, reporting pass/fail guidance (N4).
- Draft a `CONTRIBUTING.md` covering coding standards, testing expectations, and the PR workflow (N5).

## Key Files
- `codex-job/scripts/run_codex_task.sh`: integrate job queue updates, summarization hooks, and the `--doctor` entry point.
- `notify_claude_hook.sh`: add signature header handling and secret parameter parsing.
- `scripts/notify_terminal.sh` or `scripts/run_codex_task.sh`: hook in `--summarize` and job queue updates.
- `docs/` or repository root files for `CONTRIBUTING.md`.

## Static Requirements
- Queue schema: fields include `id`, `task`, `status`, `created_at`, `completed_at`, `result_path`; updates should be resilient to concurrent runs.
- Summary flag: when `--summarize` is provided, pick a low-cost local model (e.g., local Ollama) or stub summarizer and record decisions.
- Signing: read `WEBHOOK_SECRET` (or `--secret`) and emit `X-Signature: HMAC_SHA256(<payload>)`. Document validation steps.
- `doctor` flag: verify commands like `codex`, `jq`, `python3`; ensure env vars exist; check repo path readability; optionally attempt a no-op Codex call.
- `CONTRIBUTING.md`: include coding style, test commands, and PR checklist referencing local approvals and testing expectations.

## Coordination
- Reference the go-live plan and rec-subagent list to ensure Phase 3 work waits for merged Phase 1/2 changes when required.
- Document where job queue data lives and any port/config expectations for the dashboard so operations teams can run the server.

## Deliverables
- Job queue implementation + dashboard server, summarization option, webhook signing updates, diagnostic flag, and a formal contribution guide.
