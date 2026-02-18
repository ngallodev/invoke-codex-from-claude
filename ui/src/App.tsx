import { RUNS, EVENTS } from "./mockData";
import type { RunStatus } from "./types";

function badgeClass(status: RunStatus): string {
  const map: Record<RunStatus, string> = {
    queued: "s-queued",
    claimed: "s-claimed",
    running: "s-running",
    waiting_approval: "s-waiting",
    retry_scheduled: "s-retry",
    completed: "s-completed",
    failed: "s-failed",
    canceled: "s-canceled"
  };
  return `status ${map[status]}`;
}

export function App() {
  const totalTokens = RUNS.reduce((n, r) => n + r.tokens, 0);
  const totalCost = RUNS.reduce((n, r) => n + r.costUsd, 0);
  const failures = RUNS.filter((r) => r.status === "failed").length;

  return (
    <main className="page">
      <header className="hero">
        <h1>Multi-Agent Orchestration Control Plane</h1>
        <p>Queue visibility, run timelines, approvals, and cost/error telemetry.</p>
      </header>

      <section className="metrics">
        <article><h2>Tokens</h2><p>{totalTokens.toLocaleString()}</p></article>
        <article><h2>Cost (USD)</h2><p>${totalCost.toFixed(2)}</p></article>
        <article><h2>Failures</h2><p>{failures}</p></article>
      </section>

      <section className="panel">
        <h2>Run Queue</h2>
        <table>
          <thead>
            <tr><th>Run</th><th>Repo</th><th>Agent</th><th>Status</th><th>Tokens</th><th>Cost</th></tr>
          </thead>
          <tbody>
            {RUNS.map((run) => (
              <tr key={run.id}>
                <td>{run.id}</td>
                <td>{run.repo}</td>
                <td>{run.agent}</td>
                <td><span className={badgeClass(run.status)}>{run.status}</span></td>
                <td>{run.tokens.toLocaleString()}</td>
                <td>${run.costUsd.toFixed(2)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section className="panel">
        <h2>Recent Timeline Events</h2>
        <ul className="timeline">
          {EVENTS.map((evt) => (
            <li key={evt.id}>
              <strong>{evt.label}</strong>
              <span>{evt.runId}</span>
              <time>{evt.at}</time>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}
