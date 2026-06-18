#!/bin/bash
# LAYER 2 logging. Registered on SessionStart / Stop / SessionEnd.
# Writes boundary markers into the action log so you can see where each agent's session began and
# ended in the unified timeline. Never blocks.

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/_common.sh"

INPUT=$(cat)
RUN_DIR="$(resolve_run_dir)"
LOGDIR="$RUN_DIR/logs"
mkdir -p "$LOGDIR"

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "Session?"' 2>/dev/null)
SID=$(printf '%s'   "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)

jq -nc \
  --arg ts "$(now_ts)" \
  --arg agent "$(agent_role)" \
  --arg event "$EVENT" \
  --arg session "$SID" \
  '{ts:$ts, agent:$agent, event:$event, session:$session}' \
  >> "$LOGDIR/actions.jsonl" 2>/dev/null

exit 0
