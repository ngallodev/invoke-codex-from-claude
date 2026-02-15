#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$ROOT_DIR/codex-job/scripts/run_codex_task.sh"

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
  local file="$1"
  local key="$2"
  awk -F= -v k="$key" '$1==k {print substr($0, index($0, "=")+1)}' "$file" | tail -n1
}

make_fake_codex() {
  local out="$1"
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

CWD="${3:-}"
TASK="${4:-}"
shift 4

MODEL="default"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

echo "fake_codex_cwd=$CWD"
echo "fake_codex_task=$TASK"
echo "fake_codex_model=$MODEL"

if [[ "$MODEL" == "gpt-5-mini" ]]; then
  echo "prompt_tokens: 111"
  echo "completion_tokens: 22"
  echo "estimated_cost_usd: 0.01"
else
  echo "prompt_tokens: 1,234"
  echo "completion_tokens: 56"
  echo "estimated_cost_usd: 0.12"
fi
FAKE
  chmod +x "$out"
}

run_test_basic() {
  local tmp
  tmp="$(mktemp -d)"

  local fake_codex="$tmp/fake_codex.sh"
  local repo="$tmp/repo"
  local log_dir="$tmp/runs"
  local summary="$tmp/basic.summary.json"
  local output="$tmp/basic.output.txt"

  mkdir -p "$repo" "$log_dir"
  make_fake_codex "$fake_codex"

  "$RUNNER" \
    --repo "$repo" \
    --task "Basic task" \
    --codex-bin "$fake_codex" \
    --log-dir "$log_dir" \
    --json-out "$summary" \
    -vvv \
    > "$output"

  assert_file_exists "$summary"

  local summary_file
  summary_file="$(extract_kv "$output" summary_file)"
  assert_eq "$summary" "$summary_file" "summary_file"

  local exit_code
  exit_code="$(extract_kv "$output" codex_exit_code)"
  assert_eq "0" "$exit_code" "codex_exit_code"

  local log_file
  log_file="$(extract_kv "$output" log_file)"
  assert_file_exists "$log_file"

  local cd_line
  cd_line="$(rg -n '^fake_codex_cwd=' "$log_file" | tail -n1 | cut -d: -f2-)"
  assert_eq "fake_codex_cwd=$repo" "$cd_line" "exec --cd passthrough"

  rg -n '^script_invocation=' "$log_file" >/dev/null || fail "missing script_invocation in log"
  rg -n '^codex_command=' "$log_file" >/dev/null || fail "missing codex_command in log"
  rg -n 'exec --cd' "$log_file" >/dev/null || fail "missing exec --cd in diagnostic command"

  assert_eq "true" "$(json_get "$summary" success)" "success"
  assert_eq "0" "$(json_get "$summary" exit_code)" "exit_code"
  assert_eq "1234" "$(json_get "$summary" token_usage.input_tokens)" "input_tokens"
  assert_eq "56" "$(json_get "$summary" token_usage.output_tokens)" "output_tokens"
  assert_eq "1290" "$(json_get "$summary" token_usage.total_tokens)" "total_tokens"
  assert_eq "0.12" "$(json_get "$summary" cost.usd)" "cost.usd"

  rm -rf "$tmp"
  pass "basic functionality + parsed summary"
}

run_test_advanced_options() {
  local tmp
  tmp="$(mktemp -d)"

  local fake_codex="$tmp/fake_codex.sh"
  local repo="$tmp/repo"
  local log_dir="$tmp/runs"
  local summary="$tmp/advanced.summary.json"
  local output="$tmp/advanced.output.txt"

  mkdir -p "$repo" "$log_dir"
  make_fake_codex "$fake_codex"

  "$RUNNER" \
    --repo "$repo" \
    --task "Advanced task" \
    --codex-bin "$fake_codex" \
    --log-dir "$log_dir" \
    --json-out "$summary" \
    -vvv \
    -- --model gpt-5-mini --effort low \
    > "$output"

  assert_file_exists "$summary"

  local log_file
  log_file="$(extract_kv "$output" log_file)"
  assert_file_exists "$log_file"

  local model_line
  model_line="$(rg -n '^fake_codex_model=' "$log_file" | tail -n1 | cut -d: -f2-)"
  assert_eq "fake_codex_model=gpt-5-mini" "$model_line" "model passthrough"
  rg -n '^codex_command=' "$log_file" >/dev/null || fail "missing codex_command in advanced log"
  rg -n 'gpt-5-mini' "$log_file" >/dev/null || fail "missing mini model in advanced diagnostics"

  assert_eq "111" "$(json_get "$summary" token_usage.input_tokens)" "input_tokens mini"
  assert_eq "22" "$(json_get "$summary" token_usage.output_tokens)" "output_tokens mini"
  assert_eq "133" "$(json_get "$summary" token_usage.total_tokens)" "total_tokens mini"
  assert_eq "0.01" "$(json_get "$summary" cost.usd)" "cost.usd mini"

  rm -rf "$tmp"
  pass "advanced options (--model gpt-5-mini) + parsed summary"
}

run_test_tokens_used_line() {
  local tmp
  tmp="$(mktemp -d)"

  local log="$tmp/tokens-used.log"
  local meta="$tmp/tokens-used.meta.json"
  local summary="$tmp/tokens-used.summary.json"

  cat <<'EOF' > "$log"
tokens used
7,200
EOF

  cat <<'EOF' > "$meta"
{
  "run_id": "tokens-used-test",
  "repo": ".",
  "task": "Tokens used pattern",
  "started_at": "2026-01-01T00:00:00Z",
  "ended_at": "2026-01-01T00:00:01Z",
  "elapsed_seconds": 1,
  "exit_code": 0
}
EOF

  python3 "$ROOT_DIR/codex-job/scripts/parse_codex_run.py" --log "$log" --meta "$meta" > "$summary"

  assert_eq "7200" "$(json_get "$summary" token_usage.total_tokens)" "tokens used total"
  assert_eq "null" "$(json_get "$summary" token_usage.input_tokens)" "input tokens null"
  assert_eq "null" "$(json_get "$summary" token_usage.output_tokens)" "output tokens null"

  rm -rf "$tmp"
  pass "tokens used format parsed as total"
}

main() {
  run_test_basic
  run_test_advanced_options
  run_test_tokens_used_line
  echo "All tests passed."
}

main "$@"
