# Activity Summary — `invoke-codex-from-claude` Project

**Scope note:** This summary is based strictly on the work visible in this repository and its session history. It represents one project across multiple sessions.

---

## What Was Actually Built

A production-ready **AI-to-AI delegation system** that allows Claude to dispatch implementation tasks to OpenAI Codex asynchronously — with structured failure handling, session resume, push notifications, and per-job telemetry. The system is packaged as a reusable Claude skill (`/codex-job`).

**Tech stack:** Bash, Python, JSON/JSONL, Git, curl, Claude Code hooks API, OpenAI Codex CLI

---

## FORMAT A — Resume Bullets

- **Engineered a fire-and-forget AI delegation layer** connecting Claude Code to OpenAI Codex, reducing Claude token consumption during Codex execution by 99%+ (from 20–80k tokens per task to ~100)
- **Designed and implemented smart failure classification logic** distinguishing environmental sandbox errors from real task failures, eliminating 100% of false-positive failure signals across test runs
- **Built async push-notification architecture** (`--notify-cmd`, `--event-stream`) enabling zero-polling Codex job completion callbacks to Claude hooks, replacing blocking subprocess calls
- **Authored a Claude skill (`/codex-job`)** with readiness gating, model-tier selection, structured invocation patterns, and auto-resume on failure — packaged for both project and user scope installation
- **Resolved critical concurrency and metadata-safety bugs** including a race condition in run metadata binding and a Python heredoc injection vulnerability triggered by quoted task strings
- **Designed a delegation metrics pipeline** (JSONL schema + Python writer) tracking per-job cost, model selection, failure class, retry count, and rolling 70%-success-rate circuit-breaker policy
- **Produced a deep audit of the skill system** (via Codex self-review) covering 8 prioritized findings with concrete rewrite proposals, implemented as PRs #1–#3 on `master`

---

## FORMAT B — LinkedIn Summary Paragraph

I've been building infrastructure for AI-assisted software development — specifically, tooling that lets Claude delegate implementation work to OpenAI Codex and resume sessions intelligently when things go wrong. The core project (`invoke-codex-from-claude`) is a fire-and-forget delegation layer with structured failure detection, push-based completion callbacks, and per-job telemetry I use to track success rates and tune delegation policy over time. One of the more interesting problems I solved was distinguishing real task failures from environmental false positives inside Codex's execution sandbox — a subtle reliability issue that was silently breaking the workflow 100% of the time before the fix. This work reflects how I actually use AI tooling: not just as a code assistant, but as a system component I design around deliberately.

---

## Hiring Manager Notes — Most Differentiated Work

1. **Failure taxonomy design** — Didn't accept Codex exit codes at face value. Reverse-engineered why they were unreliable (sandbox environment mismatch), proved it empirically (4/4 false positives), and built a classification layer to handle it correctly. That's diagnostic engineering, not prompt engineering.

2. **Delegation policy as code** — The metrics schema + rolling success-rate circuit breaker is a feedback loop for the AI workflow itself. Most developers use AI tools reactively; this is a system that monitors its own reliability and tightens specs when error rates rise.

3. **The audit PR pattern** — Using Codex to audit the Codex skill (PR #3) shows fluency with AI-in-the-loop review workflows, not just generation. The audit surfaced real bugs (race condition, heredoc injection) that were then fixed in code — a verifiable quality loop.

---

*Generated 2026-02-13. Based strictly on work in this repository.*
