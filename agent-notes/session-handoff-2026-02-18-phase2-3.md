# Session Handoff (2026-02-18, Phase 2/3 Start)

## Objective
Continue from MVP-stable baseline and begin deferred Phase 2/3 implementation in parallel while preserving canonical architecture:
- Canonical runtime remains `codex-job/scripts/`
- Root `scripts/` remain thin wrappers
- Experimental queue/dashboard remains opt-in install (`--include-experimental`)

## What Landed In This Session

### Phase 2 (L1): Runner Cache
Implemented opt-in-by-default result caching in canonical runner:
- File: `codex-job/scripts/run_codex_task.sh`
- New runner flags:
  - `--no-cache`
  - `--cache-dir <path>`
- New env var:
  - `CODEX_CACHE_DIR`
- Behavior:
  - Cache lookup for new task runs (`mode=new`) keyed by repo/task/model/tier plus git fingerprint
  - Cache hit fast-path returns without invoking Codex
  - Successful non-hit runs persist cache artifacts (`summary/meta/log`)
  - Graceful fallback if default cache dir is not writable

### Phase 2: Summary Schema Extension
- File: `codex-job/scripts/parse_codex_run.py`
- Added lean summary `cache` block:
  - `cache.status`
  - `cache.key`

### Phase 3 (N2): One-line Summarization
Added an optional one-line summary utility and wired it end-to-end:
- New script: `codex-job/scripts/summarize_codex_run.py`
- Runner integration (`codex-job/scripts/run_codex_task.sh`):
  - `--summarize`
  - `--summarizer <path>`
  - `CODEX_SUMMARIZER_PATH`
  - Emits `summary_line=...` in run output
  - Persists `one_line_summary` in meta JSON
  - Works for both normal and cache-hit run paths
- Invoke wrapper integration (`codex-job/scripts/invoke_codex_with_review.sh`):
  - Default summarize ON for invoke flows
  - `--no-summarize` to disable
  - `--summarizer <path>` pass-through
  - Applied to both initial invocation and review invocation

### Install/Uninstall Surface
Updated script install lists so summarizer deploys with core runtime:
- `install.sh` includes `summarize_codex_run.py`
- `uninstall.sh` includes `summarize_codex_run.py`

### Phase 3 (N1) Support: Queue Tool Tests
Added hermetic tests for existing queue/dashboard tooling:
- `tests/test_job_queue_tools.sh`
- Covers `job_queue.py` lifecycle and `job_queue_server.py --help` + dashboard fallback behavior

## Tests Added/Updated
- Updated `tests/test_runner_and_parser.sh`:
  - cache hit behavior
  - `--no-cache` behavior
  - `--summarize` behavior
- Updated `tests/test_invoke_and_notify.sh`:
  - invoke default summarize behavior
  - invoke `--no-summarize` override
- New `tests/test_summarize_codex_run.sh`
- New `tests/test_job_queue_tools.sh`

## Validation Run (all green)
- `bash tests/test_runner_and_parser.sh`
- `bash tests/test_invoke_and_notify.sh`
- `bash tests/test_install_dry_run.sh`
- `bash tests/test_agents_metadata.sh`
- `bats --tap --print-output-on-failure tests/test_run_codex_task.bats`
- `bash tests/test_summarize_codex_run.sh`
- `bash tests/test_job_queue_tools.sh`
- `bash tests/test_gemini_runner_and_parser.sh`

## Current Branch / Push Target
- Branch: `feature/multi-agent-coordination`
- Remote: `origin`

## Recommended Next Steps After Restart
1. N2 polish:
   - Consider adding a dedicated invoke README section for summarize flags and examples.
2. L1 polish:
   - Add explicit cache key semantics doc (what invalidates cache).
   - Consider configurable cache TTL/eviction strategy.
3. N1 expansion:
   - Wire queue/dashboard into explicit opt-in runtime flow (not default path), guarded by a flag.
4. Optional:
   - Add targeted bats coverage for summarize behavior on cache-hit path.
