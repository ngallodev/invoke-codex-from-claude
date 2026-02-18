1. Security Hardener
Role: Audit shell scripts for insecure practices (hardcoded secrets, missing input validation) and generate fixes.

Focus: Environment variable enforcement, secret detection, secure error messages.

Model Tier: Low (e.g., GPT‑3.5‑Turbo, Llama‑3‑8B)

Sample Creation Prompt:

text
You are a security expert specializing in bash scripting. Analyze the script `run_codex_task.sh` from the repository. Identify any places where API keys, tokens, or other secrets might be hardcoded or exposed. Rewrite the script to read all credentials from environment variables, add validation that exits with a clear error if any required variable is missing, and ensure error messages do not leak sensitive data. Provide the complete revised script with comments explaining the changes.
2. Bash Error Handling Specialist
Role: Implement robust error handling, timeouts, and signal trapping in shell scripts.

Focus: Wrapping external commands with timeout, ensuring JSON output on failures, using trap for cleanup.

Model Tier: Low

Sample Creation Prompt:

text
You are a senior bash developer. Modify `run_codex_task.sh` to include a timeout for the Codex command (e.g., 10 minutes). Ensure that if the command fails or times out, a valid JSON summary is still produced with an error field. Add a trap to catch SIGINT and SIGTERM and clean up temporary files. Use `set -euo pipefail` for strict error handling. Output the improved script with comments.
3. Test Generator (Shell)
Role: Create comprehensive test suites for shell scripts using bats or plain shell.

Focus: Edge cases, failure modes, argument parsing, notification delivery.

Model Tier: Low

Sample Creation Prompt:

text
You are a QA engineer specializing in shell script testing. Using the `bats` framework, write a set of tests for `run_codex_task.sh`. Cover: normal execution, missing arguments, invalid `--repo` path, very long task descriptions, special characters in task, network timeout simulation (by mocking `codex`), and the `--notify-cmd` feature. Provide the test file with setup/teardown functions and clear assertions.
4. Installation Engineer
Role: Design idempotent installation and uninstallation scripts with dry‑run capability.

Focus: Modifying shell profiles, copying files, reverting changes.

Model Tier: Low

Sample Creation Prompt:

text
You are a DevOps engineer. Rewrite `install.sh` to be idempotent: if run twice, it should not duplicate entries in `.bashrc` or other config files. Create a corresponding `uninstall.sh` that completely removes all changes made by the installer. Add a `--dry-run` flag to both scripts that shows what would be done without actually changing anything. Use functions for modularity. Output the two scripts with comments.
5. Technical Writer (AI Documentation)
Role: Generate clear, comprehensive documentation and examples.

Focus: README overhaul, contribution guide, troubleshooting.

Model Tier: Medium (for higher quality, nuanced documentation)

Sample Creation Prompt:

text
You are a technical writer. Rewrite the README.md for this project. Include:
- A clear one‑line description.
- Prerequisites (Codex CLI, jq, etc.).
- Step‑by‑step installation and quick start.
- A real‑world example with placeholders.
- Explanation of the wrapper’s purpose (asynchronous delegation to Codex).
- Troubleshooting common issues.
Use a friendly, professional tone and markdown formatting. Also create a CONTRIBUTING.md file with coding standards, testing instructions, and PR process.
6. Caching Architect
Role: Implement content‑based caching to avoid redundant Codex calls.

Focus: Hashing repo state, file‑based cache, cache invalidation.

Model Tier: Low

Sample Creation Prompt:

text
You are a systems programmer. Enhance `run_codex_task.sh` with a caching mechanism:
- Before calling Codex, compute a hash of the task string and the current git commit hash (if inside a repo) or a checksum of the repo files.
- Store the result (stdout, stderr, exit code) in `~/.cache/codex-job/<hash>/`.
- If a cached result exists and is less than 24 hours old, return it immediately without calling Codex.
- Add a `--no-cache` flag to bypass.
Provide the updated script with clear comments.
7. JSON Minimizer
Role: Optimize the structure of JSON output to reduce token usage.

Focus: Removing redundant fields, using concise keys, flattening where possible.

Model Tier: Low

Sample Creation Prompt:

text
You are a data efficiency expert. Review the current `summary_json` output produced by `run_codex_task.sh`. Suggest a minimal schema that includes only essential fields (e.g., exit code, run ID, elapsed time, error message if any). Use short key names (like "exit", "id", "time"). Provide a revised version of the script that emits this optimized JSON and update the documentation to reflect the new schema.
8. Model Tier Integrator
Role: Add --tier flag and map to specific Codex models.

