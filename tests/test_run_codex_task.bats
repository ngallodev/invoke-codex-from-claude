#!/usr/bin/env bats

if [[ -f "${BATS_TEST_DIRNAME}/test_helper.bash" ]]; then
  load 'test_helper.bash'
fi

setup() {
  ROOT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  RUNNER="$ROOT_DIR/scripts/run_codex_task.sh"
  export CODEX_API_KEY="test-key"
  export WEBHOOK_SECRET="test-secret"
}

json_get() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import json
import sys

path = sys.argv[1]
keypath = sys.argv[2].split(".")
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

value = data
for part in keypath:
    if part:
        value = value[part]

if isinstance(value, bool):
    print(str(value).lower())
elif value is None:
    print("null")
else:
    print(value)
PY
}

make_fake_codex() {
  local out="$1"
  cat > "$out" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "exec" || "${2:-}" != "--cd" ]]; then
  echo "expected codex exec --cd" >&2
  exit 64
fi

REPO_ARG="${3:-}"
TASK_ARG="${4:-}"
shift 4

MODE="${FAKE_MODE:-success}"

if [[ -n "${COUNTER_FILE:-}" ]]; then
  echo x >> "$COUNTER_FILE"
fi

case "$MODE" in
  long)
    echo "session id: 00000000-0000-0000-0000-000000000001"
    sleep "${FAKE_SLEEP:-2}"
    echo "tokens used: 10"
    exit 0
    ;;
  network_fail)
    echo "session id: 00000000-0000-0000-0000-000000000002"
    echo "network timeout contacting upstream" >&2
    exit 7
    ;;
  echo_task)
    echo "session id: 00000000-0000-0000-0000-000000000003"
    echo "received task: ${TASK_ARG}"
    echo "prompt_tokens: 12"
    echo "completion_tokens: 3"
    exit 0
    ;;
  *)
    echo "session id: 00000000-0000-0000-0000-000000000000"
    echo "prompt_tokens: 5"
    echo "completion_tokens: 2"
    exit 0
    ;;
esac
FAKE
  chmod +x "$out"
}

@test "long-running task records elapsed time in metadata" {
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  log_dir="$tmp/runs"
  summary="$tmp/summary.json"
  fake_codex="$tmp/fake_codex.sh"
  mkdir -p "$repo" "$log_dir"

  make_fake_codex "$fake_codex"

  FAKE_MODE=long FAKE_SLEEP=2 \
    run "$RUNNER" \
      --repo "$repo" \
      --task "Slow burn" \
      --codex-bin "$fake_codex" \
      --log-dir "$log_dir" \
      --json-out "$summary"

  [ "$status" -eq 0 ]

  meta_file="$(echo "$output" | awk -F= '/^meta_file=/{print $2}' | tail -1)"
  [ -f "$meta_file" ]

  elapsed="$(json_get "$meta_file" elapsed_seconds)"
  [ "$elapsed" -ge 2 ]

  run_id="$(json_get "$meta_file" run_id)"
  [ -n "$run_id" ]

  rm -rf "$tmp"
}

@test "task names with special characters are preserved in outputs" {
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  summary="$tmp/special.summary.json"
  fake_codex="$tmp/fake_codex.sh"
  mkdir -p "$repo"

  make_fake_codex "$fake_codex"

  special_task='Handle $PATH & pipes | "quotes" + backticks `echo`'

  FAKE_MODE=echo_task \
    run "$RUNNER" \
      --repo "$repo" \
      --task "$special_task" \
      --codex-bin "$fake_codex" \
      --json-out "$summary"

  [ "$status" -eq 0 ]
  [ -f "$summary" ]

  task_meta="$(json_get "$summary" task)"
  [ "$task_meta" = "$special_task" ]

  meta_file="$(echo "$output" | awk -F= '/^meta_file=/{print $2}' | tail -1)"
  [ -f "$meta_file" ]
  task_meta_file="$(json_get "$meta_file" task)"
  [ "$task_meta_file" = "$special_task" ]

  rm -rf "$tmp"
}

