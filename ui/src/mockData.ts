import type { RunSummary, TimelineEvent } from "./types";

export const RUNS: RunSummary[] = [
  {
    id: "run_1042",
    repo: "payments-api",
    agent: "codex:gpt-5",
    status: "running",
    tokens: 12890,
    costUsd: 0.91,
    updatedAt: "2026-02-18T10:34:00Z"
  },
  {
    id: "run_1041",
    repo: "infra-iac",
    agent: "claude:sonnet",
    status: "waiting_approval",
    tokens: 9230,
    costUsd: 0.66,
    updatedAt: "2026-02-18T10:33:00Z"
  },
  {
    id: "run_1040",
    repo: "frontend-web",
    agent: "gemini:2.5-pro",
    status: "failed",
    tokens: 6820,
    costUsd: 0.37,
    updatedAt: "2026-02-18T10:29:00Z"
  }
];

export const EVENTS: TimelineEvent[] = [
  { id: "evt1", runId: "run_1042", kind: "run", label: "run.started", at: "2026-02-18T10:31:30Z" },
  { id: "evt2", runId: "run_1042", kind: "artifact", label: "artifact.recorded (summary)", at: "2026-02-18T10:33:02Z" },
  { id: "evt3", runId: "run_1041", kind: "policy", label: "policy.evaluated -> require_approval", at: "2026-02-18T10:32:51Z" },
  { id: "evt4", runId: "run_1040", kind: "system", label: "system.error (adapter timeout)", at: "2026-02-18T10:29:41Z" }
];
