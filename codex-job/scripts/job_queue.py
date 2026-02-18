#!/usr/bin/env python3
"""
Lightweight SQLite-backed job queue for Codex runs.

Columns: id, task, status, repo, run_id, session_id, mode, tier, cache_status,
created_at, started_at, completed_at, result_path, log_path, meta_path,
summary_path, error.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Optional

DEFAULT_LIMIT = 200


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task TEXT NOT NULL,
            status TEXT NOT NULL,
            repo TEXT,
            run_id TEXT,
            session_id TEXT,
            mode TEXT,
            tier TEXT,
            cache_status TEXT,
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
            started_at TEXT,
            completed_at TEXT,
            result_path TEXT,
            log_path TEXT,
            meta_path TEXT,
            summary_path TEXT,
            error TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at DESC, id DESC);
        CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
        """
    )
    conn.commit()


@dataclass
class Job:
    id: int
    task: str
    status: str
    repo: Optional[str] = None
    run_id: Optional[str] = None
    session_id: Optional[str] = None
    mode: Optional[str] = None
    tier: Optional[str] = None
    cache_status: Optional[str] = None
    created_at: Optional[str] = None
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    result_path: Optional[str] = None
    log_path: Optional[str] = None
    meta_path: Optional[str] = None
    summary_path: Optional[str] = None
    error: Optional[str] = None
    elapsed_seconds: Optional[int] = field(default=None)

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "Job":
        started = row["started_at"]
        completed = row["completed_at"]
        elapsed = None
        try:
            if started and completed:
                start_epoch = datetime.fromisoformat(started.replace("Z", "+00:00")).timestamp()
                end_epoch = datetime.fromisoformat(completed.replace("Z", "+00:00")).timestamp()
                elapsed = int(end_epoch - start_epoch)
        except Exception:
            elapsed = None

        return cls(
            id=row["id"],
            task=row["task"],
            status=row["status"],
            repo=row["repo"],
            run_id=row["run_id"],
            session_id=row["session_id"],
            mode=row["mode"],
            tier=row["tier"],
            cache_status=row["cache_status"],
            created_at=row["created_at"],
            started_at=started,
            completed_at=completed,
            result_path=row["result_path"],
            log_path=row["log_path"],
            meta_path=row["meta_path"],
            summary_path=row["summary_path"],
            error=row["error"],
            elapsed_seconds=elapsed,
        )

    def to_dict(self) -> dict:
        return asdict(self)


