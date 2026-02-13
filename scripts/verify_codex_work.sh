#!/usr/bin/env bash
set -euo pipefail

# Verify Codex work independently
# Usage: verify_codex_work.sh --meta <meta.json> [--syntax-check] [--run-tests]

META_FILE=""
SYNTAX_CHECK=0
RUN_TESTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --meta)
      META_FILE="${2:-}"
      shift 2
      ;;
    --syntax-check)
      SYNTAX_CHECK=1
      shift
      ;;
    --run-tests)
      RUN_TESTS=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$META_FILE" ]]; then
  echo "Error: --meta required" >&2
  exit 2
fi

if [[ ! -f "$META_FILE" ]]; then
  echo "Error: Metadata file not found: $META_FILE" >&2
  exit 2
fi

echo "=== Verifying Codex Work ==="
echo ""

REPO=$(jq -r '.repo' "$META_FILE")
EXIT_CODE=$(jq -r '.exit_code' "$META_FILE")
SESSION_ID=$(jq -r '.session_id // "unknown"' "$META_FILE")
LOG_FILE=$(jq -r '.log_file' "$META_FILE")

echo "Repository: $REPO"
echo "Session ID: $SESSION_ID"
echo "Codex Exit Code: $EXIT_CODE"
echo ""

# Check 1: Did Codex complete work?
echo "Check 1: Task completion..."
if [[ -f "$LOG_FILE" ]] && grep -q "tokens used" "$LOG_FILE" 2>/dev/null; then
  echo "  ✓ Codex completed work (tokens used)"
else
  echo "  ✗ No evidence of completion"
  exit 1
fi

# Check 2: Look for real errors
echo "Check 2: Real errors..."
ERROR_COUNT=0
if [[ -f "$LOG_FILE" ]]; then
  if grep -qE "error:|fatal:|Exception:" "$LOG_FILE" 2>/dev/null; then
    echo "  ✗ Errors found in log"
    grep -E "error:|fatal:|Exception:" "$LOG_FILE" | head -5
    ERROR_COUNT=$((ERROR_COUNT + 1))
  else
    echo "  ✓ No critical errors found"
  fi
fi

# Check 3: Shell errors (environmental, not real failures)
echo "Check 3: Environmental issues..."
if [[ -f "$LOG_FILE" ]] && grep -qE "\[stderr\].*syntax error|\[stderr\].*unexpected" "$LOG_FILE" 2>/dev/null; then
  echo "  ⚠️  Shell errors found (likely environmental)"
else
  echo "  ✓ No shell errors"
fi

# Check 4: Syntax check modified files
if [[ "$SYNTAX_CHECK" == "1" ]]; then
  echo "Check 4: Syntax validation..."
  cd "$REPO"
  SYNTAX_ERRORS=0

  # Check bash scripts
  for file in $(( git diff --name-only HEAD 2>/dev/null; git diff --name-only HEAD~1..HEAD 2>/dev/null ) | sort -u | grep '\.sh$' || true); do
    if [[ -f "$file" ]]; then
      if bash -n "$file" 2>/dev/null; then
        echo "  ✓ $file - valid syntax"
      else
        echo "  ✗ $file - syntax error"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
      fi
    fi
  done

  # Check Python files
  for file in $(( git diff --name-only HEAD 2>/dev/null; git diff --name-only HEAD~1..HEAD 2>/dev/null ) | sort -u | grep '\.py$' || true); do
    if [[ -f "$file" ]]; then
      if python3 -m py_compile "$file" 2>/dev/null; then
        echo "  ✓ $file - valid syntax"
      else
        echo "  ✗ $file - syntax error"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
      fi
    fi
  done

  if [[ "$SYNTAX_ERRORS" -gt 0 ]]; then
    ERROR_COUNT=$((ERROR_COUNT + SYNTAX_ERRORS))
  fi
fi

# Check 5: Run tests
if [[ "$RUN_TESTS" == "1" ]]; then
  echo "Check 5: Running tests..."
  cd "$REPO"

  if [[ -f "tests/test_runner_and_parser.sh" ]]; then
    if bash tests/test_runner_and_parser.sh; then
      echo "  ✓ Tests passed"
    else
      echo "  ✗ Tests failed"
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
  else
    echo "  - No tests found"
  fi
fi

echo ""
echo "=== Summary ==="
if [[ "$ERROR_COUNT" -eq 0 ]]; then
  echo "✓ All checks passed"
  exit 0
else
  echo "✗ $ERROR_COUNT check(s) failed"
  exit 1
fi
