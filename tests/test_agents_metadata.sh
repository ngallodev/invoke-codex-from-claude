#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent_dir="$root_dir/.claude/agents/team"

required_agents=(
  security-hardener
  bash-error-handling-specialist
  test-generator-shell
  installation-engineer
  technical-writer
  caching-architect
  json-minimizer
  model-tier-integrator
  python-post-processor
  job-queue-designer
  webhook-signer
  self-diagnosis-creator
)

required_metrics=(
  "input_tokens"
  "output_tokens"
  "cached_tokens"
  "context_tokens"
  "elapsed_seconds"
)

for agent in "${required_agents[@]}"; do
  path="$agent_dir/${agent}.md"
  [[ -f "$path" ]] || { echo "Missing agent file: $path" >&2; exit 1; }
  # Ensure telemetry keys are documented to keep reporting consistent.
  for metric in "${required_metrics[@]}"; do
    grep -q "$metric" "$path" || { echo "Missing metric '$metric' in $path" >&2; exit 1; }
  done
  # Basic sanity: name field present.
  grep -q "^name: ${agent}$" "$path" || { echo "Missing name field in $path" >&2; exit 1; }
done

echo "All agent instruction files include telemetry requirements and names."
