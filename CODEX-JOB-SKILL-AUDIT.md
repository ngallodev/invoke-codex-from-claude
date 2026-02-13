# Codex-Job Skill Deep Audit

Date: 2026-02-13
Reviewer: Codex (GPT-5)
Scope: `.claude/skills/codex-job/SKILL.md` and related scripts
Selected push target: Claude hook callback (no polling)

## Audit Progress

- [x] Read skill definition and tool file
- [x] Read and compare implementation scripts (`run`, `invoke`, `verify`, `parse`)
- [x] Run existing tests (`tests/test_runner_and_parser.sh`)
- [x] Reproduce critical failure-path behavior
- [x] Reproduce metadata escaping bug with quoted task text
- [x] Produce concrete rewrite proposals
- [x] Define push-notification architecture (Claude callback first)
- [x] Implement critical script fixes (failure-path handling, no-race meta selection, quote-safe metadata)
- [x] Implement push notification plumbing (`--notify-cmd`, `--event-stream`, callback helper script)
- [x] Add tests for critical fixes and notifications
- [x] Update skill/docs to match implemented behavior

## Implementation Status (Completed)

### Fixed

- `scripts/invoke_codex_with_review.sh`
  - Non-zero initial runs no longer short-circuit before smart classification.
  - Review flow binds to exact run metadata parsed from runner output (no `latest-file` race).
  - Added wrapper lifecycle event emission (`review_started`, `review_completed`).

- `scripts/run_codex_task.sh`
  - Metadata JSON generation is now quote-safe/newline-safe (env-based Python serialization).
  - Added event emission support:
    - `--notify-cmd "<command>"`
    - `--event-stream <path>`
  - Emits `run_started` and `run_completed` events.

- `scripts/notify_claude_hook.sh` (new)
  - Reads JSON event payload from stdin.
  - Sends callback POST via curl (`--url` or `CLAUDE_HOOK_URL`).
  - Supports `--dry-run` for validation.

- Tests (new coverage)
  - `tests/test_invoke_and_notify.sh`:
    - quote-safe task metadata
    - run event emission
    - environmental non-zero treated as success
    - real-failure review trigger + wrapper events

## Findings (Prioritized)

### 1) Smart failure handling does not run on non-zero exits (Critical)

File: `scripts/invoke_codex_with_review.sh`
Lines: `2`, `40-41`

`set -e` causes immediate exit when `run_codex_task.sh` returns non-zero, so the post-run classification/review logic is skipped.

Observed repro: wrapper exited with code `2` directly and did not execute smart detection/review.

### 2) Metadata write path breaks with quoted task text (Critical)

File: `scripts/run_codex_task.sh`
Lines: `251-268`, especially task embedding at `257`

The Python heredoc receives raw shell interpolation inside quoted string literals. Tasks containing quotes/newlines can produce invalid Python syntax and fail the run.

Observed repro: `--task 'Fix "quoted" task'` generated Python `SyntaxError`.

### 3) Review flow can attach to wrong run under concurrency (High)

File: `scripts/invoke_codex_with_review.sh`
Line: `46`

Using `ls -t runs/codex-run-*.meta.json | head -1` is race-prone if multiple runs happen close together. It may pick another run's metadata/session.

### 4) Skill docs and script behavior conflict on error classification (High)

Doc: `.claude/skills/codex-job/SKILL.md` lines `103-106`
Script: `scripts/invoke_codex_with_review.sh` line `77`

Skill says `command not found: codex` is environmental; script marks it as real failure trigger.

### 5) Verification flow is repo-specific and not generally reusable (Medium)

File: `scripts/verify_codex_work.sh`
Lines: `125-126`

`--run-tests` only runs `tests/test_runner_and_parser.sh`. This is useful locally but too narrow for general project verification.

### 6) Syntax check target selection may include unrelated changes (Medium)

File: `scripts/verify_codex_work.sh`
Lines: `92`, `104`

`git diff --name-only HEAD` checks working tree deltas globally, not just files changed by the specific run, risking noise from pre-existing edits.

### 7) Tool implementation claims "fire-and-forget" but blocks (Medium)

File: `.claude/skills/codex-job/tools/codex_task.py`
Lines: `67-73`

It uses blocking `subprocess.run(... timeout=300)`. That is not fire-and-forget behavior.

### 8) Stale/uncertain model guidance in skill text (Low)

File: `.claude/skills/codex-job/SKILL.md`
Lines: `60-64`

Hardcoded model recommendations may age quickly; better to describe these as examples or map to aliases.

## Rewrite Proposals

### A) Make failure classification path executable

File: `scripts/invoke_codex_with_review.sh`

- Wrap first runner call with `set +e` / `set -e`
- Capture exit code explicitly
- Continue logic regardless of runner non-zero
- Exit only after classification/review decision

### B) Bind review to exact launched run (remove race)

File: `scripts/invoke_codex_with_review.sh`

- Parse `meta_file=` directly from runner stdout for this invocation
- Stop using "latest meta file" lookup

### C) Make metadata JSON generation safe

File: `scripts/run_codex_task.sh`

- Replace Python string interpolation with safe JSON builder:
  - Preferred: `jq -n --arg ...`
  - Alternative: Python reads values from environment variables

### D) Unify error taxonomy across docs + script

Files:
- `scripts/invoke_codex_with_review.sh`
- `.claude/skills/codex-job/SKILL.md`

Choose one policy for `command not found: codex` and align both places.

### E) Generalize verification commands

File: `scripts/verify_codex_work.sh`

Add optional flags:
- `--test-cmd "<command>"`
- `--changed-files-cmd "<command>"`

Keep current behavior as fallback defaults for this repo.

### F) Clarify or rework `codex_task.py`

File: `.claude/skills/codex-job/tools/codex_task.py`

Either:
- make it true background (`subprocess.Popen`) and return immediate identifiers, or
- clearly document it as blocking utility and remove fire-and-forget claim.

## Push Notifications (No Polling) Plan

Target: Claude hook callback.

### Event Model

Emit structured events:
- `run_started`
- `run_completed`
- `run_failed`
- `review_started`
- `review_completed`

### Script Changes

1. `scripts/run_codex_task.sh`
- Add `--notify-cmd "<shell command>"`
- Add event emitter helper that sends compact JSON to notify command

2. `scripts/invoke_codex_with_review.sh`
- Forward `--notify-cmd`
- Emit review lifecycle events

3. New helper: `scripts/notify_claude_hook.sh`
- Accept event JSON
- Post to Claude callback endpoint (or invoke local Claude hook command)

### Minimal Event Schema

```json
{
  "event": "run_completed",
  "run_id": "20260213-123000-12345",
  "session_id": "uuid-or-null",
  "repo": "/path",
  "exit_code": 0,
  "summary_file": "runs/codex-run-...summary.json",
  "ts": "2026-02-13T20:30:00Z"
}
```

## Validation Performed

- `tests/test_runner_and_parser.sh` passed
- Repro 1: non-zero run exits wrapper before smart classification/review
- Repro 2: quoted task breaks metadata heredoc Python block

## Next Implementation Slice

1. Fix critical bugs (A, B, C)
2. Add notify plumbing (`--notify-cmd`, event emission, hook adapter)
3. Update skill docs to match behavior
4. Add tests for failure-path classification, quote-safe metadata, and event emission
