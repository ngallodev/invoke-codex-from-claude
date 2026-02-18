#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI_DIR="$ROOT_DIR/ui"

if [[ ! -d "$UI_DIR" ]]; then
  echo "UI directory not found: $UI_DIR" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node is required but not found on PATH." >&2
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required but not found on PATH." >&2
  exit 1
fi

node_major="$(node -p 'process.versions.node.split(".")[0]')"
if [[ "$node_major" -lt 18 ]]; then
  echo "Node >= 18 is required. Current: $(node -v)" >&2
  exit 1
fi

echo "Installing UI dependencies in $UI_DIR"
(cd "$UI_DIR" && npm install)

if [[ "${INSTALL_PLAYWRIGHT_BROWSERS:-0}" == "1" ]]; then
  echo "Installing Playwright browsers"
  (cd "$UI_DIR" && npx playwright install)
fi

echo "Running UI smoke checks"
(cd "$UI_DIR" && npm run test && npm run build)

cat <<'EOF'
UI bootstrap complete.
Run:
  cd ui
  npm run dev
EOF
