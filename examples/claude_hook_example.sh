#!/usr/bin/env bash
set -euo pipefail

# Example: Claude passes TASK and REPO into this script.
TASK="${1:-Implement requested coding task}"
REPO="${2:-.}"

# Resolve project root from this file location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$BASE_DIR/scripts/run_codex_task.sh"
LOG_DIR="$BASE_DIR/runs"

mkdir -p "$LOG_DIR"

OUTPUT="$($RUNNER --repo "$REPO" --task "$TASK" --log-dir "$LOG_DIR")"

# Extract summary file path from runner output.
SUMMARY_FILE="$(printf '%s\n' "$OUTPUT" | awk -F= '/^summary_file=/{print $2}' | tail -n1)"

# Print concise report back to Claude.
printf '%s\n' "$OUTPUT"
if [[ -n "$SUMMARY_FILE" && -f "$SUMMARY_FILE" ]]; then
  echo "parsed_summary_path=$SUMMARY_FILE"
  echo "parsed_summary=$(cat "$SUMMARY_FILE")"
fi
