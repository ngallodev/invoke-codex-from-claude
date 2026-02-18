#!/usr/bin/env python3
"""
Serve the Codex job queue as a tiny JSON API plus a static dashboard.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
import urllib.parse
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional

import job_queue


def discover_dashboard_path(explicit: Optional[str]) -> Optional[Path]:
    if explicit:
        path = Path(explicit)
        return path if path.exists() else None

    script_dir = Path(__file__).resolve().parent
    candidates = [
        script_dir.parent / "assets" / "job-dashboard.html",
        script_dir.parent.parent / "codex-job" / "assets" / "job-dashboard.html",
        script_dir.parent.parent / ".claude" / "skills" / "codex-job" / "assets" / "job-dashboard.html",
    ]
    for cand in candidates:
        if cand.exists():
            return cand
    return None


def load_dashboard_html(path: Optional[Path]) -> str:
    if path and path.exists():
        try:
            return path.read_text(encoding="utf-8")
        except Exception:
            pass
    return """
<!doctype html>
<meta charset="utf-8">
<title>Codex Job Queue</title>
<style>
  :root { font-family: 'Segoe UI', 'IBM Plex Sans', system-ui, sans-serif; color: #e8ecf1; background: #0b1021; }
  body { margin: 0; padding: 1.5rem; background: radial-gradient(circle at 20% 20%, rgba(120,92,255,0.15), transparent 35%), #0b1021; }
  header { display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem; }
  h1 { margin:0; font-size:1.25rem; letter-spacing:0.02em; }
  .pill { padding:0.35rem 0.75rem; border-radius:999px; background:#1c2035; border:1px solid #2f3658; font-size:0.85rem; }
  table { width:100%; border-collapse:collapse; margin-top:0.5rem; background:#0f172a; border:1px solid #1f2a44; }
  th, td { padding:0.55rem 0.65rem; text-align:left; font-size:0.92rem; }
  th { background:#111b33; color:#9fb5ff; border-bottom:1px solid #1f2a44; }
  tr:nth-child(every) { background:#0f172a; }
  tr + tr td { border-top:1px solid #1b2440; }
  .status { padding:0.18rem 0.55rem; border-radius:999px; font-size:0.8rem; text-transform:capitalize; border:1px solid transparent; display:inline-block; }
  .status.running { background:#1c2b45; border-color:#274777; color:#a7c7ff; }
  .status.completed { background:#113322; border-color:#1c5c3f; color:#8fe8b0; }
  .status.failed { background:#381622; border-color:#66293d; color:#f4a1b2; }
  .status.cached { background:#2a2538; border-color:#493a6e; color:#c9b7ff; }
  .status.pending { background:#2c2f3b; border-color:#454b5d; color:#d3d9ea; }
  .grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr)); gap:0.75rem; margin-top:0.5rem; }
  .card { background:#0f172a; border:1px solid #1f2a44; border-radius:12px; padding:0.9rem; }
  .card h2 { margin:0 0 0.35rem; font-size:0.95rem; color:#9fb5ff; }
  .muted { color:#92a2c6; font-size:0.9rem; }
  .small { font-size:0.8rem; color:#7789b0; }
</style>
<body>
  <header>
    <div>
      <h1>Codex Job Queue</h1>
      <div class="small" id="db-path"></div>
    </div>
    <div class="pill" id="refresh-label">loading…</div>
  </header>
  <div class="grid" id="totals"></div>
  <table>
    <thead>
      <tr>
        <th>ID</th><th>Status</th><th>Task</th><th>Repo</th><th>Run</th><th>Session</th><th>Started</th><th>Ended</th><th>Cache</th>
      </tr>
    </thead>
    <tbody id="jobs-body"></tbody>
  </table>
  <script>
    const body = document.getElementById('jobs-body');
    const refreshLabel = document.getElementById('refresh-label');
    const totals = document.getElementById('totals');
    const dbPath = document.getElementById('db-path');

    const format = (iso) => iso ? new Date(iso).toLocaleString() : '—';

    function renderTotals(jobs) {
      const counts = jobs.reduce((acc, j) => { acc[j.status] = (acc[j.status] || 0) + 1; return acc; }, {});
      totals.innerHTML = Object.entries(counts).map(([status, count]) => `
        <div class="card">
          <h2>${status}</h2>
          <div class="muted">${count} job${count === 1 ? '' : 's'}</div>
        </div>
      `).join('') || '<div class="card"><h2>No Jobs</h2><div class="muted">Queue is empty.</div></div>';
    }

    function renderRows(jobs) {
      body.innerHTML = jobs.map(j => `
        <tr>
          <td>${j.id}</td>
          <td><span class="status ${j.status}">${j.status}</span></td>
          <td>${j.task || ''}</td>
          <td>${j.repo || ''}</td>
          <td>${j.run_id || ''}</td>
          <td>${j.session_id || ''}</td>
          <td>${format(j.started_at || j.created_at)}</td>
          <td>${format(j.completed_at)}</td>
          <td>${j.cache_status || ''}</td>
        </tr>
      `).join('');
    }

    async function load() {
      try {
        refreshLabel.textContent = 'refreshing…';
        const res = await fetch('/api/jobs');
        if (!res.ok) throw new Error('bad response');
        const data = await res.json();
        renderRows(data.jobs || []);
        renderTotals(data.jobs || []);
        refreshLabel.textContent = `updated ${new Date(data.generated_at).toLocaleTimeString()}`;
        dbPath.textContent = data.db_path || '';
      } catch (err) {
        refreshLabel.textContent = 'error loading';
        console.error(err);
      }
    }

    load();
    setInterval(load, 5000);
  </script>
</body>
"""


class QueueHandler(BaseHTTPRequestHandler):
    server: "QueueHTTPServer"

    def log_message(self, fmt: str, *args) -> None:  # pragma: no cover - keep logs minimal
        sys.stderr.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), fmt % args))

    def _send_json(self, payload: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html: str) -> None:
        body = html.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - required signature
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("/", "/dashboard", "/index.html"):
            self._send_html(self.server.dashboard_html)
            return

        if parsed.path.startswith("/api/jobs"):
            query = urllib.parse.parse_qs(parsed.query)
            limit = self.server.default_limit
            if "limit" in query:
                try:
                    limit = max(1, int(query["limit"][0]))
                except Exception:
                    pass
            jobs = [job.to_dict() for job in job_queue.fetch_jobs(self.server.db_path, limit)]
            payload = {
                "jobs": jobs,
                "generated_at": job_queue.utc_now(),
                "db_path": str(self.server.db_path),
            }
            self._send_json(payload)
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Not Found")


class QueueHTTPServer(ThreadingHTTPServer):
    def __init__(self, host: str, port: int, db_path: Path, dashboard_html: str, default_limit: int):
        super().__init__((host, port), QueueHandler)
        self.db_path = db_path
        self.dashboard_html = dashboard_html
        self.default_limit = default_limit


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Serve the job queue dashboard + API.")
    parser.add_argument("--db", default="runs/job_queue.sqlite3", help="Path to queue database")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7801)
    parser.add_argument("--limit", type=int, default=job_queue.DEFAULT_LIMIT, help="Default API limit")
    parser.add_argument("--dashboard", help="Path to dashboard HTML")
    parser.add_argument("--open", action="store_true", help="Open the dashboard in the browser")
    args = parser.parse_args(argv)

    db_path = Path(args.db)
    dashboard_path = discover_dashboard_path(args.dashboard)
    dashboard_html = load_dashboard_html(dashboard_path)

    # Ensure schema exists up-front so the API works on first request.
    conn = job_queue.connect(db_path)
    job_queue.ensure_schema(conn)

    server = QueueHTTPServer(args.host, args.port, db_path, dashboard_html, args.limit)

    if args.open:
        url = f"http://{args.host}:{args.port}/"
        threading.Thread(target=lambda: (time.sleep(0.4), webbrowser.open(url)), daemon=True).start()

    print(f"Job queue server listening on http://{args.host}:{args.port} (db: {db_path})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
