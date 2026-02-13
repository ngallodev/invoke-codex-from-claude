# Implementation Tasks: Fire-and-Forget Codex Invocation

## Context
Based on Codex 5.2's review of the main plan, we've identified critical issues that need to be addressed. This document breaks down the implementation into discrete tasks that can be executed sequentially by Codex mini.

**Parent Plan**: PLAN-fire-and-forget.md
**Review Session**: 019c41b2-3a08-74e2-b137-da90afb9aabd

## Critical Issues to Address

### Issue 1: Fire-and-forget doesn't surface Run ID/paths
**Problem**: `run_codex_task.sh` emits run ID and paths at the end, but background execution won't capture stdout.
**Solution**: Emit run ID and log paths BEFORE starting Codex execution.

### Issue 2: --resume conflicts with required --task validation
**Problem**: Script requires both `--repo` and `--task`, making resume-without-task impossible.
**Solution**: Make `--task` optional when `--resume` is provided.

### Issue 3: codex exec resume syntax needs verification
**Problem**: Unsure about `--cd` flag support and argument ordering with resume command.
**Solution**: Test actual CLI behavior and update command construction accordingly.

### Issue 4: Session ID extraction is brittle
**Problem**: `grep "^session id:"` assumes exact formatting, will fail with casing differences or ANSI codes.
**Solution**: Use robust regex with case-insensitive matching and UUID pattern extraction.

---

## Task Breakdown

### Task 1: Emit Run ID Before Execution
**File**: `scripts/run_codex_task.sh`
**Objective**: Print run ID and file paths to stdout BEFORE launching Codex, so background callers can capture them.

**Changes**:
1. After computing `RUN_ID`, `LOG_FILE`, `META_FILE` (around line 104-106)
2. Before writing debug preamble (before line 115)
3. Add immediate output block:
```bash
# Emit run info for background callers BEFORE execution
cat <<EOF_PRERUN
codex_run_id=$RUN_ID
log_file=$LOG_FILE
meta_file=$META_FILE
summary_file_pending=$LOG_DIR/codex-run-$RUN_ID.summary.json
EOF_PRERUN
```

**Verification**:
- Run: `scripts/run_codex_task.sh --repo . --task "test" | head -5`
- Should see run_id and paths in first 5 lines
- Confirm these appear BEFORE any Codex output

---

### Task 2: Make --task Optional When Resuming
**File**: `scripts/run_codex_task.sh`
**Objective**: Allow `--resume` without `--task` for pure session continuation.

**Changes**:
1. Update validation (around line 87-91):
```bash
if [[ -z "$REPO" ]]; then
  echo "Error: --repo is required." >&2
  usage >&2
  exit 2
fi

if [[ -z "$RESUME_SESSION" && -z "$TASK" ]]; then
  echo "Error: --task is required (unless --resume is provided)." >&2
  usage >&2
  exit 2
fi
```

2. Update usage text (lines 17-34):
```bash
Options:
  --repo <path>         Repository/workdir for codex exec --cd (required)
  --task <text>         Task prompt for Codex (required unless --resume is used)
  --resume <session>    Resume an existing Codex session by ID (optional)
  ...
```

**Verification**:
- Test: `scripts/run_codex_task.sh --repo . --task "create foo.txt"` (should work)
- Test: `scripts/run_codex_task.sh --repo . --resume SESSION_ID` (should work without --task)
- Test: `scripts/run_codex_task.sh --repo .` (should fail with clear error)

---

### Task 3: Add --resume Flag Support
**File**: `scripts/run_codex_task.sh`
**Objective**: Add argument parsing and command construction for resume functionality.

**Changes**:
1. Add variable initialization (around line 44):
```bash
RESUME_SESSION=""
```

2. Add argument parsing case (around line 48-84):
```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume)
      RESUME_SESSION="${2:-}"
      shift 2
      ;;
    # ... existing cases ...
```

3. Update command construction (replace line 111):
```bash
if [[ -n "$RESUME_SESSION" ]]; then
  # Resume existing session
  if [[ -n "$TASK" ]]; then
    # Resume with additional task
    CODEX_CMD=("$CODEX_BIN_PATH" exec --cd "$REPO" resume "$RESUME_SESSION" "$TASK" "${EXTRA_ARGS[@]}")
  else
    # Resume without additional task
    CODEX_CMD=("$CODEX_BIN_PATH" exec --cd "$REPO" resume "$RESUME_SESSION" "${EXTRA_ARGS[@]}")
  fi
else
  # New session
  CODEX_CMD=("$CODEX_BIN_PATH" exec --cd "$REPO" "$TASK" "${EXTRA_ARGS[@]}")
fi
```

**Note**: This assumes `--cd` works with resume. If testing reveals it doesn't, adjust to:
```bash
# If --cd doesn't work with resume, use cd in subshell
(cd "$REPO" && "$CODEX_BIN_PATH" exec resume "$RESUME_SESSION" ...)
```

**Verification**:
- Create test session: `scripts/run_codex_task.sh --repo . --task "echo test" > /tmp/test.log`
- Extract session: `SESSION_ID=$(grep "^session id:" /tmp/test.log | awk '{print $3}')`
- Test resume: `scripts/run_codex_task.sh --repo . --resume "$SESSION_ID" --task "continue"`
- Verify: Check log shows continuation, not new context

---

### Task 4: Robust Session ID Extraction
**File**: `scripts/run_codex_task.sh`
**Objective**: Extract session ID reliably regardless of formatting variations.

