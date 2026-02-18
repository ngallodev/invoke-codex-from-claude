#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage:
  run_codex_task.sh --repo <path> [--task <text>] [--resume <session>] [options] [-- <extra codex args...>]

Options:
  --repo <path>         Repository/workdir for codex exec --cd (required)
  --doctor              Run environment diagnostics and exit
  --task <text>         Task prompt for Codex (required unless --resume is used)
  --resume <session>    Resume an existing Codex session by ID (optional)
  --codex-bin <path>    Codex binary/command (default: codex)
  --log-dir <path>      Directory for logs/metadata (default: ./runs)
  --json-out <path>     Write parsed JSON summary to this file
  --notify-cmd <cmd>    Shell command to receive event JSON on stdin
  --event-stream <path> Append event JSON lines to this file
  --tier <level>        Model tier: low (default), medium, high
  -v|-vv|-vvv           Log verbosity: normal, high, extreme
  --verbosity <level>   Log verbosity: low, normal, high, extreme (default: low)
  -h, --help            Show this help text

Environment:
  CODEX_API_KEY         Required for Codex CLI authentication
  CODEX_TIMEOUT_SECONDS Timeout for codex command (default: 1800)
  CODEX_WEBHOOK_SECRET  Optional signing secret for notify hooks
  WEBHOOK_SECRET        Optional signing secret for notify hooks
USAGE
}

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

require_env_var() {
  local name="$1"
  local reason="$2"
  if [[ -z "${!name:-}" ]]; then
    if [[ -n "$reason" ]]; then
      echo "Error: required environment variable $name is not set ($reason)." >&2
    else
      echo "Error: required environment variable $name is not set." >&2
    fi
    exit 2
  fi
}

require_any_env_var() {
  local reason="$1"
  shift
  local name
  for name in "$@"; do
    if [[ -n "${!name:-}" ]]; then
      return 0
    fi
  done
  echo "Error: one of the following environment variables must be set ($reason): $*" >&2
  exit 2
}

DOCTOR_FAILS=0
DOCTOR_WARNINGS=0

REPO=""
TASK=""
RESUME_SESSION=""
CODEX_BIN="codex"
LOG_DIR="./runs"
JSON_OUT=""
LOG_VERBOSITY="${CODEX_LOG_VERBOSITY:-low}"
NOTIFY_CMD=""
EVENT_STREAM=""
DOCTOR_MODE=0
MODEL_TIER=""
EXTRA_ARGS=()
ORIGINAL_ARGS=("$@")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse_codex_run.py"

RUN_ID=""
LOG_FILE=""
META_FILE=""
SUMMARY_PATH=""
START_EPOCH=""
END_EPOCH=""
ELAPSED=""
START_ISO=""
END_ISO=""
START_LOCAL=""
END_LOCAL=""
SESSION_ID="unknown"
MODE="new"
MODEL_SELECTED=""
MODEL_SOURCE=""
CODEX_CMD=()
CODEX_CMD_QUOTED=""
SCRIPT_CMD_QUOTED=""
CODEX_EXIT=1
ERROR_MSG=""
SUMMARY_WRITTEN=0
FINALIZED=0
IN_RUN_MODE=0
RUN_COMPLETED_EVENT_EMITTED=0

DEFAULT_MODEL_TIER="low"
CODEX_TIMEOUT_SECONDS="${CODEX_TIMEOUT_SECONDS:-1800}"

doctor_line() {
  local status="$1"
  local label="$2"
  local detail="$3"
  case "$status" in
    PASS)
      printf '[PASS] %s - %s\n' "$label" "$detail"
      ;;
    WARN)
      DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1))
      printf '[WARN] %s - %s\n' "$label" "$detail"
      ;;
    FAIL|ERROR)
      DOCTOR_FAILS=$((DOCTOR_FAILS + 1))
      printf '[FAIL] %s - %s\n' "$label" "$detail"
      ;;
    *)
      printf '[INFO] %s - %s\n' "$label" "$detail"
      ;;
  esac
}

doctor_check_command() {
  local cmd="$1"
  local fix="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    doctor_line "PASS" "command:$cmd" "found at $(command -v "$cmd")"
  else
    doctor_line "FAIL" "command:$cmd" "$fix"
  fi
}

