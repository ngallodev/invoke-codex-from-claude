#!/usr/bin/env python3
"""Append a normalized delegation metrics record from a codex run summary."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", required=True, help="Path to codex run summary JSON")
    parser.add_argument("--out", default="delegation-metrics.jsonl", help="JSONL output path")
    parser.add_argument("--task-type", required=True)
    parser.add_argument("--risk", required=True, choices=["low", "medium", "high"])
    parser.add_argument("--delegated", default="true", choices=["true", "false"])
    parser.add_argument("--reason-if-not-delegated", default="")
    parser.add_argument("--claude-model", required=True)
    parser.add_argument("--claude-tokens-input", type=int, default=0)
    parser.add_argument("--claude-tokens-output", type=int, default=0)
    parser.add_argument("--total-cost-usd", type=float)
    parser.add_argument("--status", choices=["success", "partial", "failure"])
    parser.add_argument("--failure-class", choices=["environment", "spec", "execution"], default=None)
    parser.add_argument("--retry-count", type=int, default=0)
    parser.add_argument("--delegated-model", required=True, help="The model used by the delegate (Codex/Gemini)")
    parser.add_argument("--provider", choices=["codex", "gemini"], default="codex", help="LLM provider for token recording")
    return parser.parse_args()


def _as_number(value: object, default: float = 0.0) -> float:
    if value is None:
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _as_int(value: object, default: int = 0) -> int:
    if value is None:
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def main() -> int:
    args = parse_args()
    summary_path = Path(args.summary)
    out_path = Path(args.out)

    summary = json.loads(summary_path.read_text(encoding="utf-8"))

    success = bool(summary.get("success", False))
    status = args.status or ("success" if success else "failure")

    usage = summary.get("token_usage", {})
    t_in = _as_int(usage.get("input_tokens"), 0)
    t_out = _as_int(usage.get("output_tokens"), 0)
    t_total = _as_int(usage.get("total_tokens"), 0)

    elapsed_seconds = _as_number(summary.get("elapsed_seconds"), 0.0)

    cost_from_summary = summary.get("cost", {}).get("usd")
    total_cost_usd = _as_number(args.total_cost_usd if args.total_cost_usd is not None else cost_from_summary, 0.0)

    timestamp = summary.get("ended_at") or datetime.now(timezone.utc).isoformat()

    record = {
        "timestamp": timestamp,
        "repo": summary.get("repo", ""),
        "task_type": args.task_type,
        "risk": args.risk,
        "delegated": args.delegated == "true",
        "reason_if_not_delegated": args.reason_if_not_delegated,
        "provider": args.provider,
        "claude_model": args.claude_model,
        "delegated_model": args.delegated_model,
        "claude_tokens_input": args.claude_tokens_input,
        "claude_tokens_output": args.claude_tokens_output,
        "codex_tokens_input": t_in if args.provider == "codex" else 0,
        "codex_tokens_output": t_out if args.provider == "codex" else 0,
        "codex_tokens_total": t_total if args.provider == "codex" else 0,
        "gemini_tokens_input": t_in if args.provider == "gemini" else 0,
        "gemini_tokens_output": t_out if args.provider == "gemini" else 0,
        "gemini_tokens_total": t_total if args.provider == "gemini" else 0,
        "total_cost_usd": total_cost_usd,
        "duration_sec": elapsed_seconds,
        "status": status,
        "failure_class": args.failure_class if status != "success" else None,
        "retry_count": args.retry_count,
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, separators=(",", ":")) + "\n")

    print(json.dumps({"ok": True, "out": str(out_path), "status": status, "tokens": t_total, "provider": args.provider}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
