# Contributing to invoke-codex-from-claude
This project uses specialized agents and shared scripts that multiple teams touch. Keep changes small, well-tested, and documented so Codex/Gemini runners stay reliable.

## Workflow Expectations
- Coordinate changes to `codex-job/scripts/run_codex_task.sh`, `codex-job/scripts/run_gemini_task.sh`, and install scripts; these are shared by several tracks (security, caching, tiering, docs).
- Treat `codex-job/scripts/` as canonical runtime code. Root `scripts/` must stay as thin wrappers and should not re-implement logic.
- Keep commits descriptive; include what changed and why.
- Update docs when you add flags, environment variables, or alter the summary JSON schema.
- Follow the go-live plan in `agent-notes/go-live-rec-detailed-plan.md` for dependency ordering (e.g., error handling before caching/tiering).

## Coding Standards
- Bash: use `set -euo pipefail`, prefer functions, avoid destructive git commands, and keep error messages non-sensitive. Run `shellcheck` when altering shell scripts if available.
- Python: keep scripts runnable with `python3`, prefer standard library, and add minimal comments for non-obvious logic.
- JSON schema (per `json-minimizer`): avoid verbose keys; document any schema change in README and tests.

## Testing
Run these from the repo root before opening a PR:
- `tests/test_agents_metadata.sh` (ensures agent instruction files and telemetry keys are intact)
- `tests/test_runner_and_parser.sh` (Codex runner + parser)
- `tests/test_gemini_runner_and_parser.sh` (Gemini runner + parser)
- `tests/test_invoke_and_notify.sh` (invoke + review + notification flow)

If you touch install/uninstall or notification flows, add/extend bats or shell tests to cover new flags (e.g., `--dry-run`, webhook signing). Use the existing fake Codex/Gemini shims in `tests/` to avoid external calls.

## Documentation Requirements
- README must reflect new prerequisites, flags, environment variables, dry-run behavior, and troubleshooting tips.
- Note schema updates from `json-minimizer` and any install changes from `installation-engineer` work.
- Include usage examples for new options (resume, tier, caching, doctor, webhook signing) when they land.

## Pull Request Checklist
- [ ] Tests above pass (attach output or summary).
- [ ] README/CONTRIBUTING updated for any user-facing change.
- [ ] Telemetry keys (`input_tokens`, `output_tokens`, `cached_tokens`, `context_tokens`, `elapsed_seconds`) remain documented in agent files when touched.
- [ ] No hardcoded secrets; required env vars are validated or documented.
- [ ] For shared scripts, note coordination points (who else is editing, related branches).

## Installing Locally for Development
- Install the skill with `./install.sh --scope project` (safe to re-run).
- Preview changes with `./install.sh --scope project --dry-run`.
- Uninstall with `./uninstall.sh --scope project` (or `--dry-run` to preview).

## Support & Questions
- Add concise notes to `agent-history.log` for cross-agent coordination instead of posting progress in stdout.
- For schema or cost-reduction questions, sync with the `json-minimizer` track; for install behaviors, sync with the `installation-engineer` track.
