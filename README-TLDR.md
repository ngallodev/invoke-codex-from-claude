# invoke-codex-from-claude (TLDR)

Fast path to install, configure, and run.

## 1) Install

Project-local install:

```bash
./install.sh --scope project
```

Optional (deferred/experimental queue+dashboard scripts):

```bash
./install.sh --scope project --include-experimental
```

Preview only (no changes):

```bash
./install.sh --scope project --dry-run
```

## 2) Set required env var

```bash
export CODEX_API_KEY="your-token"
```

If you use `--notify-cmd`, also set one signing secret:

```bash
export WEBHOOK_SECRET="shared-secret"
# or
export CODEX_WEBHOOK_SECRET="shared-secret"
```

## 3) Run a task

Canonical runner:

```bash
codex-job/scripts/run_codex_task.sh \
  --repo . \
  --task "Fix failing tests"
```

Convenience wrapper (delegates to canonical runner):

```bash
scripts/run_codex_task.sh --repo . --task "Fix failing tests"
```

Review wrapper (auto-review on real failures, one-line summary enabled by default):

```bash
codex-job/scripts/invoke_codex_with_review.sh --repo . --task "Fix failing tests"
```

## 4) Common options

- `--tier low|medium|high` (default `low`)
- `--no-cache` bypass cache lookup/store for this run
- `--cache-dir <path>` override cache location
- `--summarize` print a one-line run summary after completion
- `--json-out <path>` write summary JSON to a specific path
- `--event-stream <path>` append run events as JSON lines
- `--notify-cmd "<cmd>"` send each event JSON to a command on stdin

## 5) Output files

By default under `./runs/`:

- `codex-run-<id>.log`
- `codex-run-<id>.meta.json`
- `codex-run-<id>.summary.json`

Summary JSON uses a lean schema (`id`, `exit`, `ok`, `tok`, etc.) with a nested `legacy` block for compatibility.

## 6) Doctor mode

Check environment without running a task:

```bash
codex-job/scripts/run_codex_task.sh --doctor --repo .
```

## 7) Uninstall

```bash
./uninstall.sh --scope project
```

Preview only:

```bash
./uninstall.sh --scope project --dry-run
```