doctor_check_required_env() {
  local name="$1"
  local help="$2"
  if [[ -n "${!name:-}" ]]; then
    doctor_line "PASS" "env:$name" "set"
  else
    doctor_line "FAIL" "env:$name" "$help"
  fi
}

doctor_check_optional_env() {
  local name="$1"
  local help="$2"
  if [[ -n "${!name:-}" ]]; then
    doctor_line "PASS" "env:$name" "set"
  else
    doctor_line "WARN" "env:$name" "$help"
  fi
}

doctor_check_repo() {
  if [[ -z "$REPO" ]]; then
    doctor_line "FAIL" "repo" "--repo is required for diagnostics"
    return
  fi
  if [[ ! -d "$REPO" ]]; then
    doctor_line "FAIL" "repo" "path is not a directory: $REPO"
    return
  fi
  if [[ ! -r "$REPO" ]]; then
    doctor_line "FAIL" "repo" "not readable: $REPO"
    return
  fi
  if [[ -w "$REPO" ]]; then
    doctor_line "PASS" "repo" "read/write ok at $(cd "$REPO" && pwd)"
  else
    doctor_line "WARN" "repo" "readable but not writable at $(cd "$REPO" && pwd)"
  fi
}

doctor_check_tmp() {
  local tmp_root="${TMPDIR:-/tmp}"
  local tmp_dir
  if tmp_dir="$(mktemp -d "$tmp_root/codex-doctor.XXXXXX" 2>/dev/null)"; then
    if echo "probe" >"$tmp_dir/write-test" 2>/dev/null; then
      doctor_line "PASS" "tempdir" "writable at $tmp_dir"
      rm -f "$tmp_dir/write-test"
    else
      doctor_line "FAIL" "tempdir" "cannot write inside $tmp_dir"
    fi
    rmdir "$tmp_dir" 2>/dev/null || true
  else
    doctor_line "FAIL" "tempdir" "cannot create temp dir under $tmp_root"
  fi
}

doctor_check_codex_ping() {
  if [[ -z "$REPO" || ! -d "$REPO" ]]; then
    doctor_line "WARN" "codex ping" "repo not available; skipping connectivity probe"
    return
  fi
  if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
    doctor_line "WARN" "codex ping" "codex binary not found; skipping connectivity probe"
    return
  fi
  if [[ -z "${CODEX_API_KEY:-}" ]]; then
    doctor_line "WARN" "codex ping" "CODEX_API_KEY missing; skipping connectivity probe"
    return
  fi

  local cmd=("$CODEX_BIN" exec --cd "$REPO" "doctor connectivity probe")
  if command -v timeout >/dev/null 2>&1; then
    cmd=(timeout 5 "${cmd[@]}")
  fi

  set +e
  "${cmd[@]}" >/dev/null 2>&1
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    doctor_line "PASS" "codex ping" "exec probe succeeded"
  else
    doctor_line "WARN" "codex ping" "exec probe failed (exit $status); check CODEX_API_KEY or network"
  fi
}

run_doctor() {
  echo "== Codex Doctor =="
  doctor_check_command "$CODEX_BIN" "Install Codex CLI or pass --codex-bin <path>"
  doctor_check_command "jq" "Install jq to parse summaries"
  doctor_check_command "git" "Install git to capture repo state"
  doctor_check_command "python3" "Install python3 to enable log parsing"

  case "$LOG_VERBOSITY" in
    low|normal|high|extreme)
      doctor_line "PASS" "verbosity" "level set to $LOG_VERBOSITY"
      ;;
    *)
      doctor_line "WARN" "verbosity" "unknown level '$LOG_VERBOSITY'; defaulting to low"
      LOG_VERBOSITY="low"
      ;;
  esac

  doctor_check_required_env "CODEX_API_KEY" "export CODEX_API_KEY=<token> before running Codex"
  doctor_check_optional_env "CODEX_WEBHOOK_SECRET" "set when using --notify-cmd to sign events"
  doctor_check_optional_env "WEBHOOK_SECRET" "set when using --notify-cmd to sign events"

  doctor_check_repo
  doctor_check_tmp
  doctor_check_codex_ping

  if [[ "$DOCTOR_FAILS" -eq 0 ]]; then
    echo "Doctor result: PASS (warnings=$DOCTOR_WARNINGS)"
    return 0
  fi

  echo "Doctor result: FAIL (failures=$DOCTOR_FAILS warnings=$DOCTOR_WARNINGS)"
  return 1
}

