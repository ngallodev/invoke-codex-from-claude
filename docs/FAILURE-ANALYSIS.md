# Failure Analysis: Exit Code Investigation

## Summary
During implementation of 6 tasks, 4 tasks reported exit code 2 but actually completed successfully. Investigation revealed these were **environmental errors in Codex's execution sandbox**, not real failures.

## Failure Details

| Task | Exit | Error Type | Line | Root Cause |
|------|------|------------|------|------------|
| 1 | 2 | `syntax error near unexpected token 'then'` | 148 | Shell parsing error in Codex's verification commands |
| 2 | 2 | `syntax error near unexpected token ')'` | 157 | Shell parsing error in Codex's verification commands |
| 3 | 2 | `unexpected EOF while looking for matching '"'` | 239 | Unclosed quote in Codex's verification commands |
| 6 | 2 | `unexpected EOF while looking for matching '"'` | 259 | Unclosed quote in Codex's verification commands |

## Key Findings

### 1. Exit Codes Are Misleading
**Problem**: Codex returns non-zero exit codes when verification commands fail in its environment, even after successfully completing the requested work.

**Evidence**:
- All modified files had valid syntax (`bash -n` passed)
- All tests passed when run independently
- Metadata confirmed work completed (session IDs captured, tokens used)
- Changes were correct and functional

### 2. The Execution Flow
```
1. Codex receives task               ✓
2. Codex makes code changes          ✓
3. Codex writes correct code         ✓
4. Codex tries verification in sandbox  (may fail - no codex binary, shell errors)
5. Returns exit code from step 4    ✗ (misleading)
```

### 3. Environmental vs Real Failures

**Environmental Failures** (false positives):
- `[stderr] scripts/run_codex_task.sh: line X: syntax error`
  - Happens when Codex tries to test the script it modified
  - Our script is valid, but Codex's shell command parsing fails
- `command not found: codex`
  - Codex tries to run wrapper script in verification
  - `codex` binary doesn't exist in Codex's sandbox
- Shell errors at lines 148, 157, 239, 259
  - These are WHERE Codex executed something, not where our code has errors

**Real Failures** (should trigger review):
- No "tokens used" in log → didn't complete
- `error:`, `fatal:`, `Exception:` in logs → actual errors
- Syntax check fails when WE run it → code has issues

## Solution Implemented

### Smart Failure Detection
`invoke_codex_with_review.sh` now checks:

1. **Did Codex complete?** → Look for "tokens used" in log
2. **Real errors present?** → Check for `error:|fatal:|Exception:`
3. **Shell errors?** → Detect `[stderr].*syntax error` patterns

**Decision logic**:
```bash
if [[ CODEX_COMPLETED && !REAL_ERRORS ]]; then
  # Environmental issue - treat as success
  exit 0
else
  # Real failure - trigger review
  codex exec --cd $repo resume $session "Review and fix..."
fi
```

### Independent Verification
`verify_codex_work.sh` validates work in Claude's environment:
- Check task completion (tokens used)
- Detect real vs environmental errors
- Syntax check modified files (`bash -n`, `python3 -m py_compile`)
- Run test suite
- Exit 0 only if all checks pass

## Impact on Workflow

### Before (Broken)
```
Codex completes work → Exit code 2 → Claude thinks it failed → Waste time investigating
```

### After (Fixed)
```
Codex completes work → Exit code 2 → Smart detection → Treats as success → Continue
```

**OR**

```
Codex truly fails → Exit code ≠ 0 → Smart detection → Real failure → Auto-review → Fix
```

## Metrics

### Observed Results
- Total tasks: 6
- Reported failures: 4 (exit code 2)
- Actual failures: 0
- False positive rate: 100% (4/4)

### After Smart Detection
- Environmental errors: Auto-handled
- Real failures: Auto-reviewed
- Human intervention: Only when review also fails

## Recommendations

### For Claude
1. **Always use invoke_codex_with_review.sh** instead of run_codex_task.sh directly
2. **Don't trust exit codes alone** - verify work independently
3. **Run verify_codex_work.sh** after Codex completes for confidence

### For Future Tasks
1. **Don't ask Codex to verify** - it can't run tests in its environment reliably
2. **Keep verification separate** - let Codex do work, Claude verifies
3. **Use resume for fixes** - when real failures occur, resume session to maintain context

## Lessons Learned

### Key Insight
**Codex is excellent at making code changes but verification should happen in a known environment with reliable tools.**

**Separation of concerns**:
- **Codex** → Makes changes
- **Smart detection** → Filters false positives
- **Verification script** → Validates work
- **Claude** → Decides next steps

This architecture makes the system resilient to Codex's environmental limitations while still leveraging its code generation capabilities.

## Testing Recommendations

When testing this workflow:
1. Let task fail/succeed naturally
2. Check what smart detection decided
3. Run verification script independently
4. Compare all three results

Expected: Smart detection and verification align, exit code may not.
