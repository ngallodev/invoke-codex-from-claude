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
  install.sh --scope <project|user|global> [options]

Options:
  --scope <project|user|global>  Install scope (required)
  --claude-home <path>           Override target Claude home (~/.claude)
  --profile <path>               Shell profile to update (default: auto-detect)
  --no-profile                   Skip PATH/profile edits
  --include-experimental         Install deferred Phase 2/3 runtime scripts (queue/dashboard)
  --dry-run                      Show actions without changing files
  -h, --help                     Show this help text

Examples:
  install.sh --scope user
  install.sh --scope user --dry-run
  install.sh --scope user --profile ~/.bashrc
  install.sh --scope project --no-profile
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/.claude/skills/codex-job"
SCRIPT_SRC_DIR="$SCRIPT_DIR/codex-job/scripts"
CORE_SCRIPT_FILES=(
  "codex_task.py"
  "invoke_codex_with_review.sh"
  "invoke_gemini_with_review.sh"
  "run_codex_task.sh"
  "run_gemini_task.sh"
  "parse_codex_run.py"
  "parse_gemini_run.py"
  "summarize_codex_run.py"
  "notify_claude_hook.sh"
  "notify_terminal.sh"
  "verify_codex_work.sh"
  "write_delegation_metric.py"
)
EXPERIMENTAL_SCRIPT_FILES=(
  "job_queue.py"
  "job_queue_server.py"
)
SCRIPT_FILES=("${CORE_SCRIPT_FILES[@]}")

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

if [[ ! -d "$SKILL_SRC" ]]; then
  echo "Error: skill source not found: $SKILL_SRC" >&2
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
DEST_SKILL="$DEST_SKILLS_ROOT/$(basename "$SKILL_SRC")"
DEST_SKILL_SCRIPTS="$DEST_SKILL/scripts"
LEGACY_SCRIPTS_ROOT="$DEST_CLAUDE_ROOT/scripts"

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
  if command -v rsync >/dev/null 2>&1; then
    log_step "Sync skill tree to $DEST_SKILL (rsync --delete)"
    if [[ "$DRY_RUN" -ne 1 ]]; then
      mkdir -p "$DEST_SKILLS_ROOT"
      rsync -a --delete "$SKILL_SRC/" "$DEST_SKILL/"
    fi
  else
    log_step "Copy skill tree to $DEST_SKILL (cp -a)"
    if [[ "$DRY_RUN" -ne 1 ]]; then
      mkdir -p "$DEST_SKILLS_ROOT"
      rm -rf "$DEST_SKILL"
      cp -a "$SKILL_SRC" "$DEST_SKILL"
    fi
  fi
}

sync_runtime_scripts() {
  ensure_dir "$DEST_SKILL_SCRIPTS"

  local name
  for name in "${SCRIPT_FILES[@]}"; do
    local src="$SCRIPT_SRC_DIR/$name"
    if [[ ! -f "$src" ]]; then
      log_step "Skip missing source $src"
      continue
    fi
    local dest="$DEST_SKILL_SCRIPTS/$name"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_step "Copy $src -> $dest"
    else
      cp "$src" "$dest"
      chmod +x "$dest"
      log_step "Installed script $dest"
    fi
  done
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
  stamp="# Added by invoke-codex-from-claude install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)"

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
  SCRIPT_FILES+=("${EXPERIMENTAL_SCRIPT_FILES[@]}")
  log_step "Including experimental scripts (Phase 2/3 deferred features)"
fi

sync_skill_tree
sync_runtime_scripts

PROFILE_PATH="$(detect_profile_path)"
if [[ -n "${PROFILE_PATH:-}" ]]; then
  update_profile_block "$PROFILE_PATH" "$DEST_SKILL_SCRIPTS"
else
  log_step "No profile updated (project scope or not provided)"
fi

# Clean legacy root-level runtime scripts from older installs.
for name in "${SCRIPT_FILES[@]}"; do
  legacy="$LEGACY_SCRIPTS_ROOT/$name"
  if [[ -f "$legacy" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_step "Remove legacy script $legacy"
    else
      rm -f "$legacy"
      log_step "Removed legacy script $legacy"
    fi
  fi
done

log_step "Install completed"
