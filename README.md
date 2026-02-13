# invoke-codex-from-claude

Minimal wrapper that runs `codex exec --cd <repo> <task>` in a forked shell and emits structured summaries for Claude hooks.

## Quick run
```bash
git clone <your-repo-url>
cd invoke-codex-from-claude
scripts/run_codex_task.sh \
  --repo /path/to/your/repo \
  --task "Implement feature X and run tests"
```

With push notifications (no polling):
```bash
scripts/run_codex_task.sh \
  --repo /path/to/your/repo \
  --task "Implement feature X and run tests" \
  --notify-cmd "scripts/notify_claude_hook.sh --url https://<callback-endpoint>"
```

Terminal Claude local notification:
```bash
scripts/run_codex_task.sh \
  --repo /path/to/your/repo \
  --task "Implement feature X and run tests" \
  --notify-cmd "scripts/notify_terminal.sh"
```

## Install (Claude Skill)
Install the skill into a project or user scope:
```bash
./install.sh --scope project
./install.sh --scope user
```

Uninstall:
```bash
./install.sh --scope project --uninstall
./install.sh --scope user --uninstall
```

## Logging
Log verbosity defaults to `low`. To increase it:
```bash
scripts/run_codex_task.sh --repo /path/to/your/repo --task "..." -v
scripts/run_codex_task.sh --repo /path/to/your/repo --task "..." -vv
scripts/run_codex_task.sh --repo /path/to/your/repo --task "..." -vvv
```

Pass extra Codex arguments after a `--`:
```bash
scripts/run_codex_task.sh ... -- --model gpt-5-codex
```

## Tests
```bash
tests/test_runner_and_parser.sh
```

## Output
Each run prints `codex_run_id`, `codex_exit_code`, `elapsed_seconds`, `log_file`, `meta_file`, `summary_file`, plus `summary_json={…}` for easy parsing. Log verbosity defaults to `low` and can be raised with `-v`, `-vv`, or `-vvv`.

## Event Notifications
`run_codex_task.sh` can emit status events:
- `--notify-cmd "<shell command>"` sends each event JSON object to the command on stdin
- `--event-stream <path>` appends JSONL events for local tracking

Helper script:
```bash
echo '{"event":"ping"}' | scripts/notify_claude_hook.sh --url https://<callback-endpoint>
```
