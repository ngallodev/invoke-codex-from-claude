#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI_DIR="$ROOT_DIR/ui"
fail=0

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[PASS] command:$cmd"
  else
    echo "[FAIL] command:$cmd missing"
    fail=1
  fi
}

check_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "[PASS] path:$path"
  else
    echo "[FAIL] path:$path missing"
    fail=1
  fi
}

echo "UI doctor starting"
check_cmd node
check_cmd npm
check_path "$UI_DIR/package.json"
check_path "$UI_DIR/src/App.tsx"

if command -v node >/dev/null 2>&1; then
  echo "[INFO] node_version=$(node -v)"
fi
if command -v npm >/dev/null 2>&1; then
  echo "[INFO] npm_version=$(npm -v)"
fi

if [[ -d "$UI_DIR/node_modules" ]]; then
  echo "[PASS] ui/node_modules exists"
else
  echo "[WARN] ui/node_modules missing (run scripts/bootstrap_ui.sh)"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "UI doctor result: FAIL" >&2
  exit 1
fi
echo "UI doctor result: PASS"
