---
name: phase1-shield
description: Focuses on stabilizing the core scripts across Phase 1 tasks (C1–C5) with secure secrets handling, strong error control, idempotent installs, and a tightened README.
---

# Phase 1 Shield

## Mission
- Secure `run_codex_task.sh` by reading secrets from environment variables, validating their presence, and preventing leaks in error messages (C1).
- Add strict error handling, timeouts, signal trapping, and guaranteed JSON summaries on every exit (C2).
- Vet the existing bash workflows by expanding shell tests, including ragged edge cases and notification coverage (C3).
- Make `install.sh` idempotent, provide `uninstall.sh`, and offer `--dry-run` previews for both (C4).
- Use documentation guidance from C5 to keep README up-to-date with these security and reliability improvements.

## Key Files
- `codex-job/scripts/run_codex_task.sh`: current home for C1–C3 logic.
- `codex-job/scripts/notify_claude_hook.sh`: ensure event notifications follow the new error paradigm set by C2.
- `install.sh` & new `uninstall.sh`: handle file copies, PATH updates, and profile changes idempotently.
- `README.md`: document new env vars, dry-run flags, and test invocation examples.

## Static Requirements
- Environment variables to check: `CODEX_API_KEY`, `CODEX_WEBHOOK_SECRET`, `WEBHOOK_SECRET`, `NOTIFY_CMD`, and any other credential referenced by the script.
- Fail fast with `set -euo pipefail`. Wrap the Codex call with `timeout` (e.g., 10m) and trap `SIGINT/SIGTERM` to clean temporary files.
- Guarantee `summary_json` always outputs a JSON blob with `exit`, `id`, `time`, and `error` fields even on exceptions for downstream consumers.
- Tests (Phase 1) should execute under `tests/` (create as needed) using `bats` or equivalent, mock `codex` via `PATH` shims, and assert notifications and JSON summaries.

## Coordination
- Reference `agent-notes/go-live-rec-detailed-plan.md` when aligning tasks C1–C5 with this agent.
- Note any uncovered dependencies (e.g., `timeout`, `jq`, `git`) in the go-live plan updates before merging.

## Deliverables
- Updated `run_codex_task.sh` with env verification, timeouts, traps, and JSON summary resilience.
- A more robust installation workflow (`install.sh`, `uninstall.sh`, `--dry-run`) with documentation.
- Expanded README sections describing how to run tests, the new security expectations, and troubleshooting steps tied to these scripts.
