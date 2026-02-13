#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path
from typing import Any


def parse_int(text: str) -> int | None:
    cleaned = re.sub(r"[^0-9]", "", text)
    return int(cleaned) if cleaned else None


def first_float(text: str) -> float | None:
    m = re.search(r"([0-9]+(?:\.[0-9]+)?)", text)
    return float(m.group(1)) if m else None


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
    lines = log_text.splitlines()
    for line in reversed(lines):
        if re.search(r"cost|price|usd|\$", line, flags=re.IGNORECASE):
            usd = first_float(line.replace(",", ""))
            if usd is not None:
                return {"usd": usd, "evidence": line.strip()}
    return {"usd": None, "evidence": None}


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

    output = {
        "run_id": meta.get("run_id"),
        "session_id": meta.get("session_id"),
        "resume_session": meta.get("resume_session"),
        "repo": meta.get("repo"),
        "task": meta.get("task"),
        "started_at": meta.get("started_at"),
        "ended_at": meta.get("ended_at"),
        "elapsed_seconds": meta.get("elapsed_seconds"),
        "exit_code": meta.get("exit_code"),
        "success": meta.get("exit_code") == 0 if isinstance(meta.get("exit_code"), int) else None,
        "log_file": str(log_path),
        "meta_file": args.meta,
        "token_usage": token_usage,
        "cost": cost,
    }

    print(json.dumps(output, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
