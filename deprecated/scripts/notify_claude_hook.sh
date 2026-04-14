#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../codex-job/scripts/notify_claude_hook.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "Error: canonical script not found at $TARGET" >&2
  exit 2
fi

exec "$TARGET" "$@"
