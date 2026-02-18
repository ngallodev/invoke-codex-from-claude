#!/usr/bin/env bash
set -euo pipefail

shell_join() {
  local out=""
  local arg quoted
  for arg in "$@"; do
    printf -v quoted '%q' "$arg"
    if [[ -n "$out" ]]; then
      out+=" "
    fi
    out+="$quoted"
  done
  printf '%s' "$out"
}

usage() {
  cat <<'USAGE'
Usage:
  run_codex_task.sh --repo <path> [--task <text>] [--resume <session>] [options] [-- <extra codex args...>]

Options:
  --repo <path>         Repository/workdir for codex exec --cd (required)
  --task <text>         Task prompt for Codex (required unless --resume is used)
  --resume <session>    Resume an existing Codex session by ID (optional)
  --codex-bin <path>    Codex binary/command (default: codex)
  --log-dir <path>      Directory for logs/metadata (default: ./runs)
  --json-out <path>     Write parsed JSON summary to this file
  --notify-cmd <cmd>    Shell command to receive event JSON on stdin
  --event-stream <path> Append event JSON lines to this file
  -v|-vv|-vvv           Log verbosity: normal, high, extreme
  --verbosity <level>   Log verbosity: low, normal, high, extreme (default: low)
  -h, --help            Show this help text

Examples:
  scripts/run_codex_task.sh --repo /path/to/your/repo --task "Fix failing tests"
  scripts/run_codex_task.sh --repo . --task "Implement feature" -- --model gpt-5-codex
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse_codex_run.py"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
ORIGINAL_ARGS=("$@")

REPO=""
TASK=""
RESUME_SESSION=""
CODEX_BIN="codex"
LOG_DIR="./runs"
JSON_OUT=""
LOG_VERBOSITY="${CODEX_LOG_VERBOSITY:-low}"
NOTIFY_CMD=""
EVENT_STREAM=""
EXTRA_ARGS=()

make_event_json() {
  local event_name="$1"
  local event_status="$2"
  local event_exit="${3:-}"

  EVENT_NAME="$event_name" \
  EVENT_STATUS="$event_status" \
  EVENT_EXIT="$event_exit" \
  EVENT_RUN_ID="$RUN_ID" \
  EVENT_SESSION_ID="$SESSION_ID" \
  EVENT_REPO="$REPO" \
  EVENT_MODE="$MODE" \
  EVENT_LOG_FILE="$LOG_FILE" \
  EVENT_META_FILE="$META_FILE" \
  EVENT_SUMMARY_FILE="$EVENT_SUMMARY_FILE" \
  EVENT_STARTED_AT="$START_ISO" \
  EVENT_ENDED_AT="$END_ISO" \
  EVENT_ELAPSED="$ELAPSED" \
  python3 - <<'PY'
import json
import os
from datetime import datetime, timezone


def nullable(name: str):
    value = os.environ.get(name, "")
    if value == "" or value == "unknown":
        return None
    return value


def nullable_int(name: str):
    value = os.environ.get(name, "")
    if value == "":
        return None
    return int(value)


obj = {
    "event": os.environ["EVENT_NAME"],
    "status": os.environ["EVENT_STATUS"],
    "run_id": os.environ["EVENT_RUN_ID"],
    "session_id": nullable("EVENT_SESSION_ID"),
    "repo": nullable("EVENT_REPO"),
    "mode": nullable("EVENT_MODE"),
    "exit_code": nullable_int("EVENT_EXIT"),
    "log_file": nullable("EVENT_LOG_FILE"),
    "meta_file": nullable("EVENT_META_FILE"),
    "summary_file": nullable("EVENT_SUMMARY_FILE"),
    "started_at": nullable("EVENT_STARTED_AT"),
    "ended_at": nullable("EVENT_ENDED_AT"),
    "elapsed_seconds": nullable_int("EVENT_ELAPSED"),
    "source": "run_codex_task.sh",
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
print(json.dumps(obj, ensure_ascii=True))
PY
}

emit_event() {
  local event_json="$1"

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
      echo "Warning: notify command failed with exit $notify_exit" >&2
    fi
  fi
}

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
    --codex-bin)
      CODEX_BIN="${2:-}"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="${2:-}"
      shift 2
      ;;
    --resume)
      RESUME_SESSION="${2:-}"
      shift 2
      ;;
    --json-out)
      JSON_OUT="${2:-}"
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
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      EXTRA_ARGS=("$@")
      break
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Error: --repo is required." >&2
  usage >&2
  exit 2
fi

if [[ -z "$RESUME_SESSION" && -z "$TASK" ]]; then
  echo "Error: --task is required (unless --resume is provided)." >&2
  usage >&2
  exit 2
fi

case "$LOG_VERBOSITY" in
  low|normal|high|extreme)
    ;;
  *)
    echo "Error: --verbosity must be low, normal, high, or extreme." >&2
    exit 2
    ;;
esac