detect_model_arg() {
  local prev=""
  local arg
  for arg in "${EXTRA_ARGS[@]}"; do
    if [[ "$prev" == "--model" ]]; then
      echo "$arg"
      return 0
    fi
    if [[ "$arg" == --model=* ]]; then
      echo "${arg#--model=}"
      return 0
    fi
    prev="$arg"
  done
  return 1
}

map_tier_to_model() {
  case "$1" in
    low) echo "gpt-3.5-turbo" ;;
    medium) echo "gpt-4o-mini" ;;
    high) echo "gpt-4o" ;;
    *) return 1 ;;
  esac
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
  EVENT_SUMMARY_FILE="$SUMMARY_PATH" \
  EVENT_STARTED_AT="$START_ISO" \
  EVENT_ENDED_AT="$END_ISO" \
  EVENT_ELAPSED="$ELAPSED" \
  python3 - <<'PY'
import json
import os
from datetime import datetime, timezone


def nullable(name: str):
    value = os.environ.get(name, "")
    if value in ("", "unknown"):
        return None
    return value


def nullable_int(name: str):
    value = os.environ.get(name, "")
    if value == "":
        return None
    try:
        return int(value)
    except ValueError:
        return None

obj = {
    "event": os.environ["EVENT_NAME"],
    "status": os.environ["EVENT_STATUS"],
    "run_id": nullable("EVENT_RUN_ID"),
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

write_meta_file() {
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
  MODEL_SELECTED_ENV="$MODEL_SELECTED" \
  MODEL_TIER_ENV="$MODEL_TIER" \
  MODEL_SOURCE_ENV="$MODEL_SOURCE" \
  python3 - <<'PY' > "$META_FILE"
import json
import os

session_id = os.environ.get("SESSION_ID_ENV") or "unknown"
obj = {
    "run_id": os.environ.get("RUN_ID_ENV"),
    "session_id": None if session_id == "unknown" else session_id,
    "repo": os.environ.get("REPO_ENV"),
    "task": os.environ.get("TASK_ENV") or None,
    "resume_session": os.environ.get("RESUME_SESSION_ENV") or None,
    "codex_bin": os.environ.get("CODEX_BIN_ENV"),
    "log_file": os.environ.get("LOG_FILE_ENV"),
    "meta_file": os.environ.get("META_FILE_ENV"),
    "started_at": os.environ.get("START_ISO_ENV"),
    "ended_at": os.environ.get("END_ISO_ENV"),
    "elapsed_seconds": int(os.environ.get("ELAPSED_ENV", "0")),
    "exit_code": int(os.environ.get("CODEX_EXIT_ENV", "1")),
    "model": os.environ.get("MODEL_SELECTED_ENV") or None,
    "model_tier": os.environ.get("MODEL_TIER_ENV") or None,
    "model_source": os.environ.get("MODEL_SOURCE_ENV") or None,
}
print(json.dumps(obj, ensure_ascii=True, indent=2))
PY
}

write_fallback_summary() {
  local err_msg="$1"
  RUN_ID_ENV="$RUN_ID" \
  SESSION_ID_ENV="$SESSION_ID" \
  REPO_ENV="$REPO" \
  TASK_ENV="$TASK" \
  RESUME_SESSION_ENV="$RESUME_SESSION" \
  START_ISO_ENV="$START_ISO" \
  END_ISO_ENV="$END_ISO" \
  ELAPSED_ENV="$ELAPSED" \
  CODEX_EXIT_ENV="$CODEX_EXIT" \
  MODEL_SELECTED_ENV="$MODEL_SELECTED" \
  MODEL_TIER_ENV="$MODEL_TIER" \
  MODEL_SOURCE_ENV="$MODEL_SOURCE" \
  LOG_FILE_ENV="$LOG_FILE" \
  META_FILE_ENV="$META_FILE" \
  ERR_MSG_ENV="$err_msg" \
  python3 - <<'PY' > "$SUMMARY_PATH"
import json
import os

exit_code = int(os.environ.get("CODEX_EXIT_ENV", "1"))
session_id = os.environ.get("SESSION_ID_ENV") or "unknown"
err = os.environ.get("ERR_MSG_ENV") or None

legacy = {
    "run_id": os.environ.get("RUN_ID_ENV"),
    "session_id": None if session_id == "unknown" else session_id,
    "resume_session": os.environ.get("RESUME_SESSION_ENV") or None,
    "repo": os.environ.get("REPO_ENV"),
    "task": os.environ.get("TASK_ENV") or None,
    "model": os.environ.get("MODEL_SELECTED_ENV") or None,
    "model_tier": os.environ.get("MODEL_TIER_ENV") or None,
    "model_source": os.environ.get("MODEL_SOURCE_ENV") or None,
    "started_at": os.environ.get("START_ISO_ENV"),
    "ended_at": os.environ.get("END_ISO_ENV"),
    "elapsed_seconds": int(os.environ.get("ELAPSED_ENV", "0")),
    "exit_code": exit_code,
    "success": exit_code == 0,
    "log_file": os.environ.get("LOG_FILE_ENV"),
    "meta_file": os.environ.get("META_FILE_ENV"),
    "token_usage": {"input_tokens": None, "output_tokens": None, "total_tokens": None, "evidence": {}},
    "cost": {"usd": None, "evidence": None},
}

obj = {
    "id": os.environ.get("RUN_ID_ENV"),
    "sid": None if session_id == "unknown" else session_id,
    "repo": os.environ.get("REPO_ENV"),
    "task": os.environ.get("TASK_ENV") or None,
    "resume": os.environ.get("RESUME_SESSION_ENV") or None,
    "start": os.environ.get("START_ISO_ENV"),
    "end": os.environ.get("END_ISO_ENV"),
    "time": int(os.environ.get("ELAPSED_ENV", "0")),
    "exit": exit_code,
    "ok": exit_code == 0,
    "mdl": os.environ.get("MODEL_SELECTED_ENV") or None,
    "tier": os.environ.get("MODEL_TIER_ENV") or None,
    "msrc": os.environ.get("MODEL_SOURCE_ENV") or None,
    "log": os.environ.get("LOG_FILE_ENV"),
    "meta": os.environ.get("META_FILE_ENV"),
    "tok": None,
    "cost": None,
    "err": err,
    "src": "run_codex_task.sh",
    "legacy": legacy,
}
print(json.dumps(obj, ensure_ascii=True, separators=(",", ":")))
PY
}

ensure_summary_json() {
  local err_msg="$1"

  if [[ "$SUMMARY_WRITTEN" -eq 1 ]]; then
    return
  fi

  write_meta_file

  if [[ -f "$PARSER" ]]; then
    set +e
    if [[ -x "$PARSER" ]]; then
      "$PARSER" --log "$LOG_FILE" --meta "$META_FILE" > "$SUMMARY_PATH"
    else
      python3 "$PARSER" --log "$LOG_FILE" --meta "$META_FILE" > "$SUMMARY_PATH"
    fi
    local parse_exit=$?
    set -e
    if [[ "$parse_exit" -ne 0 ]]; then
      write_fallback_summary "$err_msg"
    fi
  else
    write_fallback_summary "$err_msg"
  fi

  if [[ -n "$JSON_OUT" ]]; then
    mkdir -p "$(dirname "$JSON_OUT")"
    cp "$SUMMARY_PATH" "$JSON_OUT"
  fi

  SUMMARY_WRITTEN=1
}

print_run_summary_lines() {
  local summary_report_path="$SUMMARY_PATH"
  if [[ -n "$JSON_OUT" ]]; then
    summary_report_path="$JSON_OUT"
  fi

  local lines=(
    "codex_run_id=$RUN_ID"
    "codex_exit_code=$CODEX_EXIT"
    "elapsed_seconds=$ELAPSED"
    "codex_session_id=$SESSION_ID"
    "log_file=$LOG_FILE"
    "meta_file=$META_FILE"
    "summary_file=$summary_report_path"
    "model_selected=$MODEL_SELECTED"
    "model_tier=$MODEL_TIER"
    "model_source=$MODEL_SOURCE"
  )

  if [[ "$LOG_VERBOSITY" != "low" ]]; then
    lines+=("started_at_utc=$START_ISO")
    lines+=("ended_at_utc=$END_ISO")
  fi

  if [[ "$LOG_VERBOSITY" == "high" || "$LOG_VERBOSITY" == "extreme" ]]; then
    lines+=("started_at_local=$START_LOCAL")
    lines+=("ended_at_local=$END_LOCAL")
    lines+=("script_invocation=$SCRIPT_CMD_QUOTED")
    lines+=("codex_command=$CODEX_CMD_QUOTED")
  fi

  printf '%s\n' "${lines[@]}"
}

finish_run() {
  local exit_code="$1"
  local err_msg="$2"

  if [[ "$FINALIZED" -eq 1 ]]; then
    return
  fi
  FINALIZED=1

  set +e

  CODEX_EXIT="$exit_code"
  END_EPOCH="$(date +%s)"
  END_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  END_LOCAL="$(date +%Y-%m-%dT%H:%M:%S%z)"
  ELAPSED=$((END_EPOCH - START_EPOCH))

  SESSION_ID="$({
    grep -i "session.*id" "$LOG_FILE" 2>/dev/null || true
  } | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | tail -1)"

  if [[ -z "$SESSION_ID" ]]; then
    echo "Warning: Could not extract session ID from log" >&2
    SESSION_ID="unknown"
  fi

  ensure_summary_json "$err_msg"

  print_run_summary_lines | tee -a "$LOG_FILE"

  if [[ "$LOG_VERBOSITY" == "low" ]]; then
    echo "summary_json=$(cat "$SUMMARY_PATH")"
  else
    echo "summary_json=$(cat "$SUMMARY_PATH")" | tee -a "$LOG_FILE"
  fi

  if [[ "$RUN_COMPLETED_EVENT_EMITTED" -eq 0 ]]; then
    if [[ "$CODEX_EXIT" -eq 0 ]]; then
      emit_event "$(make_event_json "run_completed" "success" "$CODEX_EXIT")"
    else
      emit_event "$(make_event_json "run_completed" "failure" "$CODEX_EXIT")"
    fi
    RUN_COMPLETED_EVENT_EMITTED=1
  fi

  set -e
}

