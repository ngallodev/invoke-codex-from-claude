#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install.sh --scope <project|user|global> [--uninstall]

Options:
  --scope <project|user|global> Install scope (required)
  --uninstall             Remove the skill instead of installing
  -h, --help              Show this help text
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/.claude/skills/codex-job"
SCOPE=""
UNINSTALL=0

SCRIPT_FILES=(
  "invoke_codex_with_review.sh"
  "run_codex_task.sh"
  "parse_codex_run.py"
  "notify_claude_hook.sh"
  "notify_terminal.sh"
  "verify_codex_work.sh"
)

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
    DEST_CLAUDE_ROOT="$SCRIPT_DIR/.claude"
    ;;
  user|global)
    DEST_CLAUDE_ROOT="$HOME/.claude"
    ;;
  *)
    echo "Error: --scope must be project, user, or global." >&2
    exit 2
    ;;
esac

if [[ ! -d "$SKILL_SRC" ]]; then
  echo "Error: skill source not found: $SKILL_SRC" >&2
  exit 2
fi

DEST_SKILLS_ROOT="$DEST_CLAUDE_ROOT/skills"
DEST_SCRIPTS_ROOT="$DEST_CLAUDE_ROOT/scripts"  # legacy cleanup path only
DEST_SKILL="$DEST_SKILLS_ROOT/$(basename "$SKILL_SRC")"

if [[ "$UNINSTALL" -eq 1 ]]; then
  if [[ -d "$DEST_SKILL" ]]; then
    rm -rf "$DEST_SKILL"
    echo "Removed skill: $DEST_SKILL"
  else
    echo "Skill not installed: $DEST_SKILL"
  fi

  # Clean legacy root-level runtime scripts from older installs.
  for script_name in "${SCRIPT_FILES[@]}"; do
    target="$DEST_SCRIPTS_ROOT/$script_name"
    if [[ -f "$target" ]]; then
      rm -f "$target"
      echo "Removed legacy root script: $target"
    fi
  done
  exit 0
fi

mkdir -p "$DEST_SKILLS_ROOT"

if [[ -d "$DEST_SKILL" ]]; then
  rm -rf "$DEST_SKILL"
fi
cp -R "$SKILL_SRC" "$DEST_SKILL"
echo "Installed skill: $DEST_SKILL"

# Canonical runtime location: skill-local scripts directory.
DEST_SKILL_SCRIPTS_DIR="$DEST_SKILL/scripts"
mkdir -p "$DEST_SKILL_SCRIPTS_DIR"

for script_name in "${SCRIPT_FILES[@]}"; do
  src="$SCRIPT_DIR/scripts/$script_name"
  dest_skill="$DEST_SKILL_SCRIPTS_DIR/$script_name"

  if [[ ! -f "$src" ]]; then
    echo "Warning: missing source script: $src" >&2
    continue
  fi

  cp "$src" "$dest_skill"
  chmod +x "$dest_skill"
  echo "Installed skill-local script: $dest_skill"
done
