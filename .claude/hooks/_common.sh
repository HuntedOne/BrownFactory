#!/bin/bash
# Shared helpers for the logging/protection hooks. Sourced by the other hook scripts.

# Resolve the active run directory (absolute). review.sh exports RUN_DIR and also writes a pointer
# file so interactively-launched agents (e.g. the Mentor) still log to the right place.
resolve_run_dir() {
  local proj="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  if [ -n "${RUN_DIR:-}" ]; then
    printf '%s' "$RUN_DIR"
  elif [ -f "$proj/.claude/.current-run" ]; then
    cat "$proj/.claude/.current-run"
  else
    printf '%s' "$proj/runs/_adhoc"
  fi
}

# Which agent is acting. review.sh exports AGENT_ROLE for headless agents.
agent_role() { printf '%s' "${AGENT_ROLE:-interactive}"; }

# UTC timestamp (the shell `date`, not JS — allowed).
now_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
