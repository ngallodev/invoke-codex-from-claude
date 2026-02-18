#!/usr/bin/env python3
"""
Convert verbose Codex run summaries to the lean schema championed by the
json-minimizer track (short keys like id/exit/time/error/msg).

Input:  JSON emitted by scripts/parse_codex_run.py (stdin or --input).
Output: Minified JSON on stdout (or --output).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Mapping


def load_json(path: Path | None) -> Mapping[str, Any]:
    if path is None:
        try:
            return json.load(sys.stdin)
        except Exception:
            return {}
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def coerce_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


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


def minify(summary: Mapping[str, Any]) -> dict[str, Any]:
    legacy = _legacy(summary)
    tok = summary.get("tok") if isinstance(summary.get("tok"), Mapping) else {}
    token_usage = legacy.get("token_usage") if isinstance(legacy.get("token_usage"), Mapping) else {}
    cost_short = summary.get("cost") if isinstance(summary.get("cost"), Mapping) else {}
    cost_legacy = legacy.get("cost") if isinstance(legacy.get("cost"), Mapping) else {}

    exit_code = coerce_int(_pick(summary, "exit", "exit_code"))

    tokens_out = {
        "in": coerce_int(tok.get("in")) if tok else coerce_int(token_usage.get("input_tokens")),
        "out": coerce_int(tok.get("out")) if tok else coerce_int(token_usage.get("output_tokens")),
        "total": coerce_int(tok.get("tot")) if tok else coerce_int(token_usage.get("total_tokens")),
    }

    ok = summary.get("ok")
    if ok is None:
        ok = legacy.get("success")
    if ok is None and exit_code is not None:
        ok = exit_code == 0

    # Keep message terse; include exit_code to aid quick triage.
    if ok is True:
        msg = "completed"
    elif ok is False:
        msg = f"failed (exit {exit_code})" if exit_code is not None else "failed"
    else:
        msg = None

    return {
        "id": _pick(summary, "id", "run_id"),
        "sess": _pick(summary, "sid", "session_id"),
        "repo": _pick(summary, "repo", "repo"),
        "task": _pick(summary, "task", "task"),
        "resume": _pick(summary, "resume", "resume_session"),
        "start": _pick(summary, "start", "started_at"),
        "end": _pick(summary, "end", "ended_at"),
        "time": coerce_int(_pick(summary, "time", "elapsed_seconds")),
        "exit": exit_code,
        "ok": ok,
        "msg": msg,
        "log": _pick(summary, "log", "log_file"),
        "meta": _pick(summary, "meta", "meta_file"),
        "tokens": tokens_out,
        "cost": cost_short.get("usd") if cost_short else cost_legacy.get("usd"),
        # Carry over the original file location for traceability.
        "source": _pick(summary, "meta", "meta_file") or _pick(summary, "log", "log_file"),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Minify Codex summary JSON to the short-key schema (id/exit/time/msg)."
    )
    parser.add_argument(
        "--input",
        "-i",
        type=Path,
        help="Path to verbose summary JSON (defaults to stdin).",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="Path to write minified JSON (defaults to stdout).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    summary = load_json(args.input)
    minimized = minify(summary)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(minimized, ensure_ascii=True, indent=2), encoding="utf-8")
    else:
        json.dump(minimized, sys.stdout, ensure_ascii=True, indent=2)
        sys.stdout.write("\n")


if __name__ == "__main__":
    main()
