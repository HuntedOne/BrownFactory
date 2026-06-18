#!/bin/bash
# SAFETY hook. Registered on PreToolUse for Bash, Write, and Edit.
# Enforces the brownfield guardrails as machinery, not just prompt wishes:
#   - Git safety: no `push`, no `--force`, no switching onto main/master.
#   - The harness config (.claude/) is never editable by an agent.
#   - Code under review (sandbox/) is editable ONLY by the implementer.
#   - The Mentor (when tagged) may only write guidance.md / its own journal.
# Blocking convention: exit 2 blocks the tool call and shows stderr to the agent; exit 0 allows.

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/_common.sh"

INPUT=$(cat)
PROJ="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROLE="$(agent_role)"
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null)

block() { echo "BLOCKED by protect.sh: $1" >&2; exit 2; }

# ---- Git safety (Bash) -------------------------------------------------------
if [ "$TOOL" = "Bash" ]; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
  if printf '%s' "$CMD" | grep -Eq '\bgit\b' && printf '%s' "$CMD" | grep -Eq '\bpush\b'; then
    block "git push is not allowed — review changes locally on the branch, then merge yourself."
  fi
  if printf '%s' "$CMD" | grep -Eq -- '--force|--force-with-lease' ; then
    block "force operations are not allowed."
  fi
  if printf '%s' "$CMD" | grep -Eq '\bgit\b' && printf '%s' "$CMD" | grep -Eq '(checkout|switch)[[:space:]]+(main|master)\b'; then
    block "switching onto main/master is not allowed — work stays on the review branch."
  fi
  exit 0
fi

# ---- Write/Edit scoping ------------------------------------------------------
if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ]; then
  FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
  [ -z "$FILE" ] && exit 0
  case "$FILE" in
    /*) ABS="$FILE" ;;
    *)  ABS="$PROJ/$FILE" ;;
  esac

  # Never let an agent rewrite the harness itself.
  case "$ABS" in
    "$PROJ/.claude/"*) block "agents may not modify the harness config (.claude/)." ;;
  esac

  # Code under review: only the implementer may change it.
  case "$ABS" in
    "$PROJ/sandbox/"*)
      [ "$ROLE" = "implementer" ] || block "only the implementer may modify sandbox code (role=$ROLE)."
      ;;
  esac

  # Mentor (when explicitly tagged) is limited to its guidance + journal.
  if [ "$ROLE" = "mentor" ]; then
    case "$ABS" in
      */guidance.md|*/logs/journals/mentor.md) : ;;
      *) block "the mentor may only write guidance.md (attempted: $ABS)." ;;
    esac
  fi

  exit 0
fi

exit 0
