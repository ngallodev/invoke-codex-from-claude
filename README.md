# invoke-codex-from-claude

Minimal wrapper to let Claude invoke Codex in a forked terminal/process and get a machine-readable run summary.

## Files
- `scripts/run_codex_task.sh`: runs Codex, captures log/timing/exit code, writes meta JSON, emits summary JSON.
- `scripts/parse_codex_run.py`: parses raw log + meta into normalized JSON (token usage, cost hints, elapsed, status).
- `examples/claude_hook_example.sh`: example caller script suitable for a Claude hook/integration.

## Quick start
```bash
cd /lump/apps/invoke-codex-from-claude
scripts/run_codex_task.sh \
  --repo /lump/apps/some-repo \
  --task "Implement feature X and run tests"
```

Optional extra Codex args:
```bash
scripts/run_codex_task.sh \
  --repo /lump/apps/some-repo \
  --task "Fix lint and tests" \
  -- --model gpt-5-codex
```

## Output contract
The wrapper prints key-value lines and a JSON payload:
- `codex_run_id`
- `codex_exit_code`
- `elapsed_seconds`
- `log_file`
- `meta_file`
- `summary_file`
- `summary_json={...}`

This is intentionally easy for Claude hooks to parse.

## Notes
- Token/cost extraction is best-effort and depends on what Codex prints in logs.
- The wrapper exits with Codex's exit code.
