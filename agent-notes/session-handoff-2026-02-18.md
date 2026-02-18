# Session Handoff (2026-02-18)

## Objective
Stabilize MVP go-live scope (C1-C5), unwind drift, and enforce architecture boundary:
- canonical runtime in `codex-job/scripts/`
- root `scripts/` are thin executable wrappers only

## Architecture Decisions (confirmed)
1. `codex-job/scripts/` is source of truth.
2. Root `scripts/` should delegate only (no duplicated runtime logic).
3. Summary schema standardized to lean keys with nested `legacy`.
4. MVP focus is C1-C5; Phase 2/3 features are deferred/optional.

## Key Changes Completed
- Rewrote canonical runner for MVP stability/security:
  - `codex-job/scripts/run_codex_task.sh`
  - Includes env validation, timeout handling, signal traps, guaranteed summary JSON output, tier mapping, doctor mode, event hooks.
  - Queue/cache removed from default execution path.
- Root wrappers now delegate to canonical scripts:
  - `scripts/run_codex_task.sh`
  - `scripts/invoke_codex_with_review.sh`
  - `scripts/notify_claude_hook.sh`
  - `scripts/notify_terminal.sh`
  - `scripts/parse_codex_run.py`
  - `scripts/verify_codex_work.sh`
- Install path now sources runtime scripts from canonical location:
  - `install.sh` uses `SCRIPT_SRC_DIR="$SCRIPT_DIR/codex-job/scripts"`.
- Deferred features gated in install:
  - `--include-experimental` flag to include queue/dashboard scripts.
- Removed dead root wrappers for queue server/util:
  - `scripts/job_queue.py`
  - `scripts/job_queue_server.py`
- Summary minifier updated to consume lean schema + nested legacy:
  - `scripts/summary_minifier.py`
- Added reassessment + checklist status doc:
  - `agent-notes/mvp-architecture-reassessment.md`
- Added short end-user guide:
  - `README-TLDR.md`
- README linked to TLDR and aligned with architecture.

## Tests / Validation Run
Passed:
- `bash tests/test_runner_and_parser.sh`
- `bash tests/test_invoke_and_notify.sh`
- `bash tests/test_install_dry_run.sh`
- `bash tests/test_agents_metadata.sh`
- `bats --tap --print-output-on-failure tests/test_run_codex_task.bats`

Notes:
- Installed `bats` via apt (`Bats 1.8.2`).
- Updated bats setup to be robust in this environment:
  - `tests/test_run_codex_task.bats` now conditionally loads helper and sets required env vars in `setup()`.

## Open / Deferred
- Phase 2/3 artifacts (queue/dashboard, extra docs/agents) still exist in repo but are not in MVP default flow.
- If desired, next pass can prune or archive non-MVP files more aggressively.

## Recommended Next Step After Restart
1. Review `agent-notes/mvp-architecture-reassessment.md` and this handoff.
2. Decide whether to:
   - keep deferred Phase 2/3 files in-tree behind opt-in (current), or
   - remove/archive them now for a stricter MVP branch.