if [[ ! -d "$REPO" ]]; then
  echo "Error: repo path does not exist or is not a directory: $REPO" >&2
  exit 2
fi

if ! CODEX_BIN_PATH="$(command -v "$CODEX_BIN" 2>/dev/null)"; then
  echo "Error: codex command not found: $CODEX_BIN" >&2
  exit 127
fi

mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
LOG_FILE="$LOG_DIR/codex-run-$RUN_ID.log"
META_FILE="$LOG_DIR/codex-run-$RUN_ID.meta.json"
if [[ -n "$JSON_OUT" ]]; then
  SUMMARY_PENDING="$JSON_OUT"
else
  SUMMARY_PENDING="$LOG_DIR/codex-run-$RUN_ID.summary.json"
fi
if [[ -n "$EVENT_STREAM" ]]; then
  mkdir -p "$(dirname "$EVENT_STREAM")"
fi
START_EPOCH="$(date +%s)"
START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_LOCAL="$(date +%Y-%m-%dT%H:%M:%S%z)"
SCRIPT_CMD=("$0" "${ORIGINAL_ARGS[@]}")
if [[ -n "$RESUME_SESSION" ]]; then
  if [[ -n "$TASK" ]]; then
    CODEX_CMD=("$CODEX_BIN_PATH" exec --cd "$REPO" resume "$RESUME_SESSION" "$TASK" "${EXTRA_ARGS[@]}")
  else
    CODEX_CMD=("$CODEX_BIN_PATH" exec --cd "$REPO" resume "$RESUME_SESSION" "${EXTRA_ARGS[@]}")
  fi
else
  CODEX_CMD=("$CODEX_BIN_PATH" exec --cd "$REPO" "$TASK" "${EXTRA_ARGS[@]}")
fi
SCRIPT_CMD_QUOTED="$(shell_join "${SCRIPT_CMD[@]}")"
CODEX_CMD_QUOTED="$(shell_join "${CODEX_CMD[@]}")"

# Emit run info for background callers BEFORE execution
cat <<EOF_PRERUN
codex_run_id=$RUN_ID
log_file=$LOG_FILE
meta_file=$META_FILE
summary_file_pending=$SUMMARY_PENDING
EOF_PRERUN

MODE="new"
if [[ -n "$RESUME_SESSION" ]]; then
  MODE="resume"
fi
SESSION_ID="unknown"
END_ISO=""
ELAPSED=""
EVENT_SUMMARY_FILE="$SUMMARY_PENDING"

emit_event "$(make_event_json "run_started" "running")"

: > "$LOG_FILE"

if [[ "$LOG_VERBOSITY" == "high" || "$LOG_VERBOSITY" == "extreme" ]]; then
  {
    echo "===== run_codex_task.sh debug preamble ====="
    echo "timestamp_utc=$START_ISO"
    echo "timestamp_local=$START_LOCAL"
    echo "mode=$MODE"
    echo "resume_session_id=${RESUME_SESSION:-none}"
    echo "script_path=$SCRIPT_PATH"
    echo "script_pwd=$(pwd)"
    echo "script_invocation=$SCRIPT_CMD_QUOTED"
    echo "script_args_count=${#ORIGINAL_ARGS[@]}"
    echo "repo=$REPO"
    echo "repo_abs=$(cd "$REPO" && pwd)"
    echo "log_dir=$LOG_DIR"
    echo "log_file=$LOG_FILE"
    echo "meta_file=$META_FILE"
    echo "json_out=${JSON_OUT:-}"
    echo "codex_bin_input=$CODEX_BIN"
    echo "codex_bin_resolved=$CODEX_BIN_PATH"
    echo "codex_command=$CODEX_CMD_QUOTED"
    echo "caller_user=${USER:-unknown}"
    echo "caller_host=$(hostname 2>/dev/null || true)"
    echo "shell=${SHELL:-unknown}"
    echo "bash_version=${BASH_VERSION:-unknown}"
    echo "uname=$(uname -a 2>/dev/null || true)"
    echo "PATH=$PATH"
    if "$CODEX_BIN_PATH" --version >/dev/null 2>&1; then
      echo "codex_version=$("$CODEX_BIN_PATH" --version | head -n1)"
    else
      echo "codex_version=<unavailable>"
    fi
    echo "===== end preamble ====="
  } | tee -a "$LOG_FILE"
elif [[ "$LOG_VERBOSITY" == "normal" ]]; then
  {
    echo "timestamp_utc=$START_ISO"
    echo "mode=$MODE"
    echo "repo=$REPO"
    echo "log_file=$LOG_FILE"
    echo "meta_file=$META_FILE"
    echo "summary_file_pending=$SUMMARY_PENDING"
    echo "codex_command=$CODEX_CMD_QUOTED"
  } | tee -a "$LOG_FILE"
fi

set +e
"${CODEX_CMD[@]}" 2>&1 | tee -a "$LOG_FILE"
CODEX_EXIT=${PIPESTATUS[0]}
set -e

