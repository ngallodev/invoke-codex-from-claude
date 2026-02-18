#!/usr/bin/env python3
"""Emit a concise one-line summary from a Codex run summary JSON file."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Mapping


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Print a one-line summary for a Codex run summary JSON.")
    parser.add_argument("--summary", required=True, type=Path, help="Path to summary JSON file.")
    return parser.parse_args()


def load_summary(path: Path) -> Mapping[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"summary file not found: {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON in summary file: {path} ({exc.msg})") from exc
    if not isinstance(data, Mapping):
        raise ValueError(f"summary JSON must be an object: {path}")
    return data


def _legacy(summary: Mapping[str, Any]) -> Mapping[str, Any]:
    legacy = summary.get("legacy")
    return legacy if isinstance(legacy, Mapping) else {}


def _pick(summary: Mapping[str, Any], key: str, legacy_key: str | None = None) -> Any:
    value = summary.get(key)
    if value is not None:
        return value
    legacy = _legacy(summary)
    if legacy_key:
        return legacy.get(legacy_key)
    return None


def _to_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _to_float(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _to_ok(summary: Mapping[str, Any], exit_code: int | None) -> bool | None:
    ok = _pick(summary, "ok", "success")
    if isinstance(ok, bool):
        return ok
    if exit_code is not None:
        return exit_code == 0
    return None


def _sanitize_task(value: Any) -> str:
    if not isinstance(value, str):
        return "-"
    compact = re.sub(r"\s+", " ", value).strip()
    if not compact:
        return "-"
    if len(compact) > 64:
        return compact[:61] + "..."
    return compact


def _fmt_cost(cost: float | None) -> str:
    if cost is None:
        return "-"
    return f"{cost:.4f}".rstrip("0").rstrip(".")


def summarize(summary: Mapping[str, Any]) -> str:
    tok = summary.get("tok") if isinstance(summary.get("tok"), Mapping) else {}
    legacy_token = _legacy(summary).get("token_usage")
    legacy_token = legacy_token if isinstance(legacy_token, Mapping) else {}

    cost = summary.get("cost") if isinstance(summary.get("cost"), Mapping) else {}
    legacy_cost = _legacy(summary).get("cost")
    legacy_cost = legacy_cost if isinstance(legacy_cost, Mapping) else {}

    run_id = _pick(summary, "id", "run_id") or "-"
    session_id = _pick(summary, "sid", "session_id") or "-"
    task = _sanitize_task(_pick(summary, "task", "task"))
    exit_code = _to_int(_pick(summary, "exit", "exit_code"))
    elapsed = _to_int(_pick(summary, "time", "elapsed_seconds"))
    total_tokens = _to_int(tok.get("tot"))
    if total_tokens is None:
        total_tokens = _to_int(legacy_token.get("total_tokens"))
    usd = _to_float(cost.get("usd"))
    if usd is None:
        usd = _to_float(legacy_cost.get("usd"))

    ok = _to_ok(summary, exit_code)
    status = "OK" if ok is True else "FAIL" if ok is False else "UNKNOWN"

    exit_text = str(exit_code) if exit_code is not None else "-"
    elapsed_text = f"{elapsed}s" if elapsed is not None else "-"
    tok_text = str(total_tokens) if total_tokens is not None else "-"

    return (
        f"{status} id={run_id} exit={exit_text} time={elapsed_text} "
        f"tok={tok_text} cost={_fmt_cost(usd)} sid={session_id} task=\"{task}\""
    )


def main() -> int:
    args = parse_args()
    try:
        summary = load_summary(args.summary)
        print(summarize(summary))
        return 0
    except (FileNotFoundError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
