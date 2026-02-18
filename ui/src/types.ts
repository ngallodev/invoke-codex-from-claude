export type RunStatus =
  | "queued"
  | "claimed"
  | "running"
  | "waiting_approval"
  | "retry_scheduled"
  | "completed"
  | "failed"
  | "canceled";

export type RunSummary = {
  id: string;
  repo: string;
  agent: string;
  status: RunStatus;
  tokens: number;
  costUsd: number;
  updatedAt: string;
};

export type TimelineEvent = {
  id: string;
  runId: string;
  kind: "run" | "policy" | "artifact" | "system";
  label: string;
  at: string;
};
