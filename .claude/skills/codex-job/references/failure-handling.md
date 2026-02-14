# Failure Handling

## Classification Rules

- Environmental failure: wrapper/runtime issue outside task semantics.
- Spec failure: prompt/spec contradictions, missing requirements, or invalid assumptions.
- Execution failure: implementation/test errors requiring task iteration.

## Smart Handling Expectations

- Do not rely on exit code alone.
- Use summary JSON and logs to classify actual outcome.
- Trigger review/resume flow for real failures.
- If work completed but environment failed post-run, mark partial/success per evidence.

## Troubleshooting Checklist

1. Check log: `tail -f runs/codex-run-<run_id>.log`
2. Check summary: `runs/codex-run-<run_id>.summary.json`
3. Verify session id exists before resume.
4. Resume with narrower, explicit fix instructions.