**Changes**:
After Codex execution completes (after line 149, before line 151):
```bash
# Extract session ID with robust pattern matching
# Pattern: UUID format (8-4-4-4-12 hex digits)
SESSION_ID=$(grep -i "session.*id" "$LOG_FILE" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | tail -1)

if [[ -z "$SESSION_ID" ]]; then
  echo "Warning: Could not extract session ID from log" >&2
  SESSION_ID="unknown"
fi
```

**Update metadata JSON** (line 156-171):
```python
python3 - <<PY > "$META_FILE"
import json
obj = {
  "run_id": "$RUN_ID",
  "session_id": "$SESSION_ID" if "$SESSION_ID" != "unknown" else None,
  "repo": "$REPO",
  "task": "$TASK",
  "resume_session": "$RESUME_SESSION" if "$RESUME_SESSION" else None,
  "codex_bin": "$CODEX_BIN",
  "log_file": "$LOG_FILE",
  "meta_file": "$META_FILE",
  "started_at": "$START_ISO",
  "ended_at": "$END_ISO",
  "elapsed_seconds": $ELAPSED,
  "exit_code": $CODEX_EXIT,
}
print(json.dumps(obj, ensure_ascii=True, indent=2))
PY
```

**Update summary output** (line 188):
```bash
cat <<EOF_SUMMARY | tee -a "$LOG_FILE"
codex_run_id=$RUN_ID
codex_session_id=${SESSION_ID}
codex_exit_code=$CODEX_EXIT
...
```

**Verification**:
- Run test: `scripts/run_codex_task.sh --repo . --task "test"`
- Check meta: `cat runs/codex-run-*.meta.json | jq '.session_id'`
- Verify: Should show UUID string, not null/unknown

---

### Task 5: Update Parser to Include Session ID
**File**: `scripts/parse_codex_run.py`
**Objective**: Include session_id and resume_session fields in parsed summary.

**Changes** (lines 93-106):
```python
output = {
    "run_id": meta.get("run_id"),
    "session_id": meta.get("session_id"),
    "resume_session": meta.get("resume_session"),
    "repo": meta.get("repo"),
    "task": meta.get("task"),
    "started_at": meta.get("started_at"),
    "ended_at": meta.get("ended_at"),
    "elapsed_seconds": meta.get("elapsed_seconds"),
    "exit_code": meta.get("exit_code"),
    "success": meta.get("exit_code") == 0 if isinstance(meta.get("exit_code"), int) else None,
    "log_file": str(log_path),
    "meta_file": args.meta,
    "token_usage": token_usage,
    "cost": cost,
}
```

**Verification**:
- Run: `scripts/run_codex_task.sh --repo . --task "test"`
- Parse: `python3 scripts/parse_codex_run.py --log runs/codex-run-*.log --meta runs/codex-run-*.meta.json`
- Check: `jq '.session_id' < output`
- Verify: Should show session ID from metadata

---

### Task 6: Update Debug Preamble with Mode Info
**File**: `scripts/run_codex_task.sh`
**Objective**: Add traceability for new vs resume mode in diagnostic logs.

**Changes** (in debug preamble section, around line 115-144):
```bash
{
  echo "===== run_codex_task.sh debug preamble ====="
  echo "timestamp_utc=$START_ISO"
  echo "timestamp_local=$START_LOCAL"
  echo "mode=$(if [[ -n "$RESUME_SESSION" ]]; then echo "resume"; else echo "new"; fi)"
  echo "resume_session_id=${RESUME_SESSION:-none}"
  echo "script_path=$SCRIPT_PATH"
  # ... rest of existing preamble ...
} | tee "$LOG_FILE"
```

**Verification**:
- New session: Check log shows `mode=new` and `resume_session_id=none`
- Resume session: Check log shows `mode=resume` and `resume_session_id=<UUID>`

---

## Execution Order

Tasks must be executed in this order due to dependencies:

1. **Task 1** (Emit Run ID Early) - Independent, enables background tracking ✅ COMPLETE
2. **Task 2** (Make --task Optional) - Independent, validation logic only ✅ COMPLETE
3. **Task 3** (Add --resume Flag) - Depends on Task 2 ✅ COMPLETE
4. **Task 4** (Session ID Extraction) - Independent, but needed for Task 3 to be useful ✅ COMPLETE
5. **Task 5** (Update Parser) - Depends on Task 4 ✅ COMPLETE
6. **Task 6** (Update Preamble) - Depends on Task 3, cosmetic ✅ COMPLETE

## ✅ ALL TASKS COMPLETE

All fire-and-forget and resume functionality has been successfully implemented!

## Notes

**Test Failure Handling**: Tasks 1 and 2 both exited with error code 2 due to syntax errors introduced during Codex's changes. Codex should better handle test failures - if a verification step fails with a syntax error or unexpected failure, it should:
1. Detect the error
2. Investigate the cause (read the file, check syntax)
3. Fix the issue before completing
4. Re-run verification

Currently Codex completes the task even when tests fail, leaving broken code behind.

## Testing Strategy

After each task:
1. Run basic test case
2. Verify output matches expectations
3. Ensure no regressions in existing functionality

After all tasks:
1. Full end-to-end test: Create session, capture ID, resume with new task
2. Test background execution with run ID capture
3. Verify parsed summary includes all new fields

## Success Criteria

- [ ] Background invocations return run ID immediately
- [ ] Session IDs are captured and stored in metadata/summary
- [ ] Resume flag works with and without additional task
- [ ] All existing tests pass
- [ ] New integration test passes (create → resume → verify context preserved)