handle_signal() {
  local sig="$1"
  ERROR_MSG="Interrupted by signal $sig"
  case "$sig" in
    INT) CODEX_EXIT=130 ;;
    TERM) CODEX_EXIT=143 ;;
    *) CODEX_EXIT=1 ;;
  esac
  finish_run "$CODEX_EXIT" "$ERROR_MSG"
  exit "$CODEX_EXIT"
}

trap 'if [[ "$IN_RUN_MODE" -eq 1 ]]; then finish_run "${CODEX_EXIT:-1}" "${ERROR_MSG:-}"; fi' EXIT
trap 'handle_signal INT' INT
trap 'handle_signal TERM' TERM

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
    --resume)
      RESUME_SESSION="${2:-}"
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
    --doctor)
      DOCTOR_MODE=1
      shift
      ;;
    --tier)
      MODEL_TIER="${2:-}"
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
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$LOG_VERBOSITY" in
  low|normal|high|extreme)
    ;;
  *)
    echo "Error: --verbosity must be one of low, normal, high, extreme." >&2
    exit 2
    ;;
esac

if [[ "$DOCTOR_MODE" -eq 1 ]]; then
  run_doctor
  exit $?
fi

IN_RUN_MODE=1

if [[ -z "$REPO" ]]; then
  echo "Error: --repo is required." >&2
  exit 2
