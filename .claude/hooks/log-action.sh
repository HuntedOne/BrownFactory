#!/bin/bash
# LAYER 2 logging. Registered on PreToolUse and PostToolUse for ALL tools.
# Appends one structured JSONL line per tool call to the active run's actions.jsonl, tagged with
# which agent acted. This is the uniform, greppable audit trail of every ACTION any agent took.
# Never blocks (always exit 0).

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/_common.sh"

INPUT=$(cat)
RUN_DIR="$(resolve_run_dir)"
LOGDIR="$RUN_DIR/logs"
mkdir -p "$LOGDIR"

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "?"' 2>/dev/null)
TOOL=$(printf '%s'  "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null)

# Compact detail: the file path and/or command involved, if any.
DETAIL=$(printf '%s' "$INPUT" | jq -c '{
  file: (.tool_input.file_path // .tool_input.path // null),
  cmd:  (.tool_input.command // null)
}' 2>/dev/null)
[ -z "$DETAIL" ] && DETAIL='null'

jq -nc \
  --arg ts "$(now_ts)" \
  --arg agent "$(agent_role)" \
  --arg event "$EVENT" \
  --arg tool "$TOOL" \
  --argjson detail "$DETAIL" \
  '{ts:$ts, agent:$agent, event:$event, tool:$tool, detail:$detail}' \
  >> "$LOGDIR/actions.jsonl" 2>/dev/null

exit 0
