# MVP Architecture Reassessment

Date: 2026-02-18
Scope: Re-center on pre-drift MVP go-live intent (C1-C5 only), remove drift, and define clean boundaries.

## 1) Proposed Architecture Contract

### Canonical runtime (source of truth)
- Location: `codex-job/scripts/`
- Owns all task execution behavior:
  - `run_codex_task.sh`, `invoke_codex_with_review.sh`
  - `notify_claude_hook.sh`, `notify_terminal.sh`
  - `parse_codex_run.py`
  - verification scripts tied to Codex run outputs
- Must be runnable both:
  - from source tree (`codex-job/scripts/...`)
  - after install (`~/.claude/skills/codex-job/scripts/...`)
- Must not reference root `scripts/`.

### Root shell/Python entrypoint layer
- Location: `scripts/`
- Purpose: human/operator entrypoints only.
- Rules:
  - thin executable wrappers only
  - delegates to `codex-job/scripts/*`
  - no duplicated business logic
  - no separate parser/schema logic

### Root-only tooling (non-skill)
- Keep only utilities that are explicitly non-skill/operator-oriented.
- Candidate: `scripts/summary_minifier.py` (if retained, it must consume canonical summary schema).

### Install/uninstall
- `install.sh` and `uninstall.sh` own deployment mechanics only.
- Install should source runtime scripts from `codex-job/scripts/` (canonical), not from root `scripts/`.
- Uninstall must remove the same deployed runtime surface.

## 2) Current Violations / Risk Hotspots

1. Core runner has out-of-scope complexity wired into MVP path.
   - `codex-job/scripts/run_codex_task.sh` includes queue/cache/doctor/tier logic.
   - Queue integration currently emits `job_queue.py` argument errors during normal runs.

2. Parser/schema drift between layers.
   - Canonical parser emits lean schema with `legacy`.
   - Root tooling still contains older verbose assumptions in places.

3. Skill docs/path references are mixed.
   - `codex-job/SKILL.md` references `scripts/...` rather than canonical `codex-job/scripts/...` semantics.

4. Test intent is split.
   - Some tests target canonical scripts, others root scripts; this is valid only if root scripts remain wrappers.

## 3) Pre-Drift MVP Checklist (C1-C5)

Status legend: `done` / `partial` / `not started`

| ID | Status | Notes |
|---|---|---|
| C1 Secrets management | done | Canonical runner now enforces `CODEX_API_KEY` and requires signing secret envs when `--notify-cmd` is set. |
| C2 Error handling + timeouts + guaranteed summary | done | Canonical runner now has signal traps, timeout enforcement, and guaranteed `summary_json` emission on all exit paths. |
| C3 Test expansion | partial | Expanded tests exist and current shell suites pass; bats-specific coverage exists but could not be executed in this environment (bats missing). |
| C4 Install/uninstall robustness | done | `install.sh`/`uninstall.sh` support `--dry-run`, and install sources canonical runtime scripts from `codex-job/scripts/`. |
| C5 Documentation overhaul | done | README alignment completed and short user quickstart added in `README-TLDR.md`. |

## 4) Keep / Drop / Rewrite Plan

### Keep now (MVP-aligned)
- Canonical:
  - `codex-job/scripts/run_codex_task.sh` (after simplification)
  - `codex-job/scripts/invoke_codex_with_review.sh`
  - `codex-job/scripts/notify_claude_hook.sh` (HMAC signing)
  - `codex-job/scripts/parse_codex_run.py` (lean + `legacy`)
- Root wrappers:
  - `scripts/run_codex_task.sh`
  - `scripts/invoke_codex_with_review.sh`
  - `scripts/notify_claude_hook.sh`
  - `scripts/notify_terminal.sh`
  - `scripts/parse_codex_run.py`
  - `scripts/verify_codex_work.sh`
- Installer surface:
  - `install.sh`, `uninstall.sh`

### Remove from MVP execution path (defer; keep files optional)
- Queue/dashboard integration from core `run_codex_task.sh`.
- Cache behavior from core `run_codex_task.sh`.
- Any Phase 2/3 behavior that changes run control flow for default MVP runs.

### Rewrite
- `codex-job/scripts/run_codex_task.sh`:
  - make Phase 1 concerns first-class and minimal
  - isolate/defer advanced behaviors behind explicit future feature flags or remove for now
- `codex-job/SKILL.md`:
  - align invocation language with canonical script layout
- tests:
  - canonical behavior tests on `codex-job/scripts/*`
  - wrapper smoke tests for root `scripts/*`

## 5) Execution Order (safe unwind)

1. Lock boundaries in docs (this file + README + SKILL docs).
2. Simplify canonical runner to Phase 1 only (C1/C2 focus).
3. Repoint/validate wrappers and install/uninstall symmetry (C4).
4. Normalize tests to canonical+wrapper split (C3).
5. Final README + TLDR user quickstart (C5).

## 6) Definition of "MVP Go-Live Ready"

- Core run path has:
  - explicit required env validation
  - signal-safe exit handling
  - timeout enforcement
  - guaranteed valid `summary_json` on all exit paths
- No duplicated runtime logic across root and canonical script trees.
- Install/uninstall are idempotent and dry-run safe.
- Tests for C1-C4 pass from clean checkout.
- Documentation accurately matches behavior and path conventions.
