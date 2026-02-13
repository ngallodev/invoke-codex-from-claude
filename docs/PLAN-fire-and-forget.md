# Plan: Fire-and-Forget Codex Invocation

## Context
Currently, when Claude invokes Codex via the Bash tool, it streams all output in real-time. This consumes tokens unnecessarily while Codex executes (which can take 30+ seconds or minutes). The user correctly identified that this should be a "fire and forget" operation where:
1. Claude constructs and launches the Codex command
2. Execution happens in background
3. Claude can optionally check results later, but doesn't burn tokens while Codex runs

## Current Behavior Analysis
- Claude calls: `Bash(command="scripts/run_codex_task.sh --repo ... --task ...")`
- This blocks and streams all Codex output (~19k tokens in the last example)
- The wrapper script already:
  - Captures all output to log files
  - Writes structured metadata (meta.json, summary.json)
  - Provides machine-readable output at the end

## Problem
The current approach wastes tokens because Claude monitors the entire execution stream even though all results are already captured to files by the wrapper script.

## Proposed Solution: Use Background Execution

### Approach
Use the Bash tool's `run_in_background: true` parameter to execute Codex without blocking.

**Execution pattern:**
```javascript
Bash({
  command: "scripts/run_codex_task.sh --repo /path --task 'description' -- --model gpt-5.1-codex-mini",
  run_in_background: true,
  description: "Launch Codex task in background"
})
```

**Result checking (optional, later):**
- Use TaskOutput tool to retrieve results when needed
- Or: Simply point user to the log files (runs/codex-run-*.log, *.summary.json)
- The wrapper already provides all artifacts with predictable paths

## Trade-offs

### Background Execution Pros:
- ✅ No token cost during Codex execution
- ✅ Claude can continue with other work or return control to user
- ✅ All outputs still captured by wrapper script
- ✅ Machine-readable summary.json available after completion

### Background Execution Cons:
- ❌ Claude doesn't know when Codex finishes (without polling)
- ❌ Can't immediately report success/failure
- ❌ User must be informed that task is running in background

## User Requirements (Clarified)

1. **Fire-and-forget**: Minimize token usage - Claude launches Codex and returns immediately
2. **Resume support**: Must be able to call Codex's resume function later for additional work on same task without rebuilding context
3. **Scope**: Focus on getting the basic invocation working first, skill creation comes later

## Key Discovery: Codex Resume Feature

Codex has **built-in resume support** that's perfect for this use case:

### What Codex Provides
- Every `codex exec` run generates a **session ID** (UUID format)
- Session ID is printed to stdout: `session id: 019c41a6-47a1-7450-9482-bb111cc8d1d4`
- Resume command: `codex exec resume [SESSION_ID]` or `codex exec resume [SESSION_ID] "Follow-up task"`
- Non-interactive, works perfectly with background execution

### What We're Missing
Current wrapper (`run_codex_task.sh` + `parse_codex_run.py`) does NOT:
- Extract the session ID from Codex output
- Store session ID in metadata/summary JSON files
- Support the `--resume` flag to resume existing sessions

### The Gap
Without capturing session IDs, we can't resume tasks. The session ID is buried in the log file but never surfaced to Claude.

## Implementation Strategy

### Phase 1: Background Execution (Token Reduction)
Add `run_in_background: true` to Bash calls invoking Codex. This alone saves tokens.

**Result**: Claude launches task and immediately returns with:
- Run ID for tracking
- Log file paths where output will be written
- Summary file path (created when Codex finishes)

### Phase 2: Session ID Capture & Resume Support
Enhance the wrapper to capture and expose session IDs for resume functionality.

**Changes needed:**
1. `run_codex_task.sh`: Extract session ID from Codex output, add to metadata
2. `parse_codex_run.py`: Include session_id field in parsed summary JSON
3. `run_codex_task.sh`: Add `--resume [SESSION_ID]` flag to resume existing sessions

**Result**: Summary JSON will include:
```json
{
  "run_id": "20260209-010541-1893988",
  "session_id": "019c41a6-47a1-7450-9482-bb111cc8d1d4",
  "repo": "/lump/apps/invoke-codex-from-claude",
  "exit_code": 0,
  ...
}
```

### Phase 3: Resume Workflow
Claude can resume a Codex session:
```bash
scripts/run_codex_task.sh \
  --resume 019c41a6-47a1-7450-9482-bb111cc8d1d4 \
  --task "Continue the previous work and fix the tests" \
  -- --model gpt-5.1-codex-mini
```

Or without a new task (just resume interactive):
```bash
scripts/run_codex_task.sh \
  --resume 019c41a6-47a1-7450-9482-bb111cc8d1d4
```

## Detailed Implementation Plan

### Step 1: Background Execution (Immediate Win)
**File**: None - this is a usage change only
**Change**: When Claude invokes Codex via Bash, add `run_in_background: true`

**Example**:
```javascript
Bash({
  command: "scripts/run_codex_task.sh --repo /path --task 'Fix tests' -- --model gpt-5.1-codex-mini",
  run_in_background: true,
  description: "Launch Codex task in background"
})
```

