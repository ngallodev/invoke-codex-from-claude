#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../codex-job/scripts/run_codex_task.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "Error: canonical runner not found at $TARGET" >&2
  exit 2
fi

exec "$TARGET" "$@"
