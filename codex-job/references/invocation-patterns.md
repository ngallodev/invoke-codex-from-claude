# Invocation Patterns

## Standard Launch

```bash
codex-job/scripts/invoke_codex_with_review.sh \
  --repo <repo_path> \
  --task '<task_description_with_acceptance_criteria>' \
  --notify-cmd 'codex-job/scripts/notify_claude_hook.sh --url https://<callback> --secret "$WEBHOOK_SECRET"' \
  -- --model gpt-5.1-codex-max
```

Webhook payloads are HMAC-SHA256 signed when `--secret`, `WEBHOOK_SECRET`, or `CODEX_WEBHOOK_SECRET` is present; the script sends `X-Signature: sha256=<hex>`.

## Resume Existing Session

```bash
codex-job/scripts/run_codex_task.sh \
  --repo <repo_path> \
  --resume <session_id> \
  --task 'Follow-up fixes' \
  -- --model gpt-5.1-codex-max
```

## Status Check

```bash
jq '{sid, exit, ok, tok}' runs/codex-run-<run_id>.summary.json
```

## Append Delegation Metrics

Claude invokes this after reading the run summary — not the wrapper script. One call per delegated run.

Run from repo root (paths are relative to CWD; `delegation-metrics.jsonl` must resolve to the repo root for `.gitignore` to match).

**From source tree:**
```bash
codex-job/scripts/write_delegation_metric.py \
  --summary runs/codex-run-<run_id>.summary.json \
  --out delegation-metrics.jsonl \
  --task-type feature \
  --risk medium \
  --claude-model sonnet \
  --delegated-model gpt-5.1-codex-max \
  --provider codex
```

**After deploy (`~/.claude/skills/codex-job/`):**
```bash
~/.claude/skills/codex-job/scripts/write_delegation_metric.py \
  --summary runs/codex-run-<run_id>.summary.json \
  --out delegation-metrics.jsonl \
  --task-type feature \
  --risk medium \
  --claude-model sonnet \
  --delegated-model gpt-5.1-codex-max \
  --provider codex
```

Pass `--status partial` when Codex partially completed the task (manual judgment based on logs/summary).

## Optional Verification

```bash
codex-job/scripts/verify_codex_work.sh --meta runs/codex-run-<run_id>.meta.json --syntax-check --run-tests
```
