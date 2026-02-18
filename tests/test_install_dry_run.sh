#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

run_install_dry_run() {
  "$ROOT_DIR/install.sh" --scope project --dry-run >/dev/null
}

run_uninstall_dry_run() {
  "$ROOT_DIR/uninstall.sh" --scope project --dry-run >/dev/null
}

run_install_dry_run
run_uninstall_dry_run

echo "[PASS] install/uninstall dry-run completed without changes"
