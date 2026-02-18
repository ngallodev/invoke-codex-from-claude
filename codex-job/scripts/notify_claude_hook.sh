#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  notify_claude_hook.sh [--url <callback_url>] [--timeout <seconds>] [--secret <value>] [--dry-run]

Reads a single JSON event object from stdin and forwards it to a Claude callback endpoint.

Options:
  --url <callback_url>  Callback URL (fallback: CLAUDE_HOOK_URL env var)
  --timeout <seconds>   HTTP timeout in seconds (default: 10)
  --secret <value>      HMAC key (fallback: WEBHOOK_SECRET or CODEX_WEBHOOK_SECRET)
  --dry-run             Print payload instead of sending HTTP request
  -h, --help            Show this help text
USAGE
}

URL="${CLAUDE_HOOK_URL:-}"
TIMEOUT=10
DRY_RUN=0
SECRET="${WEBHOOK_SECRET:-${CODEX_WEBHOOK_SECRET:-}}"
SIGN_PAYLOAD=0

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
    --secret)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --secret requires a value." >&2
        exit 2
      fi
      SECRET="${2}"
      SIGN_PAYLOAD=1
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

if [[ -n "$SECRET" ]]; then
  SIGN_PAYLOAD=1
fi

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

if [[ "$SIGN_PAYLOAD" -eq 1 && -z "$SECRET" ]]; then
  echo "Error: Signing requested but secret is missing (set --secret, WEBHOOK_SECRET, or CODEX_WEBHOOK_SECRET)." >&2
  exit 2
fi

SIGNATURE=""
if [[ "$SIGN_PAYLOAD" -eq 1 ]]; then
  SIGNATURE="$(
    SECRET_ENV="$SECRET" PAYLOAD_ENV="$PAYLOAD" python3 - <<'PY'
import hashlib, hmac, os

secret = os.environ.get("SECRET_ENV", "")
payload = os.environ.get("PAYLOAD_ENV", "")
digest = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
print(digest)
PY
  )"
fi

CURL_HEADERS=(
  -H "Content-Type: application/json"
)
if [[ -n "$SIGNATURE" ]]; then
  CURL_HEADERS+=(-H "X-Signature: sha256=${SIGNATURE}")
fi

printf '%s' "$PAYLOAD" | curl --silent --show-error --fail \
  --max-time "$TIMEOUT" \
  "${CURL_HEADERS[@]}" \
  -X POST \
  --data-binary @- \
  "$URL" >/dev/null
