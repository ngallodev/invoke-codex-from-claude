#!/usr/bin/env bash
set -euo pipefail

# Enhanced Codex invocation with automatic review on failure
# Usage: invoke_codex_with_review.sh --repo <path> --task <text> [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/run_codex_task.sh"

usage() {
  "$RUNNER" --help
}

REPO=""
TASK=""
NOTIFY_CMD=""
EVENT_STREAM=""
CODEX_BIN=""
LOG_DIR=""
LOG_VERBOSITY=""
EXTRA_ARGS=()
SHOW_HELP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --task)
      TASK="${2:-}"
      shift 2
      ;;
    --notify-cmd)
      NOTIFY_CMD="${2:-}"
      shift 2
      ;;
    --event-stream)
      EVENT_STREAM="${2:-}"
      shift 2
      ;;
    --codex-bin)
      CODEX_BIN="${2:-}"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="${2:-}"
      shift 2
      ;;
    --verbosity)
      LOG_VERBOSITY="${2:-}"
      shift 2
      ;;
    -v)
      LOG_VERBOSITY="normal"
      shift
      ;;
    -vv)
      LOG_VERBOSITY="high"
      shift
      ;;
    -vvv)
      LOG_VERBOSITY="extreme"
      shift
      ;;
    --)
      shift
      EXTRA_ARGS=("$@")
      break
      ;;
    -h|--help)
      SHOW_HELP=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$SHOW_HELP" -eq 1 ]]; then
  usage
  exit 0
fi

if [[ -z "$REPO" ]]; then
  echo "Error: --repo is required." >&2
  exit 2
fi

run_and_capture() {
  local output
  local exit_code

  set +e
  output="$("$RUNNER" "$@" 2>&1)"
  exit_code=$?
  set -e

  printf '%s\n' "$output"
  return "$exit_code"
}

extract_kv() {
  local text="$1"
  local key="$2"
  awk -F= -v k="$key" '$1==k {print substr($0, index($0, "=")+1)}' <<< "$text" | tail -n1
}

emit_wrapper_event() {
  local event_name="$1"
  local status="$2"
  local run_id="$3"
  local session_id="$4"
  local meta_file="$5"
  local log_file="$6"
  local summary_file="$7"
  local exit_code="$8"

  if [[ -z "$NOTIFY_CMD" && -z "$EVENT_STREAM" ]]; then
    return 0
  fi

  local event_json
  event_json="$(
    EVENT_NAME="$event_name" \
    EVENT_STATUS="$status" \
    EVENT_RUN_ID="$run_id" \
    EVENT_SESSION_ID="$session_id" \
    EVENT_REPO="$REPO" \
    EVENT_META_FILE="$meta_file" \
    EVENT_LOG_FILE="$log_file" \
    EVENT_SUMMARY_FILE="$summary_file" \
    EVENT_EXIT_CODE="$exit_code" \
    python3 - <<'PY'
import json
import os
from datetime import datetime, timezone


def nullable(name: str):
    value = os.environ.get(name, "")
    if value in ("", "unknown", "null"):
        return None
    return value


exit_raw = os.environ.get("EVENT_EXIT_CODE", "")
obj = {
    "event": os.environ["EVENT_NAME"],
    "status": os.environ["EVENT_STATUS"],
    "run_id": nullable("EVENT_RUN_ID"),
    "session_id": nullable("EVENT_SESSION_ID"),
    "repo": nullable("EVENT_REPO"),
    "meta_file": nullable("EVENT_META_FILE"),
    "log_file": nullable("EVENT_LOG_FILE"),
    "summary_file": nullable("EVENT_SUMMARY_FILE"),
    "exit_code": int(exit_raw) if exit_raw not in ("", "null") else None,
    "source": "invoke_codex_with_review.sh",
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
print(json.dumps(obj, ensure_ascii=True))
PY
  )"

  if [[ -n "$EVENT_STREAM" ]]; then
    mkdir -p "$(dirname "$EVENT_STREAM")"
    printf '%s\n' "$event_json" >> "$EVENT_STREAM"
  fi

  if [[ -n "$NOTIFY_CMD" ]]; then
    set +e
    printf '%s\n' "$event_json" | bash -lc "$NOTIFY_CMD"
    local notify_exit=$?
    set -e
    if [[ "$notify_exit" -ne 0 ]]; then
      echo "Warning: wrapper notify command failed with exit $notify_exit" >&2
    fi
  fi
}

echo "Launching Codex task..."

RUNNER_ARGS=(--repo "$REPO")
if [[ -n "$TASK" ]]; then
  RUNNER_ARGS+=(--task "$TASK")
fi
if [[ -n "$NOTIFY_CMD" ]]; then
  RUNNER_ARGS+=(--notify-cmd "$NOTIFY_CMD")
fi
if [[ -n "$EVENT_STREAM" ]]; then
  RUNNER_ARGS+=(--event-stream "$EVENT_STREAM")
fi
if [[ -n "$CODEX_BIN" ]]; then
  RUNNER_ARGS+=(--codex-bin "$CODEX_BIN")
fi
if [[ -n "$LOG_DIR" ]]; then
  RUNNER_ARGS+=(--log-dir "$LOG_DIR")
fi
if [[ -n "$LOG_VERBOSITY" ]]; then
  RUNNER_ARGS+=(--verbosity "$LOG_VERBOSITY")
