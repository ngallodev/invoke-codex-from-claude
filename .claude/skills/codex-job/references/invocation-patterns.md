# Invocation Patterns

## Standard Launch

```bash
scripts/invoke_codex_with_review.sh \
  --repo <repo_path> \
  --task '<task_description_with_acceptance_criteria>' \
  --notify-cmd 'scripts/notify_claude_hook.sh --url https://<callback>' \
  -- --model gpt-5.1-codex-max
```

## Resume Existing Session

```bash
scripts/run_codex_task.sh \
  --repo <repo_path> \
  --resume <session_id> \
  --task 'Follow-up fixes' \
  -- --model gpt-5.1-codex-max
```

## Status Check

```bash
jq '{session_id, exit_code, success, token_usage}' runs/codex-run-<run_id>.summary.json
```

## Append Delegation Metrics

```bash
.claude/skills/codex-job/tools/write_delegation_metric.py \
  --summary runs/codex-run-<run_id>.summary.json \
  --out delegation-metrics.jsonl \
  --task-type feature \
  --risk medium \
  --claude-model sonnet \
  --codex-model gpt-5.1-codex-max
```

## Optional Verification

```bash
scripts/verify_codex_work.sh --meta runs/codex-run-<run_id>.meta.json --syntax-check --run-tests
```
