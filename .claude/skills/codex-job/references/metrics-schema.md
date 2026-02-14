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
- `failure_class` (`environment` | `spec` | `execution`)
- `retry_count`

Rolling policy:
- Evaluate every 10 delegated jobs per `task_type`.
- Success threshold: 70% minimum, excluding environmental failures.
- If below threshold: increase spec detail, reduce delegation scope, re-measure on next window.