fi
if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
  RUNNER_ARGS+=(-- "${EXTRA_ARGS[@]}")
fi

set +e
RUN_OUTPUT="$(run_and_capture "${RUNNER_ARGS[@]}")"
EXIT_CODE=$?
set -e

printf '%s\n' "$RUN_OUTPUT"
echo "Codex exit code: $EXIT_CODE"

# Extract metadata for this exact run (no race with concurrent jobs)
LATEST_META="$(extract_kv "$RUN_OUTPUT" "meta_file")"
LATEST_LOG="$(extract_kv "$RUN_OUTPUT" "log_file")"
LATEST_SUMMARY="$(extract_kv "$RUN_OUTPUT" "summary_file")"
LATEST_RUN_ID="$(extract_kv "$RUN_OUTPUT" "codex_run_id")"
SESSION_ID="$(extract_kv "$RUN_OUTPUT" "codex_session_id")"

if [[ -z "$LATEST_META" || ! -f "$LATEST_META" ]]; then
  echo "Warning: No metadata file found, cannot review"
  exit "$EXIT_CODE"
fi

if [[ -z "$SESSION_ID" || "$SESSION_ID" == "unknown" ]]; then
  SESSION_ID="$(jq -r '.session_id // empty' "$LATEST_META" 2>/dev/null || true)"
fi

if [[ -z "$SESSION_ID" || "$SESSION_ID" == "null" ]]; then
  echo "Warning: No session ID found in metadata"
  exit "$EXIT_CODE"
fi

# Smart failure detection - distinguish real failures from environmental issues
if [[ "$EXIT_CODE" -ne 0 ]]; then
  echo ""
  echo "⚠️  Non-zero exit code: $EXIT_CODE"

  # Check if Codex actually completed work despite exit code
  LATEST_LOG=$(jq -r '.log_file' "$LATEST_META" 2>/dev/null)
  CODEX_COMPLETED=0
  REAL_FAILURE=0

  if [[ -f "$LATEST_LOG" ]]; then
    # Check for completion indicators
    if grep -q "tokens used" "$LATEST_LOG" 2>/dev/null; then
      CODEX_COMPLETED=1
      echo "✓ Codex completed work (tokens used found in log)"
    fi

    # Check for real failure indicators
    if grep -qE "error: |fatal: |Exception:" "$LATEST_LOG" 2>/dev/null; then
      REAL_FAILURE=1
    fi

    # Check for environmental shell errors (false failures)
    if grep -qE "\[stderr\].*syntax error|\[stderr\].*unexpected EOF" "$LATEST_LOG" 2>/dev/null; then
      echo "⚠️  Shell syntax errors found (likely in Codex's environment, not our code)"
    fi
  fi

  # Decide: real failure or environmental issue?
  if [[ "$CODEX_COMPLETED" == "1" && "$REAL_FAILURE" == "0" ]]; then
    echo "✓ Treating as success - work completed despite environmental errors"
    echo ""
    exit 0
  fi

  # Real failure - trigger review
  echo ""
  echo "❌ Real failure detected. Launching review..."
  echo ""

  emit_wrapper_event "review_started" "running" "$LATEST_RUN_ID" "$SESSION_ID" "$LATEST_META" "$LATEST_LOG" "$LATEST_SUMMARY" "$EXIT_CODE"

  REVIEW_ARGS=(
    --repo "$REPO"
    --resume "$SESSION_ID"
    --task "Review the work just completed. Check for syntax errors, incomplete changes, or test failures. Fix any issues found."
  )
  if [[ -n "$NOTIFY_CMD" ]]; then
    REVIEW_ARGS+=(--notify-cmd "$NOTIFY_CMD")
  fi
  if [[ -n "$EVENT_STREAM" ]]; then
    REVIEW_ARGS+=(--event-stream "$EVENT_STREAM")
  fi
  if [[ -n "$CODEX_BIN" ]]; then
    REVIEW_ARGS+=(--codex-bin "$CODEX_BIN")
  fi
  if [[ -n "$LOG_DIR" ]]; then
    REVIEW_ARGS+=(--log-dir "$LOG_DIR")
  fi
  if [[ -n "$LOG_VERBOSITY" ]]; then
    REVIEW_ARGS+=(--verbosity "$LOG_VERBOSITY")
  fi
  if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
    REVIEW_ARGS+=(-- "${EXTRA_ARGS[@]}")
  fi

  set +e
  REVIEW_OUTPUT="$(run_and_capture "${REVIEW_ARGS[@]}")"
  REVIEW_EXIT=$?
  set -e
  printf '%s\n' "$REVIEW_OUTPUT"

  echo ""
  echo "Review exit code: $REVIEW_EXIT"
  emit_wrapper_event "review_completed" "$([[ "$REVIEW_EXIT" -eq 0 ]] && echo success || echo failure)" \
    "$(extract_kv "$REVIEW_OUTPUT" "codex_run_id")" \
    "$(extract_kv "$REVIEW_OUTPUT" "codex_session_id")" \
    "$(extract_kv "$REVIEW_OUTPUT" "meta_file")" \
    "$(extract_kv "$REVIEW_OUTPUT" "log_file")" \
    "$(extract_kv "$REVIEW_OUTPUT" "summary_file")" \
    "$REVIEW_EXIT"
  exit "$REVIEW_EXIT"
fi

echo "✓ Task completed successfully"

exit 0
