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
  uninstall.sh --scope <project|user|global> [options]

Options:
  --scope <project|user|global>  Install scope to remove (required)
  --claude-home <path>           Override target Claude home (~/.claude)
  --profile <path>               Shell profile to clean (default: auto-detect)
  --no-profile                   Skip PATH/profile cleanup
  --dry-run                      Show actions without changing files
  -h, --help                     Show this help text

Examples:
  uninstall.sh --scope user
  uninstall.sh --scope user --dry-run
  uninstall.sh --scope project --no-profile
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="codex-job"
SCRIPT_FILES=(
  "codex_task.py"
  "invoke_codex_with_review.sh"
  "invoke_gemini_with_review.sh"
  "run_codex_task.sh"
  "run_gemini_task.sh"
  "parse_codex_run.py"
  "parse_gemini_run.py"
  "job_queue.py"
  "job_queue_server.py"
  "notify_claude_hook.sh"
  "notify_terminal.sh"
  "verify_codex_work.sh"
  "write_delegation_metric.py"
)

SCOPE=""
DRY_RUN=0
CLAUDE_HOME_OVERRIDE=""
PROFILE_OVERRIDE=""
NO_PROFILE=0

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
  echo "Error: python3 is required for uninstallation." >&2
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
LEGACY_SCRIPTS_ROOT="$DEST_CLAUDE_ROOT/scripts"

log_step() {
  local msg="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $msg"
  else
    echo "$msg"
  fi
}

remove_path() {
  local target="$1"
  if [[ -e "$target" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_step "Remove $target"
    else
      rm -rf "$target"
      log_step "Removed $target"
    fi
  else
    log_step "Already absent: $target"
  fi
}

clean_profile_block() {
  local profile_path="$1"

  if [[ "$NO_PROFILE" -eq 1 ]]; then
    log_step "Skipping profile cleanup (disabled)"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_step "Remove PATH block from $profile_path if present"
    return
  fi

  python3 - "$profile_path" "$PROFILE_START" "$PROFILE_END" <<'PY'
import sys
from pathlib import Path

profile = Path(sys.argv[1])
start, end = sys.argv[2:4]

if not profile.exists():
    sys.exit(0)

lines = profile.read_text().splitlines()
out = []
skipping = False
for line in lines:
    if line.strip() == start:
        skipping = True
        continue
    if skipping and line.strip() == end:
        skipping = False
        continue
    if not skipping:
        out.append(line)

# Trim trailing blank lines
while out and not out[-1].strip():
    out.pop()

profile.write_text("\n".join(out) + ("\n" if out else ""))
PY
  log_step "Cleaned PATH block in $profile_path"
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

remove_path "$DEST_SKILL"

# Legacy script cleanup (pre-skill layout)
if [[ -d "$LEGACY_SCRIPTS_ROOT" ]]; then
  for name in "${SCRIPT_FILES[@]}"; do
    legacy="$LEGACY_SCRIPTS_ROOT/$name"
    if [[ -f "$legacy" ]]; then
      remove_path "$legacy"
    fi
  done
fi

PROFILE_PATH="$(detect_profile_path)"
if [[ -n "${PROFILE_PATH:-}" ]]; then
  clean_profile_block "$PROFILE_PATH"
else
  log_step "No profile cleaned (project scope or not provided)"
fi

log_step "Uninstall completed"
