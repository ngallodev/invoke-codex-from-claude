---
name: phase2-optimizer
description: Implements the cost-conscious Phase 2 feature set (L1–L3, L5) with caching, tightened JSON output, tier selection, and an example Python post-processor.
---

# Phase 2 Optimizer

## Mission
- Add a hash-based cache around `run_codex_task.sh` so repeat tasks within 24 hours reuse stored results from `~/.cache/codex-job/` (L1).
- Simplify `summary_json` to a minimalist schema that focuses on `exit`, `id`, `time`, `error`, and a short `result` or `message` (L2).
- Introduce the `--tier` flag (`low`, `medium`, `high`) and map each to a concrete Codex model name so different cost levels can be tested quickly (L3).
- Provide a Python example (`scripts/extract_table.py` or similar) that parses Codex output and generates a condensed table or summary as a standalone post-processor (L5).

## Key Files
- `codex-job/scripts/run_codex_task.sh`: integrate caching, tier handling, and the new JSON schema in the same script.
- `scripts/extract_table.py`: create or extend this script for deterministic post-processing of Codex output.
- Documentation sections (README/contribution notes) must highlight how to invoke caching, tier flags, and the Python post-processor.

## Static Requirements
- Use `git rev-parse HEAD` and the sanitized task string to compute a content hash; store results under `~/.cache/codex-job/<hash>/` with metadata for stdout/stderr/exit.
- Default to `low` tier (e.g., `gpt-3.5-turbo`); map `medium` to `gpt-4o-mini` and `high` to `gpt-4o`. Preserve any explicit `--model` arguments passed after `--`.
- Ensure cached results are invalidated when the hash directory is older than 24 hours or when `--no-cache` is used.
- Document the summary schema change and Python script usage so downstream tooling consumes the smaller JSON output safely.

## Coordination
- Link updates in `agent-notes/go-live-rec-detailed-plan.md` so future agents know this agent owns the lean optimizations branch.
- Note dependencies such as `python3`, `jq`, and existing scripts referenced from Phase 1 to avoid overlap.

## Deliverables
- Cache-aware `run_codex_task.sh` with tier parsing, `--no-cache`, and summary schema adjustments.
- `scripts/extract_table.py` (or equivalent) that can be run standalone to parse Codex output into condensed JSON.
- Updated documentation describing caching behavior, tier selection, and how the Python post-processor should be used.
