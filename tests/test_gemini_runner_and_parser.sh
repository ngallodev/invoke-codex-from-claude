#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$ROOT_DIR/codex-job/scripts/run_gemini_task.sh"

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
keypath = sys.argv[2].split('.')
with open(file_path, 'r', encoding='utf-8') as f:
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
  local text="$1"
  local key="$2"
  awk -F= -v k="$key" '$1==k {print substr($0, index($0, "=")+1)}' <<< "$text" | tail -n1
}

run_test_basic() {
  local tmp
  tmp="$(mktemp -d)"

  local fake_gemini="$ROOT_DIR/tests/fake_gemini.sh"
  chmod +x "$fake_gemini"
  
  local repo="$tmp/repo"
  local log_dir="$tmp/runs"
  local summary="$tmp/basic.summary.json"
  local output

  mkdir -p "$repo" "$log_dir"

  output="$("$RUNNER" \
    --repo "$repo" \
    --task "Basic gemini task" \
    --gemini-bin "$fake_gemini" \
    --log-dir "$log_dir" \
    --json-out "$summary" \
    -vvv)"

  assert_file_exists "$summary"

  local summary_file
  summary_file="$(extract_kv "$output" summary_file)"
  assert_eq "$summary" "$summary_file" "summary_file"

  local exit_code
  exit_code="$(extract_kv "$output" gemini_exit_code)"
  assert_eq "0" "$exit_code" "gemini_exit_code"

  local log_file
  log_file="$(extract_kv "$output" log_file)"
  assert_file_exists "$log_file"

  assert_eq "true" "$(json_get "$summary" success)" "success"
  assert_eq "1000" "$(json_get "$summary" token_usage.input_tokens)" "input_tokens"
  assert_eq "500" "$(json_get "$summary" token_usage.output_tokens)" "output_tokens"
  assert_eq "1500" "$(json_get "$summary" token_usage.total_tokens)" "total_tokens"
  assert_eq "0.05" "$(json_get "$summary" cost.usd)" "cost.usd"
  assert_eq "12345678-1234-1234-1234-1234567890ab" "$(json_get "$summary" session_id)" "session_id"

  rm -rf "$tmp"
  pass "basic gemini functionality + parsed summary"
}

run_test_resume() {
  local tmp
  tmp="$(mktemp -d)"

  local fake_gemini="$ROOT_DIR/tests/fake_gemini.sh"
  
  local repo="$tmp/repo"
  local log_dir="$tmp/runs"
  local summary="$tmp/resume.summary.json"
  local output

  mkdir -p "$repo" "$log_dir"

  output="$("$RUNNER" \
    --repo "$repo" \
    --resume "some-session-id" \
    --task "Resume task" \
    --gemini-bin "$fake_gemini" \
    --log-dir "$log_dir" \
    --json-out "$summary" \
    -vvv)"

  local log_file
  log_file="$(extract_kv "$output" log_file)"
  
  rg -q "fake_gemini_resume=some-session-id" "$log_file" || fail "resume ID not passed to gemini"
  rg -q "fake_gemini_prompt=Resume task" "$log_file" || fail "prompt not passed to gemini on resume"

  rm -rf "$tmp"
  pass "gemini resume functionality"
}

main() {
  run_test_basic
  run_test_resume
  echo "Gemini tests passed."
}

main "$@"
