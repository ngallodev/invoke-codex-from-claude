#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  notify_terminal.sh [--title <text>] [--quiet]

Reads a single JSON event from stdin and shows a local terminal/desktop notification.

Options:
  --title <text>  Notification title (default: Codex Job)
  --quiet         Suppress stdout fallback when desktop notification is unavailable
  -h, --help      Show this help text
USAGE
}

TITLE="Codex Job"
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --quiet)
      QUIET=1
      shift
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

PAYLOAD="$(cat)"
if [[ -z "$PAYLOAD" ]]; then
  echo "Error: Expected JSON payload on stdin." >&2
  exit 2
fi

if ! printf '%s' "$PAYLOAD" | python3 -m json.tool >/dev/null 2>&1; then
  echo "Error: Payload is not valid JSON." >&2
  exit 2
fi

MESSAGE="$(
  EVENT_PAYLOAD="$PAYLOAD" python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["EVENT_PAYLOAD"])
event = str(obj.get("event", "event"))
status = str(obj.get("status", "unknown"))
run_id = str(obj.get("run_id", "n/a"))
print(f"{event} {status} run={run_id}")
PY
)"

send_macos() {
  local message="$1"
  local title="$2"
  osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1
}

send_linux() {
  local message="$1"
  local title="$2"
  notify-send "$title" "$message" >/dev/null 2>&1
}

NOTIFIED=0
if command -v notify-send >/dev/null 2>&1; then
  if send_linux "$MESSAGE" "$TITLE"; then
    NOTIFIED=1
  fi
elif command -v osascript >/dev/null 2>&1; then
  if send_macos "$MESSAGE" "$TITLE"; then
    NOTIFIED=1
  fi
fi

if [[ "$NOTIFIED" -eq 0 && "$QUIET" -eq 0 ]]; then
  printf '[%s] %s\n' "$TITLE" "$MESSAGE"
fi

