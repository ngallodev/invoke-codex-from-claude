---
name: codex-job
description: Fire-and-forget Codex invocation with smart failure detection and session resume. Use when delegating well-defined tasks to Codex. Invoked via /codex-job command.
disable-model-invocation: false
---

# Purpose

Invoke Codex CLI in fire-and-forget mode with automatic review on failure and session resume capability.

## When to Use This Skill

**Use `/codex-job` when**:
- Task has clear acceptance criteria and no ambiguous requirements
- Design decisions are finalized
- You want to delegate execution without burning tokens during Codex's work
- Task may take significant time (tests, multi-file changes, etc.)

**Do NOT use when**:
- Requirements are unclear or exploratory
- You need to iterate on design
- Task requires real-time feedback

## Instructions

### Basic Invocation
1. Construct clear task description with acceptance criteria
2. Choose appropriate Codex model (mini for simple, max for complex)
3. Use Bash tool with `run_in_background: true`
4. Capture session_id from output for potential resume
5. Prefer push notifications (`--notify-cmd`) so status does not require polling

### Smart Failure Handling
The wrapper automatically:
- Detects real failures vs environmental errors
- Triggers auto-review on real failures (resumes session)
- Treats environmental errors as success if work completed

### Session Resume
If additional work needed on same task:
- Extract session_id from summary JSON
- Use `--resume <session_id>` flag
- Context is preserved, no rebuild needed

## Workflow

### Step 1: Prepare Task
- Ensure task is well-defined
- No open design questions
- Clear success criteria

### Step 2: Invoke Codex
```javascript
Bash({
  command: "scripts/invoke_codex_with_review.sh --repo <repo_path> --task '<task_description>' --notify-cmd 'scripts/notify_claude_hook.sh --url https://<callback>' -- --model gpt-5.1-codex-mini",
  run_in_background: true,
  description: "Launch Codex task"
})
```

**Model selection**:
- `gpt-5.1-codex-mini`: Simple tasks, tests, docs, formatting
- `gpt-5.1-codex-max`: Default for most implementation work (use if unsure)
- `gpt-5.2-codex`: Complex reasoning, architectural decisions
- `gpt-5.3-codex`: Most complex tasks, equivalent to Opus

### Step 3: Capture Output
**Immediate output** (before Codex runs):
```
codex_run_id=20260209-041902-1946417
log_file=./runs/codex-run-*.log
meta_file=./runs/codex-run-*.meta.json
summary_file_pending=./runs/codex-run-*.summary.json
```

Use `run_id` to track the task.

### Step 4: Check Results (When Complete)
**Option A (push): Receive callback events**
Use `--notify-cmd` and handle events in your callback consumer.

**Option B: Check summary JSON**
```bash
cat runs/codex-run-<run_id>.summary.json | jq '{session_id, exit_code, success, token_usage}'
```

**Option C: Use verification script**
```bash
scripts/verify_codex_work.sh --meta runs/codex-run-<run_id>.meta.json --syntax-check --run-tests
```

### Step 5: Resume if Needed
```javascript
Bash({
  command: "scripts/run_codex_task.sh --repo <repo_path> --resume <session_id> --task 'Additional work or fixes' -- --model gpt-5.1-codex-mini",
  run_in_background: true
})
```

## Smart Detection Details

**Completion Indicators**:
- ✓ "tokens used" in log → Codex finished work
- ✗ No evidence of completion → Real failure

**Error Classification**:
- **Environmental**: `[stderr] syntax error`, `unexpected EOF`
  - Auto-handled, treated as success if work completed
- **Real**: `error:`, `fatal:`, `Exception:`, no completion
  - Triggers auto-review via session resume

**Auto-Review Trigger**:
```
Real failure detected → Extract session_id → Resume with review task → Fix issues
```

## Response Pattern

After invoking Codex, respond to user:
```
Codex task launched in background.

Run ID: <run_id>
Logs: ./runs/codex-run-<run_id>.log
Session ID: <will be available in summary when complete>

The task will complete in the background. I'll check the results when you're ready, or you can monitor the log file directly.
```

