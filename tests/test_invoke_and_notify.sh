#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$ROOT_DIR/scripts/run_codex_task.sh"
INVOKER="$ROOT_DIR/scripts/invoke_codex_with_review.sh"
export CODEX_API_KEY="test-key"
export WEBHOOK_SECRET="test-secret"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[PASS] $*"
}

assert_file_exists() {
  local path="$1"
  [[ -f "$path" ]] || fail "Expected file to exist: $path"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$expected" == "$actual" ]] || fail "$label mismatch. expected='$expected' actual='$actual'"
}

json_get() {
  local file="$1"
  local keypath="$2"
  python3 - "$file" "$keypath" <<'PY'
import json
import sys

file_path = sys.argv[1]
keypath = sys.argv[2].split(".")
with open(file_path, "r", encoding="utf-8") as f:
    data = json.load(f)

value = data
for key in keypath:
    if key:
        value = value[key]

if isinstance(value, bool):
    print(str(value).lower())
elif value is None:
    print("null")
else:
    print(value)
PY
}

extract_kv() {
  local file="$1"
  local key="$2"
  awk -F= -v k="$key" '$1==k {print substr($0, index($0, "=")+1)}' "$file" | tail -n1
}

make_fake_codex_sequence() {
  local out="$1"
  local mode_file="$2"
  cat > "$out" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "exec" ]]; then
  echo "expected first arg exec" >&2
  exit 64
fi
if [[ "${2:-}" != "--cd" ]]; then
  echo "expected second arg --cd" >&2
  exit 64
fi

shift 3
if [[ "${1:-}" == "resume" ]]; then
  MODE="resume"
else
  MODE="new"
fi

COUNTER_FILE="${FAKE_COUNTER_FILE:?missing counter file}"
COUNT=0
if [[ -f "$COUNTER_FILE" ]]; then
  COUNT="$(cat "$COUNTER_FILE")"
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

echo "session id: 11111111-2222-3333-4444-555555555555"

case "${FAKE_MODE:-success}" in
  success)
    echo "tokens used: 42"
    exit 0
    ;;
  env_fail)
    echo "tokens used: 12"
    echo "[stderr] syntax error near unexpected token then"
    exit 2
    ;;
  real_then_review_success)
    if [[ "$MODE" == "new" ]]; then
      echo "tokens used: 20"
      echo "error: real failure"
      exit 2
    fi
    echo "tokens used: 30"
    exit 0
    ;;
  *)
    echo "unknown fake mode" >&2
    exit 65
    ;;
esac
FAKE
  chmod +x "$out"
  : > "$mode_file"
}

run_test_quote_safe_metadata_and_notify_events() {
  local tmp
  tmp="$(mktemp -d)"

  local fake_codex="$tmp/fake_codex.sh"
  local fake_counter="$tmp/fake_counter.txt"
  local repo="$tmp/repo"
  local summary="$tmp/summary.json"
  local out="$tmp/run.out"
  local events="$tmp/events.jsonl"
  mkdir -p "$repo"

  make_fake_codex_sequence "$fake_codex" "$fake_counter"

  FAKE_MODE=success FAKE_COUNTER_FILE="$fake_counter" \
    "$RUNNER" \
      --repo "$repo" \
      --task 'Fix "quoted" task safely' \
      --codex-bin "$fake_codex" \
      --json-out "$summary" \
      --notify-cmd "cat >> $events" \
      > "$out"

  assert_file_exists "$summary"
  assert_file_exists "$events"
  assert_eq 'Fix "quoted" task safely' "$(json_get "$summary" task)" "summary.task"

  rg -n '"event": "run_started"' "$events" >/dev/null || fail "missing run_started event"
  rg -n '"event": "run_completed"' "$events" >/dev/null || fail "missing run_completed event"

  rm -rf "$tmp"
  pass "quote-safe metadata + run events"
}

run_test_invoke_environmental_failure_treated_success() {
  local tmp
  tmp="$(mktemp -d)"

  local fake_codex="$tmp/fake_codex.sh"
  local fake_counter="$tmp/fake_counter.txt"
  local repo="$tmp/repo"
  local out="$tmp/invoke.out"
  mkdir -p "$repo"

  make_fake_codex_sequence "$fake_codex" "$fake_counter"

  set +e
  FAKE_MODE=env_fail FAKE_COUNTER_FILE="$fake_counter" \
    "$INVOKER" --repo "$repo" --task "do work" --codex-bin "$fake_codex" > "$out" 2>&1
  local code=$?
  set -e

  assert_eq "0" "$code" "invoke exit code on environmental failure"
  rg -n "Treating as success" "$out" >/dev/null || fail "expected environmental success message"

  rm -rf "$tmp"
  pass "invoke treats environmental failure as success"
}

run_test_invoke_real_failure_triggers_review_and_events() {
  local tmp
  tmp="$(mktemp -d)"

  local fake_codex="$tmp/fake_codex.sh"
  local fake_counter="$tmp/fake_counter.txt"
  local repo="$tmp/repo"
  local out="$tmp/invoke.out"
  local events="$tmp/events.jsonl"
  mkdir -p "$repo"

  make_fake_codex_sequence "$fake_codex" "$fake_counter"

  set +e
  FAKE_MODE=real_then_review_success FAKE_COUNTER_FILE="$fake_counter" \
    "$INVOKER" \
      --repo "$repo" \
      --task "do work" \
      --codex-bin "$fake_codex" \
      --event-stream "$events" \
      > "$out" 2>&1
  local code=$?
  set -e

  assert_eq "0" "$code" "invoke exit code after successful review"
  assert_file_exists "$events"
  assert_eq "2" "$(cat "$fake_counter")" "codex invocation count (initial + review)"

  rg -n '"event": "review_started"' "$events" >/dev/null || fail "missing review_started event"
  rg -n '"event": "review_completed"' "$events" >/dev/null || fail "missing review_completed event"
  rg -n 'Review exit code: 0' "$out" >/dev/null || fail "missing review success output"

  rm -rf "$tmp"
  pass "invoke triggers review + emits wrapper events"
}

run_test_invoke_summary_defaults() {
  local tmp
  tmp="$(mktemp -d)"

  local fake_codex="$tmp/fake_codex.sh"
  local fake_counter="$tmp/fake_counter.txt"
  local repo="$tmp/repo"
  local out_default="$tmp/invoke-default.out"
  local out_no="$tmp/invoke-no-summary.out"
  mkdir -p "$repo"

  make_fake_codex_sequence "$fake_codex" "$fake_counter"

  FAKE_MODE=success FAKE_COUNTER_FILE="$fake_counter" \
    "$INVOKER" --repo "$repo" --task "default summary" --codex-bin "$fake_codex" > "$out_default" 2>&1

  rg -n '^summary_line=' "$out_default" >/dev/null || fail "expected summary_line in default invoke output"

  : > "$fake_counter"
  FAKE_MODE=success FAKE_COUNTER_FILE="$fake_counter" \
    "$INVOKER" --repo "$repo" --task "no summary" --codex-bin "$fake_codex" --no-summarize > "$out_no" 2>&1

  if rg -n '^summary_line=' "$out_no" >/dev/null; then
    fail "did not expect summary_line when --no-summarize is set"
  fi

  rm -rf "$tmp"
  pass "invoke summarize default + no-summarize override"
}

main() {
  run_test_quote_safe_metadata_and_notify_events
  run_test_invoke_environmental_failure_treated_success
  run_test_invoke_real_failure_triggers_review_and_events
  run_test_invoke_summary_defaults
  echo "All tests passed."
}

main "$@"
