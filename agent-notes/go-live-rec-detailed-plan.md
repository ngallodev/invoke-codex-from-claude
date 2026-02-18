📋 Phase 1: Critical Fixes (Must Have for MVP/Go‑Live)
These tasks address security, stability, and usability. They should be completed before any new features.

ID	Task	Description	Complexity	AI Model Tier	Dependencies	Parallelizable With
C1	Secrets Management	Modify run_codex_task.sh to read all credentials (Codex API keys, webhook secrets) from environment variables. Add validation that fails with a clear error if required vars are missing, and consult `.claude/agents/team/phase1-shield.md` for the expected env var names (`CODEX_API_KEY`, `CODEX_WEBHOOK_SECRET`, etc.) and the `codex-job/scripts/run_codex_task.sh` layout.	Low	Low (AI can generate error messages and validation snippets)	None	C2, C3, C4
C2	Error Handling & Timeouts	Wrap the Codex call with timeout, ensure traps handle `SIGINT/SIGTERM`, and guarantee every exit path emits a valid `summary_json` (see `.claude/agents/team/phase1-shield.md` for the required JSON schema and cleanup expectations).	Medium	Low (AI can help write robust bash error handling)	None	C1, C3, C4
C3	Expand Test Suite	Add tests for: long-running tasks, special characters in task names, network failures (simulated), and the notification system. Use bats (Bash Automated Testing System) or shell scripts, and reference `.claude/agents/team/phase1-shield.md` for guidance on mocking `codex`, triggering `--notify-cmd`, and validating JSON summaries.	Medium	Low (AI can generate test cases and assertions)	None	C1, C2, C4
C4	Install/Uninstall Robustness	Make install.sh idempotent, add a companion uninstall.sh, and include a `--dry-run` flag for both scripts; `.claude/agents/team/phase1-shield.md` notes the files to touch (profiles, skill install path) and how to log actions for reversals.	Medium	Low (AI can help design idempotent installation logic)	None	C1, C2, C3
C5	Documentation Overhaul	Rewrite README with: prerequisites, explanation of the wrapper’s purpose, a full end-to-end example, and troubleshooting tips; coordinate with `.claude/agents/team/phase1-shield.md` to capture the new env vars, dry-run steps, and testing commands.	Low	Medium (AI can draft clear, structured documentation)	None	C1–C4 (can be done in parallel)
Parallel Group 1: C1, C2, C3, C4, C5 can all be worked on simultaneously by different agents.

🧠 Phase 2: Lean & AI‑Cost Optimizations
These improvements reduce token usage and runtime costs. They build on the stable foundation from Phase 1.

ID	Task	Description	Complexity	AI Model Tier	Dependencies	Parallelizable With
L1	Result Caching	Implement a content-based cache: before calling Codex, compute a hash of the task + repo state (e.g., git rev-parse HEAD). If a previous result exists, return it immediately. Use a simple file-based cache (~/.cache/codex-job/); see `.claude/agents/team/phase2-optimizer.md` for the hash strategy, cache layout, and `--no-cache` behavior.	Medium	Low (AI can generate the hashing and cache logic)	C2 (error handling)	L2, L3, L5
L2	Optimize JSON Summary	Review the current summary_json output. Remove redundant fields, use short keys (e.g., "exit" instead of "exit_code"), and ensure only essential data is included. Update documentation accordingly and follow `.claude/agents/team/phase2-optimizer.md` for the target schema and documentation updates.	Low	Low (AI can suggest a minimal schema)	None	L1, L3, L5
L3	Model Tier Selection	Add a --tier flag to run_codex_task.sh (values: low, medium, high). Map tiers to specific Codex models via a simple case statement. Pass the chosen model to Codex and record the mapping in `.claude/agents/team/phase2-optimizer.md`, which also shows how to honor explicit `--model` overrides.	Low	Low (AI can write the argument parsing and mapping)	None	L1, L2, L5
L4	Context Minimization (Advanced)	Optional for later. Instead of passing the entire repo, build a minimal context: e.g., list of files, recent git diff, or a tree. This requires deeper integration with Codex or a pre-processor; coordinate with `.claude/agents/team/phase2-optimizer.md` once caching/tiering is stable so context builders can reuse the same hashes.	High	Medium (AI can help design the context-building script)	Stable core	None (complex, should be done after other lean tasks)
L5	Python Post-processing Example	Create a sample Python script that parses Codex output (e.g., extracts a table) and emits a condensed result. Place it in scripts/ and document its use as a model for replacing LLM calls; the `.claude/agents/team/phase2-optimizer.md` file contains the example command line and README instructions.	Low	Low (AI can generate the script)	None	L1, L2, L3
Parallel Group 2: L1, L2, L3, L5 can be done together. L4 is separate and can be tackled later.

✨ Phase 3: Next Features (Post‑MVP)
These features add polish and advanced capabilities, making the project stand out.

