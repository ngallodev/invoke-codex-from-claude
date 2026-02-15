# invoke-codex-from-claude

Minimal wrapper that runs `codex` or `gemini` (and other LLMs) in a forked shell and emits structured summaries for Claude hooks.

All scripts and skill source files live under `codex-job/` at the repo root.

## Quick run (Codex)
```bash
codex-job/scripts/run_codex_task.sh --repo . --task "Fix feature X"
```

## Quick run (Gemini)
```bash
codex-job/scripts/run_gemini_task.sh --repo . --task "Fix feature X"
```

## Deploy Skill to `~/.claude/skills/`
```bash
rm -rf ~/.claude/skills/codex-job
cp -R codex-job ~/.claude/skills/codex-job
```

Scripts are installed to `~/.claude/skills/codex-job/scripts/`. The skill includes templates, tools, and reference documentation.

## Logging
Log verbosity defaults to `low`. To increase it:
```bash
codex-job/scripts/run_codex_task.sh ... -v
codex-job/scripts/run_codex_task.sh ... -vv
codex-job/scripts/run_codex_task.sh ... -vvv
```

Pass extra arguments after a `--`:
```bash
codex-job/scripts/run_gemini_task.sh ... -- --model gemini-2.0-flash
```

## Tests
```bash
tests/test_runner_and_parser.sh
tests/test_gemini_runner_and_parser.sh
```

## Output
Each run prints `codex_run_id`, `codex_exit_code`, `elapsed_seconds`, `log_file`, `meta_file`, `summary_file`, plus `summary_json={…}` for easy parsing. Log verbosity defaults to `low` and can be raised with `-v`, `-vv`, or `-vvv`.

## Event Notifications
`run_codex_task.sh` can emit status events:
- `--notify-cmd "<shell command>"` sends each event JSON object to the command on stdin
- `--event-stream <path>` appends JSONL events for local tracking

Helper script:
```bash
echo '{"event":"ping"}' | codex-job/scripts/notify_claude_hook.sh --url https://<callback-endpoint>
```
