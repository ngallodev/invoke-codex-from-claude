#!/usr/bin/env python3
"""Thin wrapper that delegates to the canonical parser under codex-job/scripts."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "codex-job" / "scripts" / "parse_codex_run.py"

if not TARGET.exists():
    print(f"Error: canonical parser not found at {TARGET}", file=sys.stderr)
    raise SystemExit(2)

cmd = [sys.executable, str(TARGET), *sys.argv[1:]]
raise SystemExit(subprocess.call(cmd, env=os.environ.copy()))
