# Resume Prompt

Context:
- This repo was re-centered on MVP go-live scope (C1-C5) with `codex-job/scripts/` as canonical runtime.
- Root `scripts/` are thin wrappers for user/operator entrypoints.
- Deferred Phase 2/3 runtime features (queue/dashboard) are opt-in for install via `--include-experimental`.

First actions:
1. Read `agent-notes/session-handoff-2026-02-18.md`.
2. Read `agent-notes/mvp-architecture-reassessment.md`.
3. Confirm whether deferred Phase 2/3 files should remain in-tree (opt-in) or be archived/removed.

Validation baseline:
- `bash tests/test_runner_and_parser.sh`
- `bash tests/test_invoke_and_notify.sh`
- `bash tests/test_install_dry_run.sh`
- `bash tests/test_agents_metadata.sh`
- `bats --tap --print-output-on-failure tests/test_run_codex_task.bats`

Notes:
- `README-TLDR.md` is the short user path for install/setup/run.
- Canonical runner is `codex-job/scripts/run_codex_task.sh`.
