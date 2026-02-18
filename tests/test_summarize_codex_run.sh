#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUMMARIZER="$ROOT_DIR/codex-job/scripts/summarize_codex_run.py"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[PASS] $*"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$label missing '$needle' in: $haystack"
}

run_test_success_summary() {
  local tmp
  tmp="$(mktemp -d)"
  local summary="$tmp/success.summary.json"

  cat > "$summary" <<'JSON'
{"id":"run-success","sid":"sess-success","task":"Fix tests","time":12,"exit":0,"ok":true,"tok":{"tot":150},"cost":{"usd":0.05}}
JSON

  local output
  output="$(python3 "$SUMMARIZER" --summary "$summary")"

  assert_contains "$output" "OK" "status"
  assert_contains "$output" "id=run-success" "run id"
  assert_contains "$output" "exit=0" "exit code"
  assert_contains "$output" "time=12s" "elapsed"
  assert_contains "$output" "tok=150" "tokens"
  assert_contains "$output" "cost=0.05" "cost"
  assert_contains "$output" "sid=sess-success" "session id"

  rm -rf "$tmp"
  pass "success summary"
}

run_test_failure_summary_legacy() {
  local tmp
  tmp="$(mktemp -d)"
  local summary="$tmp/failure.summary.json"

  cat > "$summary" <<'JSON'
{"legacy":{"run_id":"run-fail","session_id":"sess-fail","task":"Broken build","elapsed_seconds":7,"exit_code":9,"success":false,"token_usage":{"total_tokens":44},"cost":{"usd":1.2}}}
JSON

  local output
  output="$(python3 "$SUMMARIZER" --summary "$summary")"

  assert_contains "$output" "FAIL" "status"
  assert_contains "$output" "id=run-fail" "run id"
  assert_contains "$output" "exit=9" "exit code"
  assert_contains "$output" "time=7s" "elapsed"
  assert_contains "$output" "tok=44" "tokens"
  assert_contains "$output" "cost=1.2" "cost"
  assert_contains "$output" "sid=sess-fail" "session id"

  rm -rf "$tmp"
  pass "failure summary from legacy"
}

run_test_missing_file() {
  local tmp
  tmp="$(mktemp -d)"
  local missing="$tmp/does-not-exist.summary.json"

  set +e
  local output
  output="$(python3 "$SUMMARIZER" --summary "$missing" 2>&1)"
  local status=$?
  set -e

  [[ $status -ne 0 ]] || fail "missing file should fail"
  assert_contains "$output" "summary file not found" "missing-file message"

  rm -rf "$tmp"
  pass "missing file behavior"
}

run_test_success_summary
run_test_failure_summary_legacy
run_test_missing_file

echo "All summarize_codex_run tests passed."
