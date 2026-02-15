#!/usr/bin/env bash
set -euo pipefail

# Mock Gemini CLI for testing scripts/run_gemini_task.sh

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cd)
      CWD="${2:-}"
      shift 2
      ;;
    --prompt)
      PROMPT="${2:-}"
      shift 2
      ;;
    --resume)
      RESUME="${2:-}"
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

echo "fake_gemini_cwd=${CWD:-unknown}"
echo "fake_gemini_prompt=${PROMPT:-unknown}"
echo "fake_gemini_resume=${RESUME:-none}"
echo "fake_gemini_model=${MODEL:-default}"

if [[ "${MODEL:-}" == "gemini-2.0-flash" ]]; then
  echo "prompt_tokens: 100"
  echo "completion_tokens: 50"
  echo "usd: 0.005"
else
  echo "input_tokens: 1000"
  echo "output_tokens: 500"
  echo "cost: 0.05"
fi

# Simulate session ID emission
echo "Session ID: 12345678-1234-1234-1234-1234567890ab"