ID	Task	Description	Complexity	AI Model Tier	Dependencies	Parallelizable With
N1	Job Queue & Status Dashboard	Build a simple job queue (using files or a lightweight DB like SQLite) to track Codex tasks. Create a minimal web dashboard (static HTML + JavaScript) that reads the queue and displays status. Use a lightweight HTTP server (e.g., Python's http.server); refer to `.claude/agents/team/phase3-polisher.md` for the schema (`id`, `task`, `status`, `result_path`) and dashboard setup notes.	High	Medium (AI can help design the queue logic and generate frontend code)	Stable core, L1 (caching can be integrated)	N2, N3, N4
N2	Result Summarization with Cheaper Model	After Codex completes, optionally call a low-cost model (e.g., a local Ollama model) to generate a one-line summary. Add a flag --summarize to enable. Use the cheapest available model, and follow `.claude/agents/team/phase3-polisher.md` for how the flag integrates with the job queue hooks.	Medium	Low (the summarization itself uses a low-cost model; AI can help write the integration)	L3 (model tiers)	N1, N3, N4
N3	Webhook Signature Verification	Enhance notify_claude_hook.sh to sign the JSON payload with HMAC-SHA256 using a shared secret. Document how receivers can verify the signature; `.claude/agents/team/phase3-polisher.md` outlines reading `WEBHOOK_SECRET`/`--secret` and adding `X-Signature`.	Medium	Low (AI can generate the signing code)	C1 (secrets management)	N1, N2, N4
N4	Self-Diagnosis Mode (--doctor)	Add a --doctor flag that checks: required commands (codex, jq, etc.), environment variables, permissions, and connectivity. Print a clear report; use `.claude/agents/team/phase3-polisher.md` to show what the diagnostics should cover and how to emit suggestions.	Medium	Low (AI can generate the check functions)	None	N1, N2, N3
N5	Contribution Guide	Create CONTRIBUTING.md with coding standards, testing instructions, and pull request process; coordinate with `.claude/agents/team/phase3-polisher.md` for the expectations on documentation quality and testing.	Low	Medium (AI can draft a professional guide)	None	Any
Parallel Group 3: N2, N3, N4, N5 can be worked on together. N1 is a larger feature that may be developed in parallel but could also benefit from the others.

🧑‍💻 Multi‑Agent Coordination Tips
Phase 1 agents should focus on stability and security. They can work independently but must coordinate on changes to shared files (e.g., run_codex_task.sh) to avoid merge conflicts. Use feature branches.

Phase 2 agents can start as soon as Phase 1 is merged, or even earlier if they base their work on the same stable core. Caching (L1) depends on the error handling from C2, so that should be merged first.

Phase 3 agents can begin after the core is stable, but some tasks (like N2) depend on Phase 2 features.

## Optimized Multi-Agent Execution Plan (using new specialists)
- **C1 + C2 (secrets, timeouts, JSON)**: Run `security-hardener` + `bash-error-handling-specialist` in parallel on a shared feature branch; coordinate on `run_codex_task.sh` to avoid clashes. Gate completion on updated bats tests from `test-generator-shell`.
- **C3 (tests)**: `test-generator-shell` extends bats coverage after C1/C2 land; unblock merges only after all new tests pass locally (`tests/test_runner_and_parser.sh`, `tests/test_gemini_runner_and_parser.sh`, `tests/test_invoke_and_notify.sh`, plus new targeted cases).
- **C4 (install/uninstall)**: `installation-engineer` works independently once env validation patterns from C1 are merged; requires a short dry-run test script to verify idempotency.
- **C5 (docs)**: `technical-writer` can operate after C1–C4 conclusions are sketched; sync with `installation-engineer` for flags and with `json-minimizer` for schema notes.
- **L1/L2/L3/L5**: `caching-architect`, `json-minimizer`, `model-tier-integrator`, and `python-post-processor` can proceed concurrently after C2; cache/tier changes share `run_codex_task.sh` so merge via sequential PRs or feature toggles.
- **L4**: Start after L1–L3 stabilize; reuse hashes defined by `caching-architect`.
- **N1–N5**: `job-queue-designer`, `webhook-signer`, `self-diagnosis-creator`, and `technical-writer` collaborate; `N2` waits on tier mapping; `N3` depends on C1 secrets; `N4` depends on env checks from C1/C2.
- **Telemetry**: All agents must report `input_tokens`, `output_tokens`, `cached_tokens`, `context_tokens`, and `elapsed_seconds` per session to keep cost tracking uniform.
- **Silence until done**: Agents should not stream progress; they return one final success/failure with telemetry. Any detailed notes go to `agent-history.log` in repo root.
- **Test gating**: A task is “done” only when relevant integration/unit tests pass, including the minimal metadata check `tests/test_agents_metadata.sh` plus feature-specific bats/CLI tests each agent adds.


Telemetry gate: set `TELEMETRY_ENABLED=1` (default) to include metrics; set to 0 to suppress. Required telemetry keys when enabled: `input_tokens`, `output_tokens`, `cached_tokens`, `context_tokens`, `elapsed_seconds`.