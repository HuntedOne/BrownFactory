#!/bin/bash
# LAYER 2 logging. Registered on UserPromptSubmit.
# Records the task each agent (or the user) was given, so the action trail shows intent, not just
# tool calls. Never blocks.

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/_common.sh"

INPUT=$(cat)
RUN_DIR="$(resolve_run_dir)"
LOGDIR="$RUN_DIR/logs"
mkdir -p "$LOGDIR"

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)

jq -nc \
  --arg ts "$(now_ts)" \
  --arg agent "$(agent_role)" \
  --arg event "UserPromptSubmit" \
  --arg prompt "$PROMPT" \
  '{ts:$ts, agent:$agent, event:$event, prompt:$prompt}' \
  >> "$LOGDIR/actions.jsonl" 2>/dev/null

exit 0