def enqueue(
    db_path: Path,
    task: str,
    status: str,
    repo: Optional[str],
    run_id: Optional[str],
    session_id: Optional[str],
    mode: Optional[str],
    tier: Optional[str],
    cache_status: Optional[str],
    result_path: Optional[str],
    log_path: Optional[str],
    meta_path: Optional[str],
    summary_path: Optional[str],
    started_at: Optional[str],
) -> int:
    conn = connect(db_path)
    ensure_schema(conn)
    now_iso = utc_now()
    started_iso = started_at or now_iso if status != "pending" else None
    cur = conn.execute(
        """
        INSERT INTO jobs (
            task, status, repo, run_id, session_id, mode, tier, cache_status,
            created_at, started_at, result_path, log_path, meta_path, summary_path
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            task,
            status,
            repo,
            run_id,
            session_id,
            mode,
            tier,
            cache_status,
            now_iso,
            started_iso,
            result_path,
            log_path,
            meta_path,
            summary_path,
        ),
    )
    conn.commit()
    return int(cur.lastrowid)


def update_job(
    db_path: Path,
    job_id: int,
    status: Optional[str],
    exit_code: Optional[int],
    session_id: Optional[str],
    completed_at: Optional[str],
    result_path: Optional[str],
    log_path: Optional[str],
    meta_path: Optional[str],
    summary_path: Optional[str],
    cache_status: Optional[str],
    error: Optional[str],
) -> None:
    conn = connect(db_path)
    ensure_schema(conn)
    fields: list[str] = []
    values: list[object] = []

    mapping = {
        "status": status,
        "session_id": session_id,
        "completed_at": completed_at or utc_now() if status in {"completed", "failed", "cached"} else completed_at,
        "result_path": result_path,
        "log_path": log_path,
        "meta_path": meta_path,
        "summary_path": summary_path,
        "cache_status": cache_status,
        "error": error,
    }
    if exit_code is not None:
        mapping["error"] = error or ("" if exit_code == 0 else f"codex exited with {exit_code}")

    for key, val in mapping.items():
        if val is not None:
            fields.append(f"{key}=?")
            values.append(val)

    if not fields:
        return

    values.append(job_id)
    conn.execute(f"UPDATE jobs SET {', '.join(fields)} WHERE id=?", values)
    conn.commit()


def fetch_jobs(db_path: Path, limit: int = DEFAULT_LIMIT) -> list[Job]:
    conn = connect(db_path)
    ensure_schema(conn)
    rows = conn.execute(
        """
        SELECT id, task, status, repo, run_id, session_id, mode, tier, cache_status,
               created_at, started_at, completed_at, result_path, log_path, meta_path,
               summary_path, error
        FROM jobs
        ORDER BY COALESCE(started_at, created_at) DESC, id DESC
        LIMIT ?
        """,
        (limit,),
    ).fetchall()
    return [Job.from_row(r) for r in rows]


def emit_json(data: object) -> None:
    print(json.dumps(data, ensure_ascii=True, indent=2))


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SQLite-backed job queue utilities.")
    parser.add_argument("--db", default="runs/job_queue.sqlite3", help="Path to job queue database")

    sub = parser.add_subparsers(dest="command", required=True)

    enqueue_parser = sub.add_parser("enqueue", help="Insert a new job entry")
    enqueue_parser.add_argument("--task", required=True, help="Task text")
    enqueue_parser.add_argument("--status", default="pending", help="Status (pending/running/completed/failed/cached)")
    enqueue_parser.add_argument("--repo")
    enqueue_parser.add_argument("--run-id")
    enqueue_parser.add_argument("--session-id")
    enqueue_parser.add_argument("--mode")
    enqueue_parser.add_argument("--tier")
    enqueue_parser.add_argument("--cache")
    enqueue_parser.add_argument("--result-path")
    enqueue_parser.add_argument("--log-path")
    enqueue_parser.add_argument("--meta-path")
    enqueue_parser.add_argument("--summary-path")
    enqueue_parser.add_argument("--started-at")

    update_parser = sub.add_parser("update", help="Update an existing job")
    update_parser.add_argument("--id", type=int, required=True, help="Job id")
    update_parser.add_argument("--status")
    update_parser.add_argument("--exit-code", type=int)
    update_parser.add_argument("--session-id")
    update_parser.add_argument("--completed-at")
    update_parser.add_argument("--result-path")
    update_parser.add_argument("--log-path")
    update_parser.add_argument("--meta-path")
    update_parser.add_argument("--summary-path")
    update_parser.add_argument("--cache")
    update_parser.add_argument("--error")

    list_parser = sub.add_parser("list", help="List recent jobs")
    list_parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT)

    sub.add_parser("init", help="Create the database if needed")

    return parser.parse_args(list(argv))


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    db_path = Path(args.db)

    if args.command == "enqueue":
        job_id = enqueue(
            db_path=db_path,
            task=args.task,
            status=args.status,
            repo=args.repo,
            run_id=args.run_id,
            session_id=args.session_id,
            mode=args.mode,
            tier=args.tier,
            cache_status=args.cache,
            result_path=args.result_path,
            log_path=args.log_path,
            meta_path=args.meta_path,
            summary_path=args.summary_path,
            started_at=args.started_at,
        )
        print(job_id)
        return 0

    if args.command == "update":
        update_job(
            db_path=db_path,
            job_id=args.id,
            status=args.status,
            exit_code=args.exit_code,
            session_id=args.session_id,
            completed_at=args.completed_at,
            result_path=args.result_path,
            log_path=args.log_path,
            meta_path=args.meta_path,
            summary_path=args.summary_path,
            cache_status=args.cache,
            error=args.error,
        )
        return 0

    if args.command == "list":
        emit_json({"jobs": [job.to_dict() for job in fetch_jobs(db_path, args.limit)]})
        return 0

    if args.command == "init":
        conn = connect(db_path)
        ensure_schema(conn)
        emit_json({"status": "ok", "db": str(db_path)})
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