fi
if [[ ! -d "$REPO" ]]; then
  echo "Error: --repo is not a directory: $REPO" >&2
  exit 2
fi
if [[ -z "$TASK" && -z "$RESUME_SESSION" ]]; then
  echo "Error: --task is required unless --resume is provided." >&2
  exit 2
fi

require_env_var "CODEX_API_KEY" "Codex CLI authentication"
if [[ -n "$NOTIFY_CMD" ]]; then
  require_any_env_var "notification signing secret" "CODEX_WEBHOOK_SECRET" "WEBHOOK_SECRET"
fi

if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
  echo "Error: codex binary not found: $CODEX_BIN" >&2
  exit 127
fi

if [[ ! "$CODEX_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "Error: CODEX_TIMEOUT_SECONDS must be a non-negative integer." >&2
  exit 2
fi
if [[ "$CODEX_TIMEOUT_SECONDS" -gt 0 ]] && ! command -v timeout >/dev/null 2>&1; then
  echo "Error: timeout command is required for enforcing CODEX_TIMEOUT_SECONDS." >&2
  exit 127
fi

if [[ -z "$MODEL_TIER" ]]; then
  MODEL_TIER="$DEFAULT_MODEL_TIER"
fi
case "$MODEL_TIER" in
  low|medium|high)
    ;;
  *)
    echo "Error: --tier must be low, medium, or high." >&2
    exit 2
    ;;
