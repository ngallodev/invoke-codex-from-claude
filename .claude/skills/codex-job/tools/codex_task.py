#!/usr/bin/env python3
"""
Codex Task Invocation Tool

Fire-and-forget Codex invocation with smart failure detection.
"""

import json
import os
import subprocess
from pathlib import Path


def _auto_write_delegation_metric(
    *,
    summary_file: str,
    repo_root: Path,
    codex_model: str,
    success: bool,
) -> str | None:
    """Append delegation metrics automatically when summary output exists."""
    summary_path = Path(summary_file)
    if not summary_path.exists():
        return "summary_missing"

    writer = repo_root / ".claude/skills/codex-job/tools/write_delegation_metric.py"
    if not writer.exists():
        return "writer_missing"

    metrics_out = os.environ.get(
        "DELEGATION_METRICS_OUT",
        str(repo_root / "delegation-metrics.jsonl"),
    )

    task_type = os.environ.get("CODEX_TASK_TYPE", "implementation")
    risk = os.environ.get("CODEX_RISK_LEVEL", "medium")
    claude_model = os.environ.get("CLAUDE_MODEL", "sonnet")
    status = "success" if success else os.environ.get("CODEX_FAILURE_STATUS", "failure")
    retry_count = os.environ.get("CODEX_RETRY_COUNT", "0")

    cmd = [
        "python3",
        str(writer),
        "--summary",
        str(summary_path),
        "--out",
        metrics_out,
        "--task-type",
        task_type,
        "--risk",
        risk,
        "--claude-model",
        claude_model,
        "--codex-model",
        codex_model,
        "--status",
        status,
        "--retry-count",
        retry_count,
    ]

    failure_class = os.environ.get("CODEX_FAILURE_CLASS", "")
    if not success and failure_class in {"environment", "spec", "execution"}:
        cmd.extend(["--failure-class", failure_class])

    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=30,
        cwd=repo_root,
    )
    if result.returncode != 0:
        return f"writer_exit_{result.returncode}"

    return None


def codex_task(
    repo: str,
    task: str,
    model: str = "gpt-5.1-codex-max",
    resume_session: str = "",
    timeout_seconds: int = 1800,
) -> dict:
    """
    Invoke Codex with fire-and-forget execution and smart failure detection.

    Args:
        repo: Path to target repository
        task: Task description for Codex
        model: Codex model to use (mini, max, or 5.2)
        resume_session: Optional session ID to resume
        timeout_seconds: Maximum wait time in seconds for the subprocess

    Returns:
        dict with run_id, log_file, meta_file, session_id (when available)
    """
    # Resolve paths
    # From: .claude/skills/codex-job/tools/codex_task.py
    # To: scripts/invoke_codex_with_review.sh
    tool_file = Path(__file__).resolve()
    repo_root = tool_file.parent.parent.parent.parent.parent  # tools -> codex -> skills -> .claude -> repo root
    script_dir = repo_root / "scripts"
    wrapper = script_dir / "invoke_codex_with_review.sh"

    if not wrapper.exists():
        return {
            "error": f"Wrapper script not found: {wrapper}",
            "success": False,
        }

    # Build command
    cmd = [
        str(wrapper),
        "--repo", repo,
    ]
    if resume_session:
        cmd.extend(["--resume", resume_session])
    cmd.extend([
        "--task", task,
        "--",
        "--model", model,
    ])

    try:
        # Execute wrapper and parse structured output.
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            cwd=script_dir.parent,
        )

        # Parse output
        output_lines = result.stdout.split("\n")
        response = {"raw_output": result.stdout}

        for line in output_lines:
            if "=" in line:
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip()

                if key in ["codex_run_id", "codex_session_id", "log_file", "meta_file", "summary_file", "codex_exit_code"]:
                    response[key] = value

        # Parse summary JSON if available
        if "summary_json=" in result.stdout:
            try:
                summary_start = result.stdout.index("summary_json=") + len("summary_json=")
                summary_json = result.stdout[summary_start:].strip()
                response["summary"] = json.loads(summary_json)
            except (ValueError, json.JSONDecodeError):
                pass

        response["success"] = result.returncode == 0
        response["exit_code"] = result.returncode

        summary_file = response.get("summary_file")
        if isinstance(summary_file, str) and summary_file:
            metric_error = _auto_write_delegation_metric(
                summary_file=summary_file,
                repo_root=repo_root,
                codex_model=model,
                success=response["success"],
            )
            if metric_error:
                response["metric_warning"] = metric_error

        return response

    except subprocess.TimeoutExpired:
        timeout_minutes = timeout_seconds / 60
        return {
            "error": (
                "Codex task timed out after "
                f"{timeout_minutes:.1f} minutes ({timeout_seconds} seconds)"
            ),
            "success": False,
        }
    except Exception as e:
        return {
            "error": f"Failed to invoke Codex: {str(e)}",
            "success": False,
        }


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 3:
        print("Usage: codex_task.py <repo> <task> [model] [resume_session] [timeout_seconds]")
        sys.exit(1)

    repo = sys.argv[1]
    task = sys.argv[2]
    model = sys.argv[3] if len(sys.argv) > 3 else "gpt-5.1-codex-max"
    resume_session = sys.argv[4] if len(sys.argv) > 4 else ""
    timeout_seconds = 1800
    if len(sys.argv) > 5:
        try:
            timeout_seconds = int(sys.argv[5])
        except ValueError:
            print("timeout_seconds must be an integer")
            sys.exit(1)

    result = codex_task(repo, task, model, resume_session, timeout_seconds)
    print(json.dumps(result, indent=2))
