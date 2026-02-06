#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  run_codex_task.sh --repo <path> --task <text> [options] [-- <extra codex args...>]

Options:
  --repo <path>         Repository/workdir for codex --cwd (required)
  --task <text>         Task prompt for Codex (required)
  --codex-bin <path>    Codex binary/command (default: codex)
  --log-dir <path>      Directory for logs/metadata (default: ./runs)
  --json-out <path>     Write parsed JSON summary to this file
  -h, --help            Show this help text

Examples:
  scripts/run_codex_task.sh --repo /lump/apps/my-repo --task "Fix failing tests"
  scripts/run_codex_task.sh --repo . --task "Implement feature" -- --model gpt-5-codex
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse_codex_run.py"

REPO=""
TASK=""
CODEX_BIN="codex"
LOG_DIR="./runs"
JSON_OUT=""
EXTRA_ARGS=()

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
    --json-out)
      JSON_OUT="${2:-}"
      shift 2
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

if [[ -z "$REPO" || -z "$TASK" ]]; then
  echo "Error: --repo and --task are required." >&2
  usage >&2
  exit 2
fi

if [[ ! -d "$REPO" ]]; then
  echo "Error: repo path does not exist or is not a directory: $REPO" >&2
  exit 2
fi

if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
  echo "Error: codex command not found: $CODEX_BIN" >&2
  exit 127
fi

mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
LOG_FILE="$LOG_DIR/codex-run-$RUN_ID.log"
META_FILE="$LOG_DIR/codex-run-$RUN_ID.meta.json"
START_EPOCH="$(date +%s)"
START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

set +e
"$CODEX_BIN" --cwd "$REPO" "$TASK" "${EXTRA_ARGS[@]}" 2>&1 | tee "$LOG_FILE"
CODEX_EXIT=${PIPESTATUS[0]}
set -e

END_EPOCH="$(date +%s)"
END_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ELAPSED=$((END_EPOCH - START_EPOCH))

python3 - <<PY > "$META_FILE"
import json
obj = {
  "run_id": "$RUN_ID",
  "repo": "$REPO",
  "task": "$TASK",
  "codex_bin": "$CODEX_BIN",
  "log_file": "$LOG_FILE",
  "meta_file": "$META_FILE",
  "started_at": "$START_ISO",
  "ended_at": "$END_ISO",
  "elapsed_seconds": $ELAPSED,
  "exit_code": $CODEX_EXIT,
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

cat <<EOF_SUMMARY
codex_run_id=$RUN_ID
codex_exit_code=$CODEX_EXIT
elapsed_seconds=$ELAPSED
log_file=$LOG_FILE
meta_file=$META_FILE
summary_file=$SUMMARY_PATH
EOF_SUMMARY

if [[ -f "$SUMMARY_PATH" ]]; then
  echo "summary_json=$(cat "$SUMMARY_PATH")"
fi

exit "$CODEX_EXIT"
