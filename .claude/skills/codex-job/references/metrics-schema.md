# Delegation Metrics Schema

Write one JSON object per line to `delegation-metrics.jsonl`.

Preferred writer:
- `.claude/skills/codex-job/tools/write_delegation_metric.py`

Required fields:
- `timestamp`
- `repo`
- `task_type`
- `risk`
- `delegated` (boolean)
- `reason_if_not_delegated`
- `claude_model`
- `codex_model`
- `claude_tokens_input`
- `claude_tokens_output`
- `codex_tokens`
- `total_cost_usd`
- `duration_sec`
- `status` (`success` | `partial` | `failure`)
- `failure_class` (`environment` | `spec` | `execution`) — `null` when `status` is `success`
- `retry_count`

Notes:
- `codex_tokens` is the total token count from the summary (`token_usage.total_tokens`); input/output split is not available from Codex summaries today.
- `status: partial` is not auto-detected. Claude must pass `--status partial` manually based on logs/summary context when a run partially completed.
- `delegation-metrics.jsonl` is local-only (gitignored by design). It is not shared across machines.

Rolling policy:
- Evaluate on a rolling window of the last 10 delegated jobs per `task_type` (not cumulative multiples).
- Success threshold: 70% minimum, excluding environmental failures.
- If below threshold: increase spec detail, reduce delegation scope, re-measure on next window.
- No automated calculator exists; Claude applies this rule procedurally by reading the JSONL file.
