#!/usr/bin/env python3
import argparse
import json
import os
import re
from pathlib import Path
from typing import Any, Mapping


def parse_int(text: str) -> int | None:
    cleaned = re.sub(r"[^0-9]", "", text)
    return int(cleaned) if cleaned else None


def parse_float(text: str) -> float | None:
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def extract_token_usage(log_text: str) -> dict[str, Any]:
    patterns = {
        "input_tokens": [
            r"input[_\s-]?tokens?\s*[:=]\s*([0-9][0-9,]*)",
            r"prompt[_\s-]?tokens?\s*[:=]\s*([0-9][0-9,]*)",
        ],
        "output_tokens": [
            r"output[_\s-]?tokens?\s*[:=]\s*([0-9][0-9,]*)",
            r"completion[_\s-]?tokens?\s*[:=]\s*([0-9][0-9,]*)",
        ],
        "total_tokens": [
            r"total[_\s-]?tokens?\s*[:=]\s*([0-9][0-9,]*)",
            r"tokens?\s+used\s*(?:[:=]\s*)?([0-9][0-9,]*)",
        ],
    }

    result: dict[str, Any] = {
        "input_tokens": None,
        "output_tokens": None,
        "total_tokens": None,
        "evidence": {},
    }

    for key, key_patterns in patterns.items():
        for pat in key_patterns:
            matches = re.findall(pat, log_text, flags=re.IGNORECASE)
            if matches:
                raw = matches[-1]
                result[key] = parse_int(raw)
                result["evidence"][key] = {"pattern": pat, "raw": raw}
                break

    if result["total_tokens"] is None and result["input_tokens"] is not None and result["output_tokens"] is not None:
        result["total_tokens"] = result["input_tokens"] + result["output_tokens"]
        result["evidence"]["total_tokens"] = {"derived": "input_tokens + output_tokens"}

    return result


def extract_cost(log_text: str) -> dict[str, Any]:
    # Only accept lines that look like explicit cost fields, not arbitrary prose containing "$".
    cost_patterns = [
        r"\bcost(?:_usd)?\s*[:=]\s*\$?\s*([0-9]+(?:\.[0-9]+)?)",
        r"\bestimated_cost(?:_usd)?\s*[:=]\s*\$?\s*([0-9]+(?:\.[0-9]+)?)",
        r"\busd\s*[:=]\s*\$?\s*([0-9]+(?:\.[0-9]+)?)",
        r"\btotal\s+cost\b\s*[:=]\s*\$?\s*([0-9]+(?:\.[0-9]+)?)",
    ]

    for line in reversed(log_text.splitlines()):
        stripped = line.strip()
        for pat in cost_patterns:
            match = re.search(pat, stripped, flags=re.IGNORECASE)
            if match:
                usd = parse_float(match.group(1))
                if usd is not None:
                    return {"usd": usd, "evidence": stripped}

    return {"usd": None, "evidence": None}


