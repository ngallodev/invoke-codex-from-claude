#!/usr/bin/env python3
"""
Codex Task Invocation Tool

Fire-and-forget Codex invocation with smart failure detection.
"""

import json
import subprocess
from pathlib import Path


def codex_task(
    repo: str,
    task: str,
    model: str = "gpt-5.1-codex-max",
    resume_session: str = "",
) -> dict:
    """
    Invoke Codex with fire-and-forget execution and smart failure detection.

    Args:
        repo: Path to target repository
        task: Task description for Codex
        model: Codex model to use (mini, max, or 5.2)
        resume_session: Optional session ID to resume

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
    runner = script_dir / "run_codex_task.sh"

    if not wrapper.exists():
        return {
            "error": f"Wrapper script not found: {wrapper}",
            "success": False,
        }

    # Build command
    if resume_session:
        cmd = [
            str(runner),
            "--repo", repo,
            "--resume", resume_session,
            "--task", task,
            "--",
            "--model", model,
        ]
    else:
        cmd = [
            str(wrapper),
            "--repo", repo,
            "--task", task,
            "--",
            "--model", model,
        ]

    try:
        # Execute wrapper and parse structured output.
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,  # 5 minutes max
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

        return response

    except subprocess.TimeoutExpired:
        return {
            "error": "Codex task timed out after 5 minutes",
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
        print("Usage: codex_task.py <repo> <task> [model] [resume_session]")
        sys.exit(1)

    repo = sys.argv[1]
    task = sys.argv[2]
    model = sys.argv[3] if len(sys.argv) > 3 else "gpt-5.1-codex-max"
    resume_session = sys.argv[4] if len(sys.argv) > 4 else ""

    result = codex_task(repo, task, model, resume_session)
    print(json.dumps(result, indent=2))