If user asks about status:
```javascript
Read({ file_path: "runs/codex-run-<run_id>.summary.json" })
```

Then report session_id, exit_code, success status, and whether review was triggered.

## Examples

### Example 1: Simple Task
**User**: "Use Codex to add type hints to functions in utils.py"

**Claude**:
```javascript
Bash({
  command: "scripts/invoke_codex_with_review.sh --repo /path/to/project --task 'Add type hints to all functions in utils.py. Use Python 3.10+ syntax. Verify with mypy.' -- --model gpt-5.1-codex-mini",
  run_in_background: true
})
```

### Example 2: Multi-file Feature
**User**: "Implement user authentication with session management"

**Claude**:
```javascript
Bash({
  command: "scripts/invoke_codex_with_review.sh --repo /path/to/project --task 'Implement user authentication: 1) Add User model with password hashing, 2) Create login/logout endpoints, 3) Add session middleware, 4) Write tests. Use existing patterns from the codebase.' -- --model gpt-5.1-codex-max",
  run_in_background: true
})
```

### Example 3: Resume Session
**User**: "The authentication tests are failing, ask Codex to fix them"

**Claude**:
```javascript
// First check session_id from previous run
Read({ file_path: "runs/codex-run-<run_id>.summary.json" })

// Then resume
Bash({
  command: "scripts/run_codex_task.sh --repo /path/to/project --resume <session_id> --task 'Fix failing authentication tests. Check error messages and update test assertions or implementation as needed.' -- --model gpt-5.1-codex-max",
  run_in_background: true
})
```

## Critical Notes

### Exit Codes
- Don't trust exit codes alone
- Smart detection filters environmental errors
- Verify with summary JSON: `"success": true`

### Token Efficiency
- Fire-and-forget saves 20k-80k tokens per task
- No streaming during execution
- Only read results when needed

### Context Preservation
- Session resume maintains full context
- No need to re-explain prior work
- Efficient for iterative fixes

### When Auto-Review Triggers
- Real failure detected → Auto-resumes session
- Asks Codex to review and fix
- Check review run's summary for final status

## Troubleshooting

**Task doesn't complete**:
- Check log file: `tail -f runs/codex-run-<run_id>.log`
- Look for errors or hangs

**Smart detection incorrect**:
- Run manual verification: `verify_codex_work.sh --meta <meta_file> --syntax-check --run-tests`
- Check FAILURE-ANALYSIS.md for known patterns

**Resume doesn't work**:
- Verify session_id is valid UUID
- Check that session exists in Codex (it may have expired)

**Auto-review fails**:
- Check review run logs
- May need manual intervention
- Consider resuming with more specific instructions

**No push notifications received**:
- Verify callback command works manually:
  - `echo '{"event":"ping"}' | scripts/notify_claude_hook.sh --url <callback_url>`
- If using `--notify-cmd`, ensure command exits `0` on success
- If needed, also set `--event-stream runs/codex-events.jsonl` for local event history

## Files Reference

- `scripts/invoke_codex_with_review.sh`: Main entry point with smart detection
- `scripts/run_codex_task.sh`: Core wrapper (use directly for manual control)
- `scripts/verify_codex_work.sh`: Independent verification
- `scripts/notify_claude_hook.sh`: Send event JSON to a callback endpoint
- `runs/codex-run-*.log`: Full execution logs
- `runs/codex-run-*.meta.json`: Metadata (session_id, timing, etc.)
- `runs/codex-run-*.summary.json`: Parsed summary (tokens, cost, success)

## Best Practices

1. **Clear task descriptions**: Include acceptance criteria and examples
2. **Use appropriate models**: mini for simple, max for standard, 5.2 for complex
3. **Capture session IDs**: Always save for potential resume
4. **Verify independently**: Don't rely on exit codes
5. **Resume for iterations**: More efficient than new sessions
6. **Monitor first few runs**: Build confidence in smart detection
7. **Check logs on failure**: Understand what went wrong before resuming
