# Improvements to Codex Invocation Workflow

## Issues Discovered During Implementation

### Issue 1: Exit Codes Don't Always Reflect Task Success
**Problem**: Codex returns exit code 2 when internal verification commands fail, even if the actual task completed successfully.

**Evidence**:
- Task 1, 2, 3, 6: All exited with code 2
- All had correct changes, passing tests, valid syntax
- But Codex tried to run commands in its environment that failed

**Root Cause**:
- Codex's test commands assume `codex` binary is available
- Shell errors in Codex's environment propagate as exit codes
- The wrapper script exits with whatever Codex returns

### Issue 2: Codex Doesn't Always Fix Test Failures
**Problem**: Even with explicit instructions to "investigate and fix test failures", Codex completed tasks when verification failed.

**Evidence**:
- Tasks were told: "IMPORTANT: If verification tests fail with errors, investigate and fix the issues before completing"
- Codex still completed with syntax errors or failed verifications

### Issue 3: Transient vs Actual Failures
**Observation**:
- Tasks 4 & 5: Clean success (exit 0)
- These had simpler verification that didn't depend on Codex binary
- Suggests the failures were environmental, not task-related

## Recommended Solutions

### Solution 1: Post-Codex Verification by Claude
Instead of relying on Codex's exit code and self-verification:

```bash
# After Codex completes, Claude should:
1. Check syntax: bash -n <modified-files>
2. Run tests: <project-specific-test-command>
3. Verify expected changes: diff, grep for expected patterns
4. THEN decide if task succeeded
```

**Benefits**:
- Reliable verification in known environment
- Can handle Codex's transient errors
- Claude can fix issues Codex missed

### Solution 2: Separate Verification Phase
Add a `--verify` flag to the wrapper:

```bash
# Codex phase: do the work
scripts/run_codex_task.sh --repo . --task "..."

# Verification phase: check the work (in Claude's environment)
scripts/verify_codex_result.sh \
  --meta runs/codex-run-*.meta.json \
  --syntax-check \
  --run-tests \
  --expect-changes "pattern"
```

**Benefits**:
- Decouples execution from verification
- Verification runs in Claude's environment (where tools exist)
- Can be run multiple times without re-running Codex

### Solution 3: Enhanced Summary with Success Heuristics
Update the parser to detect common failure patterns:

```python
def assess_success(exit_code, log_text, meta):
    # Don't just trust exit code
    indicators = {
        "syntax_error": re.search(r"syntax error", log_text),
        "command_not_found": re.search(r"command not found", log_text),
        "test_failures": re.search(r"\[FAIL\]", log_text),
        "codex_completed": "tokens used" in log_text,
    }

    # If Codex completed work but had environmental errors,
    # mark as "needs_verification" not "failed"
    if exit_code != 0 and indicators["codex_completed"]:
        return "needs_verification"

    return "success" if exit_code == 0 else "failed"
```

### Solution 4: Better Task Specifications
**Current problem**: Tasks include verification steps but Codex's environment may not support them

**Better approach**:
```markdown
## Task: Update Parser to Include Session ID

### Changes Required:
- File: scripts/parse_codex_run.py
- Add fields: session_id, resume_session
- Location: output dict, lines 93-107

### DO NOT:
- Run the wrapper script (codex binary not available)
- Test with actual codex commands

### Verification (for reference):
Tests will be run by Claude after Codex completes.
```

**Benefits**:
- Clear about what Codex should/shouldn't do
- Acknowledges environmental limitations
- Moves verification responsibility to Claude

## Recommended Implementation Priority

1. **Immediate**: Solution 1 (Claude post-verification)
   - Easy to implement
   - Fixes the core issue
   - No changes to existing scripts needed

2. **Short-term**: Solution 4 (Better task specs)
   - Improves success rate
   - Reduces wasted effort
   - Just need better task descriptions

3. **Medium-term**: Solution 3 (Enhanced summary)
   - Helps distinguish real failures from environmental issues
   - Requires parser changes
   - Nice to have, not critical

4. **Long-term**: Solution 2 (Separate verification tool)
   - Most robust
   - Requires new tooling
   - Overkill for current use case

## Key Insight

**The real learning**: Codex is great at making code changes, but verification should happen in Claude's environment where we have:
- Reliable tooling
- Consistent environment
- Ability to interpret results contextually
- Power to iterate and fix issues

Codex → Do the work
Claude → Verify the work
This separation of concerns is the key to reliable automation.