Focus: Argument parsing, mapping logic, passing model to Codex.

Model Tier: Low

Sample Creation Prompt:

text
You are a CLI tool developer. Modify `run_codex_task.sh` to accept a `--tier` argument with values `low`, `medium`, `high`. Based on the tier, set an environment variable or pass a `--model` argument to Codex using a simple mapping (e.g., low → "gpt-3.5-turbo", medium → "gpt-4o-mini", high → "gpt-4o"). If no tier is given, default to `low`. Ensure the argument is passed correctly even when extra args are given after `--`. Provide the updated script.
9. Python Post‑processor
Role: Create example Python scripts that replace LLM calls for deterministic post‑processing.

Focus: Parsing Codex output, extracting tables, generating summaries.

Model Tier: Low

Sample Creation Prompt:

text
You are a Python developer. Write a script `scripts/extract_table.py` that reads a Codex output from stdin (or a file), looks for markdown tables, and outputs a condensed JSON representation. Include command‑line options for input/output files. Add a shebang and make it executable. Provide a brief README section on how to use it as a post‑processor to avoid an extra LLM call.
10. Job Queue Designer
Role: Architect a lightweight job queue with a simple web dashboard.

Focus: SQLite or file‑based queue, status tracking, static HTML/JS dashboard.

Model Tier: Medium (for frontend code and integration)

Sample Creation Prompt:

text
You are a full‑stack developer. Design a minimal job queue system for Codex tasks:
- Use SQLite to store jobs with fields: id, task, status (pending/running/completed/failed), created_at, completed_at, result_path.
- Modify `run_codex_task.sh` to insert a job at start and update it on completion.
- Create a simple Python HTTP server (`server.py`) that serves a static HTML dashboard and a JSON API to list jobs.
- The dashboard (HTML + JavaScript) fetches jobs from the API and displays them with auto‑refresh.
Keep everything lightweight (no frameworks). Provide all code and instructions.
11. Webhook Signer
Role: Implement HMAC signature for webhook payloads to ensure authenticity.

Focus: Signing JSON with a shared secret, adding signature header.

Model Tier: Low

Sample Creation Prompt:

text
You are a security‑minded developer. Enhance `notify_claude_hook.sh` to sign the JSON payload using HMAC‑SHA256 with a secret read from the environment variable `WEBHOOK_SECRET`. Add the signature in a header `X-Signature`. Also modify the script to accept a `--secret` flag or use the env var. Update the documentation to explain how receivers can verify the signature. Provide the revised script.
12. Self‑Diagnosis Creator
Role: Build a --doctor flag that checks system dependencies and configuration.

Focus: Checking for commands, environment variables, connectivity, permissions.

Model Tier: Low

Sample Creation Prompt:

text
You are a diagnostic tool developer. Add a `--doctor` flag to `run_codex_task.sh` that performs the following checks and prints a report:
- Are required commands (`codex`, `jq`, `git`, etc.) installed?
- Are required environment variables (e.g., `CODEX_API_KEY`) set?
- Is the repo path valid and readable?
- Can Codex be reached (e.g., by running a simple test command)?
- Are temporary directories writable?
Output a clear pass/fail with suggestions for fixing issues. Implement this as a separate function and call it when `--doctor` is present.
These subagents can be instantiated in parallel by feeding the appropriate prompts to an LLM (or to different instances). The outputs can then be integrated by a human or by a “coordinator agent” that merges changes. This approach maximizes efficiency while keeping AI costs low by using the smallest suitable models for each specialized task.
## Recommended Subagents for invoke-codex-from-claude

| Agent Name | Coverage | Instruction Link |
| --- | --- | --- |
| `phase1-shield` | Critical fixes (C1–C5) around secrets, error handling, testing, and idempotent install/uninstall flows | ./.claude/agents/team/phase1-shield.md |
| `phase2-optimizer` | Leaning on Phase 2 tasks (L1–L3, L5) for caching, summary schema, tier selection, and sample post-processing | ./.claude/agents/team/phase2-optimizer.md |
| `phase3-polisher` | Phase 3 polish (N1–N5) that builds dashboards, summaries, webhook signing, doctor mode, and contribution docs | ./.claude/agents/team/phase3-polisher.md |

Each agent should follow its instruction file for context, reference the go-live plan for dependencies, and coordinate via git branches before merging.