END_EPOCH="$(date +%s)"
END_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
END_LOCAL="$(date +%Y-%m-%dT%H:%M:%S%z)"
ELAPSED=$((END_EPOCH - START_EPOCH))

# Extract session ID with robust pattern matching (UUID, case-insensitive)
set +e
SESSION_ID=$(
  grep -i "session.*id" "$LOG_FILE" 2>/dev/null |
    grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' |
    tail -1
)
set -e
if [[ -z "$SESSION_ID" ]]; then
  echo "Warning: Could not extract session ID from log" >&2
  SESSION_ID="unknown"
fi

RUN_ID_ENV="$RUN_ID" \
SESSION_ID_ENV="$SESSION_ID" \
REPO_ENV="$REPO" \
TASK_ENV="$TASK" \
RESUME_SESSION_ENV="$RESUME_SESSION" \
CODEX_BIN_ENV="$CODEX_BIN" \
LOG_FILE_ENV="$LOG_FILE" \
META_FILE_ENV="$META_FILE" \
START_ISO_ENV="$START_ISO" \
END_ISO_ENV="$END_ISO" \
ELAPSED_ENV="$ELAPSED" \
CODEX_EXIT_ENV="$CODEX_EXIT" \
python3 - <<'PY' > "$META_FILE"
import json
import os

session_id = os.environ["SESSION_ID_ENV"]
task = os.environ["TASK_ENV"]
resume_session = os.environ["RESUME_SESSION_ENV"]

obj = {
    "run_id": os.environ["RUN_ID_ENV"],
    "session_id": None if session_id == "unknown" else session_id,
    "repo": os.environ["REPO_ENV"],
    "task": task if task else None,
    "resume_session": resume_session if resume_session else None,
    "codex_bin": os.environ["CODEX_BIN_ENV"],
    "log_file": os.environ["LOG_FILE_ENV"],
    "meta_file": os.environ["META_FILE_ENV"],
    "started_at": os.environ["START_ISO_ENV"],
    "ended_at": os.environ["END_ISO_ENV"],
    "elapsed_seconds": int(os.environ["ELAPSED_ENV"]),
    "exit_code": int(os.environ["CODEX_EXIT_ENV"]),
}
print(json.dumps(obj, ensure_ascii=True, indent=2))
PY

if [[ -x "$PARSER" ]]; then
  PARSER_CMD=("$PARSER" --log "$LOG_FILE" --meta "$META_FILE")
else
  PARSER_CMD=(python3 "$PARSER" --log "$LOG_FILE" --meta "$META_FILE")
fi

if [[ -n "$JSON_OUT" ]]; then
  mkdir -p "$(dirname "$JSON_OUT")"
  "${PARSER_CMD[@]}" > "$JSON_OUT"
  SUMMARY_PATH="$JSON_OUT"
else
  SUMMARY_PATH="$LOG_DIR/codex-run-$RUN_ID.summary.json"
  "${PARSER_CMD[@]}" > "$SUMMARY_PATH"
fi
EVENT_SUMMARY_FILE="$SUMMARY_PATH"

SUMMARY_LINES=(
  "codex_run_id=$RUN_ID"
  "codex_exit_code=$CODEX_EXIT"
  "elapsed_seconds=$ELAPSED"
  "codex_session_id=$SESSION_ID"
  "log_file=$LOG_FILE"
  "meta_file=$META_FILE"
  "summary_file=$SUMMARY_PATH"
)
if [[ "$LOG_VERBOSITY" != "low" ]]; then
  SUMMARY_LINES+=("started_at_utc=$START_ISO")
  SUMMARY_LINES+=("ended_at_utc=$END_ISO")
fi
if [[ "$LOG_VERBOSITY" == "high" || "$LOG_VERBOSITY" == "extreme" ]]; then
  SUMMARY_LINES+=("started_at_local=$START_LOCAL")
  SUMMARY_LINES+=("ended_at_local=$END_LOCAL")
  SUMMARY_LINES+=("script_invocation=$SCRIPT_CMD_QUOTED")
  SUMMARY_LINES+=("codex_command=$CODEX_CMD_QUOTED")
fi
printf '%s\n' "${SUMMARY_LINES[@]}" | tee -a "$LOG_FILE"

if [[ -f "$SUMMARY_PATH" ]]; then
  if [[ "$LOG_VERBOSITY" == "low" ]]; then
    echo "summary_json=$(cat "$SUMMARY_PATH")"
  else
    echo "summary_json=$(cat "$SUMMARY_PATH")" | tee -a "$LOG_FILE"
  fi
fi

if [[ "$CODEX_EXIT" -eq 0 ]]; then
  emit_event "$(make_event_json "run_completed" "success" "$CODEX_EXIT")"
else
  emit_event "$(make_event_json "run_completed" "failure" "$CODEX_EXIT")"
fi

exit "$CODEX_EXIT"
