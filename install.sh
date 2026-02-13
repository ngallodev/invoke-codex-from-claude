#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install.sh --scope <project|user> [--uninstall]

Options:
  --scope <project|user>  Install scope (required)
  --uninstall             Remove the skill instead of installing
  -h, --help              Show this help text
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/.claude/skills/codex-job"
SCOPE=""
UNINSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
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

if [[ -z "$SCOPE" ]]; then
  echo "Error: --scope is required." >&2
  usage >&2
  exit 2
fi

case "$SCOPE" in
  project)
    DEST_ROOT="$SCRIPT_DIR/.claude/skills"
    ;;
  user)
    DEST_ROOT="$HOME/.claude/skills"
    ;;
  *)
    echo "Error: --scope must be project or user." >&2
    exit 2
    ;;
esac

if [[ ! -d "$SKILL_SRC" ]]; then
  echo "Error: skill source not found: $SKILL_SRC" >&2
  exit 2
fi

DEST="$DEST_ROOT/$(basename "$SKILL_SRC")"

if [[ "$UNINSTALL" -eq 1 ]]; then
  if [[ -d "$DEST" ]]; then
    rm -rf "$DEST"
    echo "Removed: $DEST"
  else
    echo "Not installed: $DEST"
  fi
  exit 0
fi

mkdir -p "$DEST_ROOT"
if [[ -d "$DEST" ]]; then
  rm -rf "$DEST"
fi
cp -R "$SKILL_SRC" "$DEST"
echo "Installed: $DEST"