**Claude's response pattern**:
```
Codex task launched in background.

Run ID: 20260209-010541-1893988
Logs: ./runs/codex-run-20260209-010541-1893988.log
Summary (when complete): ./runs/codex-run-20260209-010541-1893988.summary.json

Use TaskOutput or check the summary file to see results when Codex finishes.
```

### Step 2: Capture Session ID
**File**: `scripts/run_codex_task.sh`
**Location**: After line 149 (after Codex execution)

**Add session ID extraction**:
```bash
# Extract session ID from Codex output
SESSION_ID=$(grep "^session id:" "$LOG_FILE" | tail -1 | awk '{print $3}')
```

**Update metadata JSON** (lines 156-171):
```bash
python3 - <<PY > "$META_FILE"
import json
obj = {
  "run_id": "$RUN_ID",
  "session_id": "$SESSION_ID",  # NEW
  "repo": "$REPO",
  "task": "$TASK",
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
codex_session_id=$SESSION_ID  # NEW
codex_exit_code=$CODEX_EXIT
...
```

### Step 3: Parse Session ID in Summary
**File**: `scripts/parse_codex_run.py`
**Location**: Lines 93-106 (output construction)

**Add session_id field**:
```python
output = {
    "run_id": meta.get("run_id"),
    "session_id": meta.get("session_id"),  # NEW
    "repo": meta.get("repo"),
    "task": meta.get("task"),
    ...
}
```

### Step 4: Add Resume Flag
**File**: `scripts/run_codex_task.sh`
**Location**: Lines 17-34 (usage) and 41-85 (argument parsing)

**Update usage**:
```bash
Options:
  --repo <path>         Repository/workdir for codex exec --cd (required)
  --task <text>         Task prompt for Codex (required)
  --resume <session>    Resume an existing Codex session by ID (optional)  # NEW
  --codex-bin <path>    Codex binary/command (default: codex)
  ...
```

**Add argument parsing**:
```bash
RESUME_SESSION=""  # NEW

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume)
      RESUME_SESSION="${2:-}"
      shift 2
      ;;
    # ... existing cases ...
```

**Update Codex command construction** (line 111):
```bash
if [[ -n "$RESUME_SESSION" ]]; then
  # Resume existing session with optional new task
  if [[ -n "$TASK" ]]; then
    CODEX_CMD=("$CODEX_BIN_PATH" exec resume --cd "$REPO" "$RESUME_SESSION" "$TASK" "${EXTRA_ARGS[@]}")
  else
    CODEX_CMD=("$CODEX_BIN_PATH" exec resume --cd "$REPO" "$RESUME_SESSION" "${EXTRA_ARGS[@]}")
  fi
else
  # New session
  CODEX_CMD=("$CODEX_BIN_PATH" exec --cd "$REPO" "$TASK" "${EXTRA_ARGS[@]}")
fi
```

## Critical Files to Modify
1. **scripts/run_codex_task.sh** (lines ~149, 156-171, 17-34, 41-85, 111)
   - Extract session ID from log
   - Add to metadata JSON
   - Add --resume flag support
   - Conditionally build resume vs new session command

2. **scripts/parse_codex_run.py** (lines 93-106)
   - Add session_id to output JSON

3. **Usage pattern** (no file change)
   - Claude uses `run_in_background: true` on Bash invocations

## Verification Steps

### Test 1: Background Execution
```bash
# Should return immediately, not stream output
scripts/run_codex_task.sh \
  --repo /lump/apps/invoke-codex-from-claude \
  --task "Add a comment to README" \
  -- --model gpt-5.1-codex-mini
```
**Verify**:
- Command returns immediately (< 1 second)
- Log file is created and grows over time
- Summary JSON appears after Codex completes

### Test 2: Session ID Capture
```bash
# Run a task
scripts/run_codex_task.sh --repo . --task "Test task"

# Check metadata includes session_id
cat ./runs/codex-run-*.meta.json | jq '.session_id'
# Should output: "019c41a6-47a1-7450-9482-bb111cc8d1d4" (or similar UUID)

# Check summary includes session_id
cat ./runs/codex-run-*.summary.json | jq '.session_id'
```

### Test 3: Resume Functionality
```bash
# First task
scripts/run_codex_task.sh --repo . --task "Create a test file named foo.txt"

# Capture session ID from previous run
SESSION_ID=$(cat ./runs/codex-run-*.summary.json | jq -r '.session_id' | tail -1)

# Resume with additional work
scripts/run_codex_task.sh \
  --resume "$SESSION_ID" \
  --task "Now add the text 'hello world' to foo.txt"
```
**Verify**:
- Second command resumes first session
- Context from first task is available
- No context rebuilding needed

### Test 4: Full Fire-and-Forget from Claude
**In Claude session**:
```
Invoke Codex to create a simple Python script, run it in background using gpt-5.1-codex-mini
```
**Verify**:
- Claude returns immediately with run ID and log paths
- No token cost during Codex execution
- Summary JSON includes session_id
- Can later ask: "Resume that Codex session and ask it to add error handling"