@test "network failure emits failure event and notifies listeners" {
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  events="$tmp/events.jsonl"
  notify_sink="$tmp/notify.jsonl"
  fake_codex="$tmp/fake_codex.sh"
  mkdir -p "$repo"

  make_fake_codex "$fake_codex"

  FAKE_MODE=network_fail \
    run "$RUNNER" \
      --repo "$repo" \
      --task "Network sensitive task" \
      --codex-bin "$fake_codex" \
      --event-stream "$events" \
      --notify-cmd "cat >> $notify_sink"

  [ "$status" -eq 7 ]
  [ -f "$events" ]
  [ -f "$notify_sink" ]

  line_count="$(python3 - <<'PY' "$events"
from pathlib import Path
from sys import argv
text = Path(argv[1]).read_text().strip()
print(0 if not text else len(text.splitlines()))
PY
)"
  [ "$line_count" -ge 2 ]

  last_status="$(python3 - <<'PY' "$events"
from pathlib import Path
import json
from sys import argv
lines = [line for line in Path(argv[1]).read_text().splitlines() if line.strip()]
last = json.loads(lines[-1])
print(f"{last.get('status')}|{last.get('exit_code')}")
PY
)"

  [ "$last_status" = "failure|7" ]

  notify_lines="$(python3 - <<'PY' "$notify_sink"
from pathlib import Path
from sys import argv
text = Path(argv[1]).read_text().strip()
print(0 if not text else len(text.splitlines()))
PY
)"
  [ "$notify_lines" -ge 2 ]

  rm -rf "$tmp"
}

@test "--summarize emits summary_line on cache-hit path" {
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  log_dir="$tmp/runs"
  fake_codex="$tmp/fake_codex.sh"
  counter="$tmp/counter.txt"
  out_first="$tmp/first.out"
  out_second="$tmp/second.out"
  mkdir -p "$repo" "$log_dir"

  make_fake_codex "$fake_codex"

  COUNTER_FILE="$counter" XDG_CACHE_HOME="$tmp/cache-home" \
    "$RUNNER" \
      --repo "$repo" \
      --task "Cache summarize task" \
      --codex-bin "$fake_codex" \
      --log-dir "$log_dir" \
      > "$out_first"

  COUNTER_FILE="$counter" XDG_CACHE_HOME="$tmp/cache-home" \
    run "$RUNNER" \
      --repo "$repo" \
      --task "Cache summarize task" \
      --codex-bin "$fake_codex" \
      --log-dir "$log_dir" \
      --summarize

  [ "$status" -eq 0 ]
  [[ "$output" == *$'cache_status=hit'* ]]

  run_count="$(wc -l < "$counter" | tr -d ' ')"
  [ "$run_count" -eq 1 ]

  summary_line="$(echo "$output" | awk -F= '/^summary_line=/{print substr($0, index($0, "=")+1)}' | tail -1)"
  [ -n "$summary_line" ]
  [[ "$summary_line" == OK* ]]
  [[ "$summary_line" == *'task="Cache summarize task"'* ]]

  meta_file="$(echo "$output" | awk -F= '/^meta_file=/{print $2}' | tail -1)"
  [ -f "$meta_file" ]
  [ "$(json_get "$meta_file" one_line_summary)" = "$summary_line" ]

  rm -rf "$tmp"
}

@test "--doctor passes when requirements are met" {
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  log_dir="$tmp/runs"
  fake_codex="$tmp/fake_codex.sh"
  mkdir -p "$repo" "$log_dir"

  make_fake_codex "$fake_codex"

  CODEX_API_KEY=abc123 \
    run "$RUNNER" \
      --repo "$repo" \
      --doctor \
      --codex-bin "$fake_codex" \
      --log-dir "$log_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Doctor result: PASS"* ]]

  rm -rf "$tmp"
}

@test "--doctor fails without CODEX_API_KEY" {
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  fake_codex="$tmp/fake_codex.sh"
  mkdir -p "$repo"

  make_fake_codex "$fake_codex"

  unset CODEX_API_KEY
  run "$RUNNER" \
    --repo "$repo" \
    --doctor \
    --codex-bin "$fake_codex"

  [ "$status" -ne 0 ]
  [[ "$output" == *"env:CODEX_API_KEY"* ]]

  rm -rf "$tmp"
}