esac

EXPLICIT_MODEL="$(detect_model_arg || true)"
if [[ -n "$EXPLICIT_MODEL" ]]; then
  MODEL_SELECTED="$EXPLICIT_MODEL"
  MODEL_SOURCE="explicit_model"
else
  MODEL_SELECTED="$(map_tier_to_model "$MODEL_TIER")"
  if [[ "$MODEL_TIER" == "$DEFAULT_MODEL_TIER" ]]; then
    MODEL_SOURCE="tier_default"
  else
    MODEL_SOURCE="tier_flag"
  fi
  EXTRA_ARGS+=("--model" "$MODEL_SELECTED")
fi

if [[ -n "$RESUME_SESSION" ]]; then
  MODE="resume"
  if [[ -n "$TASK" ]]; then
    CODEX_CMD=("$CODEX_BIN" exec --cd "$REPO" resume "$RESUME_SESSION" "$TASK" "${EXTRA_ARGS[@]}")
  else
    CODEX_CMD=("$CODEX_BIN" exec --cd "$REPO" resume "$RESUME_SESSION" "${EXTRA_ARGS[@]}")
  fi
else
  MODE="new"
  CODEX_CMD=("$CODEX_BIN" exec --cd "$REPO" "$TASK" "${EXTRA_ARGS[@]}")
fi

mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$(printf '%06d' "$((RANDOM % 1000000))")"
LOG_FILE="$LOG_DIR/codex-run-$RUN_ID.log"
META_FILE="$LOG_DIR/codex-run-$RUN_ID.meta.json"
SUMMARY_PATH="$LOG_DIR/codex-run-$RUN_ID.summary.json"

START_EPOCH="$(date +%s)"
START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_LOCAL="$(date +%Y-%m-%dT%H:%M:%S%z)"

SCRIPT_CMD_QUOTED="$(shell_join "$0" "${ORIGINAL_ARGS[@]}")"
CODEX_CMD_QUOTED="$(shell_join "${CODEX_CMD[@]}")"

: > "$LOG_FILE"
{
  echo "codex_run_id=$RUN_ID"
  echo "log_file=$LOG_FILE"
  echo "meta_file=$META_FILE"
  echo "summary_file_pending=$SUMMARY_PATH"
} | tee -a "$LOG_FILE"

if [[ "$LOG_VERBOSITY" == "high" || "$LOG_VERBOSITY" == "extreme" ]]; then
  {
    echo "script_invocation=$SCRIPT_CMD_QUOTED"
    echo "codex_command=$CODEX_CMD_QUOTED"
  } >> "$LOG_FILE"
fi

emit_event "$(make_event_json "run_started" "running")"

set +e
if [[ "$CODEX_TIMEOUT_SECONDS" -gt 0 ]]; then
  timeout -s TERM "$CODEX_TIMEOUT_SECONDS" "${CODEX_CMD[@]}" 2>&1 | tee -a "$LOG_FILE"
  CODEX_EXIT=${PIPESTATUS[0]}
  if [[ "$CODEX_EXIT" -eq 124 ]]; then
    ERROR_MSG="Codex run timed out after ${CODEX_TIMEOUT_SECONDS}s"
  fi
else
  "${CODEX_CMD[@]}" 2>&1 | tee -a "$LOG_FILE"
  CODEX_EXIT=${PIPESTATUS[0]}
fi
set -e

finish_run "$CODEX_EXIT" "$ERROR_MSG"
exit "$CODEX_EXIT"