def coerce_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def compact_token_usage(raw: Mapping[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(raw, Mapping):
        return None

    def pick(*keys: str) -> Any:
        for key in keys:
            if key in raw and raw[key] is not None:
                return raw[key]
        return None

    evidence_in = raw.get("evidence") or raw.get("ev") or {}
    ev: dict[str, Any] = {}
    for new_key, old_key in [("in", "input_tokens"), ("out", "output_tokens"), ("tot", "total_tokens")]:
        src = evidence_in.get(new_key) or evidence_in.get(old_key)
        if isinstance(src, Mapping):
            ev_entry = {}
            if src.get("pattern"):
                ev_entry["pat"] = src["pattern"]
            if src.get("raw"):
                ev_entry["raw"] = src["raw"]
            if src.get("derived"):
                ev_entry["derived"] = src["derived"]
            if ev_entry:
                ev[new_key] = ev_entry

    tok = {
        "in": coerce_int(pick("in", "input_tokens")),
        "out": coerce_int(pick("out", "output_tokens")),
        "tot": coerce_int(pick("tot", "total_tokens")),
    }
    if ev:
        tok["ev"] = ev

    if all(value is None for value in tok.values() if not isinstance(value, dict)) and "ev" not in tok:
        return None
    return tok


def compact_cost(raw: Mapping[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(raw, Mapping):
        return None

    usd = raw.get("usd")
    if isinstance(usd, str):
        try:
            usd = float(usd)
        except ValueError:
            usd = None
    elif not isinstance(usd, (int, float)):
        usd = None

    ev = raw.get("ev") or raw.get("evidence")
    if ev is not None and not isinstance(ev, (str, int, float)):
        ev = str(ev)

    if usd is None and ev is None:
        return None
    return {"usd": usd, "ev": ev}


def build_legacy(
    meta: Mapping[str, Any],
    log_path: Path,
    token_usage: Mapping[str, Any],
    cost: Mapping[str, Any],
    success: bool | None,
) -> dict[str, Any]:
    return {
        "run_id": meta.get("run_id"),
        "session_id": meta.get("session_id"),
        "resume_session": meta.get("resume_session"),
        "repo": meta.get("repo"),
        "task": meta.get("task"),
        "model": meta.get("model"),
        "model_tier": meta.get("model_tier"),
        "model_source": meta.get("model_source"),
        "started_at": meta.get("started_at"),
        "ended_at": meta.get("ended_at"),
        "elapsed_seconds": meta.get("elapsed_seconds"),
        "exit_code": meta.get("exit_code"),
        "success": success,
        "log_file": str(log_path),
        "meta_file": meta.get("meta_file"),
        "token_usage": token_usage,
        "cost": cost,
    }


def compact_summary(*, meta: Mapping[str, Any], log_path: Path, token_usage: Mapping[str, Any], cost: Mapping[str, Any]) -> dict[str, Any]:
    short_tok = compact_token_usage(token_usage)
    short_cost = compact_cost(cost)

    exit_code = coerce_int(meta.get("exit_code"))
    ok = meta.get("success")
    if ok is None and exit_code is not None:
        ok = exit_code == 0

    summary = {
        "id": meta.get("run_id"),
        "sid": meta.get("session_id"),
        "repo": meta.get("repo"),
        "task": meta.get("task"),
        "resume": meta.get("resume_session"),
        "start": meta.get("started_at"),
        "end": meta.get("ended_at"),
        "time": coerce_int(meta.get("elapsed_seconds")),
        "exit": exit_code,
        "ok": ok,
        "mdl": meta.get("model"),
        "tier": meta.get("model_tier"),
        "msrc": meta.get("model_source"),
        "log": str(log_path),
        "meta": meta.get("meta_file"),
        "tok": short_tok,
        "cost": short_cost,
        "err": None,
        "cache": {
            "status": meta.get("cache_status"),
            "key": meta.get("cache_key"),
        },
        "src": "run_codex_task.sh",
    }

    # Always provide verbose payload for compatibility, nested to avoid top-level bloat.
    summary["legacy"] = build_legacy(meta, log_path, token_usage, cost, ok)

    if os.environ.get("SUMMARY_JSON_LEGACY", "0") == "1":
        summary["legacy_inline"] = build_legacy(meta, log_path, token_usage, cost, ok)

    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Parse Codex run output into normalized JSON summary.")
    parser.add_argument("--log", required=True, help="Path to raw codex log file")
    parser.add_argument("--meta", help="Path to meta JSON emitted by run_codex_task.sh")
    args = parser.parse_args()

    log_path = Path(args.log)
    meta = load_json(Path(args.meta)) if args.meta else {}

    log_text = ""
    if log_path.exists():
        log_text = log_path.read_text(encoding="utf-8", errors="replace")

    token_usage = extract_token_usage(log_text)
    cost = extract_cost(log_text)
    meta["meta_file"] = args.meta

    compact = compact_summary(meta=meta, log_path=log_path, token_usage=token_usage, cost=cost)
    print(json.dumps(compact, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
