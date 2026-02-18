#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
event_schema_path = root / "schemas" / "event.v1.json"
state_machine_path = root / "schemas" / "run-state-machine.v1.json"

event_schema = json.loads(event_schema_path.read_text(encoding="utf-8"))
state_machine = json.loads(state_machine_path.read_text(encoding="utf-8"))

required_event_keys = [
    "schema_version",
    "event_id",
    "event_type",
    "occurred_at",
    "correlation_id",
    "task_id",
    "run_id",
    "agent_id",
    "actor_type",
    "actor_id",
    "payload",
]
if event_schema.get("required") != required_event_keys:
    raise SystemExit("event.v1.json required keys do not match contract")

states = state_machine.get("states", [])
if state_machine.get("initial_state") != "queued":
    raise SystemExit("run-state-machine.v1 initial_state must be queued")
if not {"completed", "failed", "canceled"}.issubset(set(state_machine.get("terminal_states", []))):
    raise SystemExit("run-state-machine.v1 missing terminal states")
if len(states) < 8:
    raise SystemExit("run-state-machine.v1 missing expected states")

allowed = {(t["from"], t["to"]) for t in state_machine.get("transitions", [])}
required_edges = {
    ("queued", "claimed"),
    ("claimed", "running"),
    ("running", "waiting_approval"),
    ("waiting_approval", "running"),
    ("waiting_approval", "failed"),
    ("running", "retry_scheduled"),
    ("retry_scheduled", "queued"),
    ("running", "completed"),
    ("running", "failed"),
}
if not required_edges.issubset(allowed):
    raise SystemExit("run-state-machine.v1 missing required transitions")


def validate_event(event):
    for key in required_event_keys:
        if key not in event:
            raise ValueError(f"missing required key: {key}")
    if event["schema_version"] != "event.v1":
        raise ValueError("schema_version must be event.v1")
    if event["actor_type"] not in {"system", "agent", "user"}:
        raise ValueError("invalid actor_type")
    if not re.match(r"^(task|run|policy|artifact|system)\.[a-z_]+$", event["event_type"]):
        raise ValueError("invalid event_type namespace")
    if not isinstance(event["payload"], dict):
        raise ValueError("payload must be object")


def validate_transition(src, dst):
    if (src, dst) not in allowed:
        raise ValueError(f"invalid transition: {src} -> {dst}")


valid_event = {
    "schema_version": "event.v1",
    "event_id": "evt_001",
    "event_type": "run.started",
    "occurred_at": "2026-02-18T00:00:00Z",
    "correlation_id": "corr_123",
    "task_id": "task_1",
    "run_id": "run_1",
    "agent_id": "agent_codex",
    "actor_type": "agent",
    "actor_id": "codex",
    "payload": {"state": "running"},
    "meta": {"provider": "codex"},
}
validate_event(valid_event)
validate_transition("queued", "claimed")
validate_transition("running", "completed")

invalid_event = dict(valid_event)
invalid_event.pop("event_id")
try:
    validate_event(invalid_event)
    raise SystemExit("expected invalid event to fail")
except ValueError:
    pass

try:
    validate_transition("completed", "running")
    raise SystemExit("expected invalid transition to fail")
except ValueError:
    pass

print("Schema and state machine contract checks passed.")
PY
