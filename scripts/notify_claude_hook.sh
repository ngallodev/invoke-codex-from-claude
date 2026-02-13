#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  notify_claude_hook.sh [--url <callback_url>] [--timeout <seconds>] [--dry-run]

Reads a single JSON event object from stdin and forwards it to a Claude callback endpoint.

Options:
  --url <callback_url>  Callback URL (fallback: CLAUDE_HOOK_URL env var)
  --timeout <seconds>   HTTP timeout in seconds (default: 10)
  --dry-run             Print payload instead of sending HTTP request
  -h, --help            Show this help text
USAGE
}

URL="${CLAUDE_HOOK_URL:-}"
TIMEOUT=10
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

# Validate payload is JSON before sending.
if ! printf '%s' "$PAYLOAD" | python3 -m json.tool >/dev/null 2>&1; then
  echo "Error: Payload is not valid JSON." >&2
  exit 2
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "$PAYLOAD"
  exit 0
fi

if [[ -z "$URL" ]]; then
  echo "Error: Missing callback URL. Set CLAUDE_HOOK_URL or pass --url." >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required to send callback events." >&2
  exit 127
fi

printf '%s' "$PAYLOAD" | curl --silent --show-error --fail \
  --max-time "$TIMEOUT" \
  -H "Content-Type: application/json" \
  -X POST \
  --data-binary @- \
  "$URL" >/dev/null
