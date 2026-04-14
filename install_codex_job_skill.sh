#!/usr/bin/env bash
set -euo pipefail
umask 077

require_env_var() {
  local name="$1"
  local reason="$2"

  if [[ -z "${!name:-}" ]]; then
    if [[ -n "$reason" ]]; then
      echo "Error: required environment variable $name is not set ($reason)." >&2
    else
      echo "Error: required environment variable $name is not set." >&2
    fi
    exit 2
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  install_codex_job_skill.sh --scope <project|user|global> [options]

Options:
  --scope <project|user|global>  Install scope (required)
  --claude-home <path>           Override target Claude home (~/.claude)
  --profile <path>               Shell profile to update (default: auto-detect)
  --no-profile                   Skip PATH/profile edits
  --include-experimental         Install deferred Phase 2/3 runtime scripts (queue/dashboard)
  --dry-run                      Show actions without changing files
  -h, --help                     Show this help text

Examples:
  install_codex_job_skill.sh --scope user
  install_codex_job_skill.sh --scope user --dry-run
  install_codex_job_skill.sh --scope user --profile ~/.bashrc
  install_codex_job_skill.sh --scope project --no-profile
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="codex-job"
SKILL_SRC_ROOT="$SCRIPT_DIR/codex-job"

SCOPE=""
DRY_RUN=0
CLAUDE_HOME_OVERRIDE=""
PROFILE_OVERRIDE=""
NO_PROFILE=0
INCLUDE_EXPERIMENTAL=0

PROFILE_START="# >>> codex-job path (invoke-codex-from-claude)"
PROFILE_END="# <<< codex-job path (invoke-codex-from-claude)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --claude-home)
      CLAUDE_HOME_OVERRIDE="${2:-}"
      shift 2
      ;;
    --profile)
      PROFILE_OVERRIDE="${2:-}"
      shift 2
      ;;
    --no-profile)
      NO_PROFILE=1
      shift
      ;;
    --include-experimental)
      INCLUDE_EXPERIMENTAL=1
      shift
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

if [[ -z "$SCOPE" ]]; then
  echo "Error: --scope is required." >&2
  usage >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required for installation." >&2
  exit 127
fi

case "$SCOPE" in
  project)
    DEST_CLAUDE_ROOT="${CLAUDE_HOME_OVERRIDE:-$SCRIPT_DIR/.claude}"
    ;;
  user|global)
    require_env_var "HOME" "user/global scope resolution"
    DEST_CLAUDE_ROOT="${CLAUDE_HOME_OVERRIDE:-$HOME/.claude}"
    ;;
  *)
    echo "Error: --scope must be project, user, or global." >&2
    exit 2
    ;;
esac

if [[ ! -d "$SKILL_SRC_ROOT" ]]; then
  echo "Error: skill source not found: $SKILL_SRC_ROOT" >&2
  exit 2
fi

abs_path() {
  python3 - "$1" <<'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().resolve())
PY
}

DEST_CLAUDE_ROOT="$(abs_path "$DEST_CLAUDE_ROOT")"
DEST_SKILLS_ROOT="$DEST_CLAUDE_ROOT/skills"
DEST_SKILL="$DEST_SKILLS_ROOT/$SKILL_NAME"
DEST_SKILL_SCRIPTS="$DEST_SKILL/scripts"
SOURCE_FILES_ROOT="$SKILL_SRC_ROOT"

log_step() {
  local msg="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $msg"
  else
    echo "$msg"
  fi
}

ensure_dir() {
  local dir="$1"
  log_step "Ensure directory $dir"
  [[ "$DRY_RUN" -eq 1 ]] || mkdir -p "$dir"
}

sync_skill_tree() {
  ensure_dir "$DEST_SKILL"

  local src rel dest
  while IFS= read -r src; do
    rel="${src#"$SOURCE_FILES_ROOT"/}"
    dest="$DEST_SKILL/$rel"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_step "Copy $src -> $dest"
    else
      mkdir -p "$(dirname "$dest")"
      cp -p "$src" "$dest"
    fi
  done < <(
    find "$SOURCE_FILES_ROOT" \
      \( -type d -name '__pycache__' -prune \) -o \
      \( -type f ! -name '*.pyc' -print \) | sort
  )
}

update_profile_block() {
  local profile_path="$1"
  local path_entry="$2"

  if [[ "$NO_PROFILE" -eq 1 ]]; then
    log_step "Skipping profile update (disabled)"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_step "Ensure PATH entry for $path_entry in $profile_path"
    return
  fi

  local stamp
  stamp="# Added by invoke-codex-from-claude install_codex_job_skill.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)"

  python3 - "$profile_path" "$PROFILE_START" "$PROFILE_END" "$stamp" "$path_entry" <<'PY'
import sys
from pathlib import Path

profile = Path(sys.argv[1])
start, end, stamp, path_entry = sys.argv[2:6]
export_line = f'export PATH="{path_entry}:$PATH"'

text = profile.read_text() if profile.exists() else ""
out = []
skipping = False
for line in text.splitlines():
    if line.strip() == start:
        skipping = True
        continue
    if skipping and line.strip() == end:
        skipping = False
        continue
    if not skipping:
        out.append(line)

if out and out[-1].strip():
    out.append("")

out.extend([start, stamp, export_line, end])
profile.parent.mkdir(parents=True, exist_ok=True)
profile.write_text("\n".join(out) + "\n")
PY
  log_step "Updated PATH block in $profile_path"
}

detect_profile_path() {
  if [[ -n "$PROFILE_OVERRIDE" ]]; then
    echo "$PROFILE_OVERRIDE"
    return
  fi

  if [[ "$SCOPE" == "project" ]]; then
    return
  fi

  require_env_var "HOME" "profile detection"
  local candidates=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile")
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
  echo "$HOME/.profile"
}

# Execution

log_step "Scope: $SCOPE"
log_step "Claude root: $DEST_CLAUDE_ROOT"
if [[ "$INCLUDE_EXPERIMENTAL" -eq 1 ]]; then
  log_step "--include-experimental is no-op; all codex-job scripts are installed."
fi

sync_skill_tree

PROFILE_PATH="$(detect_profile_path)"
if [[ -n "${PROFILE_PATH:-}" ]]; then
  update_profile_block "$PROFILE_PATH" "$DEST_SKILL_SCRIPTS"
else
  log_step "No profile updated (project scope or not provided)"
fi

log_step "Install completed"
