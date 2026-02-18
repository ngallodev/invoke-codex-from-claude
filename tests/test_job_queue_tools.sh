#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUEUE="$ROOT_DIR/codex-job/scripts/job_queue.py"
SERVER="$ROOT_DIR/codex-job/scripts/job_queue_server.py"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[PASS] $*"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$expected" == "$actual" ]] || fail "$label mismatch. expected='$expected' actual='$actual'"
}

run_test_queue_lifecycle() {
  local tmp db job_id json_out
  tmp="$(mktemp -d)"
  db="$tmp/job_queue.sqlite3"

  job_id="$(python3 "$QUEUE" --db "$db" enqueue \
    --task "phase3 n1 queue test" \
    --status running \
    --repo "$tmp/repo" \
    --run-id "run-123" \
    --session-id "sess-a" \
    --mode "codex" \
    --tier "medium" \
    --cache "miss" \
    --result-path "$tmp/result.txt" \
    --log-path "$tmp/run.log" \
    --meta-path "$tmp/meta.json" \
    --summary-path "$tmp/summary.json")"

  [[ "$job_id" =~ ^[0-9]+$ ]] || fail "enqueue did not return numeric job id: $job_id"

  python3 "$QUEUE" --db "$db" update \
    --id "$job_id" \
    --status completed \
    --exit-code 0 \
    --session-id "sess-b" \
    --cache "hit" \
    --result-path "$tmp/result-final.txt" \
    --log-path "$tmp/run-final.log" \
    --meta-path "$tmp/meta-final.json" \
    --summary-path "$tmp/summary-final.json"

  json_out="$(python3 "$QUEUE" --db "$db" list --limit 10)"

  JSON_OUT="$json_out" JOB_ID="$job_id" TMP_DIR="$tmp" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["JSON_OUT"])
jobs = payload.get("jobs")
if not isinstance(jobs, list) or len(jobs) != 1:
    raise SystemExit(f"expected exactly 1 job, got: {jobs!r}")

job = jobs[0]
required = {
    "id", "task", "status", "repo", "run_id", "session_id", "mode", "tier",
    "cache_status", "created_at", "started_at", "completed_at", "result_path",
    "log_path", "meta_path", "summary_path", "error", "elapsed_seconds"
}
missing = sorted(required - set(job))
if missing:
    raise SystemExit(f"missing expected keys: {missing}")

expected = {
    "id": int(os.environ["JOB_ID"]),
    "task": "phase3 n1 queue test",
    "status": "completed",
    "run_id": "run-123",
    "session_id": "sess-b",
    "mode": "codex",
    "tier": "medium",
    "cache_status": "hit",
    "repo": os.path.join(os.environ["TMP_DIR"], "repo"),
    "result_path": os.path.join(os.environ["TMP_DIR"], "result-final.txt"),
    "log_path": os.path.join(os.environ["TMP_DIR"], "run-final.log"),
    "meta_path": os.path.join(os.environ["TMP_DIR"], "meta-final.json"),
    "summary_path": os.path.join(os.environ["TMP_DIR"], "summary-final.json"),
}
for key, value in expected.items():
    if job.get(key) != value:
        raise SystemExit(f"{key} mismatch. expected={value!r} actual={job.get(key)!r}")

if not job.get("created_at") or not job.get("started_at") or not job.get("completed_at"):
    raise SystemExit("expected created_at/started_at/completed_at to be populated")
if job.get("error") != "":
    raise SystemExit(f"expected empty error for exit-code 0, got {job.get('error')!r}")
PY

  rm -rf "$tmp"
  pass "job_queue enqueue/update/list lifecycle"
}

run_test_server_help_and_fallback() {
  local help_text
  help_text="$(python3 "$SERVER" --help)"

  [[ "$help_text" == *"Serve the job queue dashboard + API."* ]] || fail "missing expected help description"
  [[ "$help_text" == *"--dashboard"* ]] || fail "missing --dashboard in help output"

  python3 - "$SERVER" <<'PY'
import importlib.util
import pathlib
import sys

server_path = pathlib.Path(sys.argv[1]).resolve()
sys.path.insert(0, str(server_path.parent))

spec = importlib.util.spec_from_file_location("job_queue_server_under_test", server_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

missing_path = "/this/path/should/not/exist/dashboard.html"
if module.discover_dashboard_path(missing_path) is not None:
    raise SystemExit("discover_dashboard_path should return None for missing explicit path")

fallback_html = module.load_dashboard_html(pathlib.Path(missing_path))
if "Codex Job Queue" not in fallback_html:
    raise SystemExit("fallback html missing title text")
if "<!doctype html>" not in fallback_html.lower():
    raise SystemExit("fallback html missing doctype")
PY

  pass "job_queue_server --help and dashboard fallback smoke"
}

run_test_queue_lifecycle
run_test_server_help_and_fallback
pass "all job queue tool tests"
