#!/bin/bash
# review.sh — the four-agent brownfield review orchestrator.
#
#   ./review.sh <local-repo-path | git-url> [run-id]
#
# Flow per run:
#   setup sandbox + baseline  ->  SURVEY  ->  [per iteration:]
#     negotiate plan  ->  ⏸ GATE 1 (you + Mentor)  ->  IMPLEMENT  ->  REVIEW
#     ->  draft next plan  ->  ⏸ GATE 2 (you + Mentor)  ->  loop / stop
#
# Safety: agents work only in a sandbox (git worktree for a local repo, clone for a URL). The
# protect.sh hook blocks push/force/main and restricts who can edit what. Everything an agent
# thinks/does is logged under runs/<run-id>/logs/ (transcripts + actions.jsonl + journals).
#
# Tunables (env): PERM (permission mode, default bypassPermissions — hooks still enforce safety),
#                 MAX_FIX (max NEEDS_WORK retries per iteration, default 2),
#                 SKIP_BASELINE=1 to skip running the baseline test suite.

set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT" || exit 1

TARGET="${1:-}"
RUN_ID="${2:-run-$(date -u +%Y%m%d-%H%M%S)}"
PERM="${PERM:-bypassPermissions}"
MAX_FIX="${MAX_FIX:-2}"

if [ -z "$TARGET" ]; then
  echo "usage: ./review.sh <local-repo-path | git-url> [run-id]"; exit 1
fi

RUN_DIR="$ROOT/runs/$RUN_ID"
SANDBOX="$ROOT/sandbox/$RUN_ID"
TRANSCRIPTS="$RUN_DIR/logs/transcripts"
mkdir -p "$TRANSCRIPTS" "$RUN_DIR/logs/journals" "$RUN_DIR/iterations"

# Pointer so interactively-launched agents (the Mentor) log to / write under this run.
printf '%s' "$RUN_DIR" > "$ROOT/.claude/.current-run"

# --- helpers -----------------------------------------------------------------

# run_agent <role> <transcript-name> <prompt>  — headless agent run, fully logged.
run_agent() {
  local role="$1" name="$2" prompt="$3"
  local tfile="$TRANSCRIPTS/$name.stream.jsonl"
  echo "==> [$role] $name"
  AGENT_ROLE="$role" RUN_DIR="$RUN_DIR" \
    claude --agent "$role" --add-dir "$SANDBOX" --permission-mode "$PERM" \
           --output-format stream-json --verbose -p "$prompt" \
    2>>"$RUN_DIR/logs/errors.log" | tee "$tfile"
  # Return the agent's final text (used for verdicts).
  jq -r 'select(.type=="result") | .result' "$tfile" 2>/dev/null | tail -1
}

# gate <title> <what-to-read>
gate() {
  local title="$1" files="$2"
  cat <<EOF

================  ⏸  $title  ================
Review:
$files

Discuss it with your Mentor (explains the team's decisions, co-drafts your guidance):
   AGENT_ROLE=mentor RUN_DIR="$RUN_DIR" claude --agent mentor --add-dir "$SANDBOX"
   (or run  /mentor  inside an interactive 'claude' session started in $ROOT)

Your guidance is saved to: $RUN_DIR/guidance.md
EOF
  read -rp "Type 'approve' to proceed (anything else stops the run): " ans
  if [ "$ans" != "approve" ]; then echo "Stopped at: $title"; exit 0; fi
}

# --- 1. sandbox --------------------------------------------------------------
echo "==> Setting up sandbox: $SANDBOX"
if [ -e "$SANDBOX" ]; then echo "sandbox already exists; reusing it."; \
elif printf '%s' "$TARGET" | grep -Eq '^(https?://|git@)'; then
  git clone "$TARGET" "$SANDBOX" || { echo "clone failed"; exit 1; }
  git -C "$SANDBOX" checkout -b "review/$RUN_ID" >/dev/null 2>&1
else
  TARGET="$(cd "$TARGET" && pwd)" || { echo "target path not found"; exit 1; }
  git -C "$TARGET" worktree add "$SANDBOX" -b "review/$RUN_ID" \
    || { echo "worktree failed (is the target a git repo?)"; exit 1; }
fi
GIT_SHA="$(git -C "$SANDBOX" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# --- 2. baseline -------------------------------------------------------------
detect_test_cmd() {
  if [ -f "$SANDBOX/package.json" ] && grep -q '"test"' "$SANDBOX/package.json"; then echo "npm test"; \
  elif [ -f "$SANDBOX/pyproject.toml" ] || ls "$SANDBOX"/pytest.ini "$SANDBOX"/tests >/dev/null 2>&1; then echo "pytest -q"; \
  elif [ -f "$SANDBOX/Makefile" ] && grep -q '^test:' "$SANDBOX/Makefile"; then echo "make test"; \
  else echo ""; fi
}
TEST_CMD="$(detect_test_cmd)"
BASE_STATUS="skipped"; BASE_OUT=""
if [ -z "${SKIP_BASELINE:-}" ] && [ -n "$TEST_CMD" ]; then
  echo "==> Baseline: $TEST_CMD"
  BASE_OUT="$( cd "$SANDBOX" && eval "$TEST_CMD" 2>&1 | tail -40 )"
  # shellcheck disable=SC2181
  if [ "${PIPESTATUS[0]:-1}" -eq 0 ]; then BASE_STATUS="pass"; else BASE_STATUS="fail"; fi
fi
jq -n --arg cmd "$TEST_CMD" --arg status "$BASE_STATUS" --arg out "$BASE_OUT" \
  '{test_cmd:$cmd, status:$status, tail:$out}' > "$RUN_DIR/baseline.json"
jq -n --arg target "$TARGET" --arg run "$RUN_ID" --arg sandbox "$SANDBOX" \
      --arg sha "$GIT_SHA" --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg perm "$PERM" \
  '{target:$target, run_id:$run, sandbox:$sandbox, base_sha:$sha, created:$created, permission_mode:$perm}' \
  > "$RUN_DIR/manifest.json"

# --- 3. survey (once) --------------------------------------------------------
run_agent surveyor "01-survey" \
"AUDIT mode. The repo under review is in $SANDBOX. Produce audit.md, findings.json, and \
proposed-path.md in $RUN_DIR per your instructions. Baseline status: $BASE_STATUS ($TEST_CMD)."

# --- 4. iteration loop -------------------------------------------------------
N=1
while grep -q '"resolved": false' "$RUN_DIR/findings.json" 2>/dev/null; do
  IDIR="$RUN_DIR/iterations/$N"; mkdir -p "$IDIR/evidence"
  echo "==================== ITERATION $N ===================="

  # 4a. negotiate the plan
  run_agent surveyor "i${N}-01-propose" \
"PROPOSE NEXT ITERATION mode. Write $IDIR/plan.md for iteration $N: pick the next coherent \
unresolved finding(s) from $RUN_DIR/findings.json. Leave an '## Implementer feasibility' section."
  run_agent implementer "i${N}-02-feasibility" \
"FEASIBILITY pass only — do NOT change any code yet. Read $IDIR/plan.md and the sandbox, then fill \
in the '## Implementer feasibility' section (approach, files, test plan, risks, non-goals)."

  # 4b. GATE 1
  gate "GATE 1 — approve the plan for iteration $N" "  - $IDIR/plan.md"

  # 4c. implement (+ retry on NEEDS_WORK)
  run_agent implementer "i${N}-03-implement" \
"IMPLEMENT per $IDIR/plan.md and $RUN_DIR/guidance.md. Work only in the sandbox branch. Add tests, \
run the full suite, keep the baseline green, write evidence to $IDIR/evidence/, then commit."

  tries=0
  while :; do
    VERDICT="$(run_agent reviewer "i${N}-04-review-$tries" \
"REVIEW iteration $N against $IDIR/plan.md. Re-run the full suite, check regressions vs \
$RUN_DIR/baseline.json, review the diff. Write $IDIR/review.md with PASS or NEEDS_WORK first.")"
    FIRST="$(printf '%s' "$VERDICT" | grep -Eo 'PASS|NEEDS_WORK' | head -1)"
    echo "    reviewer verdict: ${FIRST:-?}"
    [ "$FIRST" = "PASS" ] && break
    tries=$((tries+1))
    if [ "$tries" -gt "$MAX_FIX" ]; then
      echo "    still NEEDS_WORK after $MAX_FIX retries — pausing for you."
      break
    fi
    run_agent implementer "i${N}-03-implement-fix$tries" \
"Address the NEEDS_WORK findings in $IDIR/review.md. Fix in the sandbox, re-run tests, update evidence, commit."
  done

  # 4d. draft the next iteration
  run_agent surveyor "i${N}-05-draft-next" \
"DRAFT NEXT PLAN mode. Read $IDIR/review.md; update $RUN_DIR/findings.json (mark resolved where the \
Reviewer passed) and draft $RUN_DIR/iterations/$((N+1))/plan.md for the next unresolved finding(s)."

  # 4e. GATE 2 — review the proposed next iteration (not the QA alone)
  gate "GATE 2 — approve the path forward (iteration $((N+1)) draft)" \
"  - $IDIR/review.md  (what just happened)
  - $RUN_DIR/iterations/$((N+1))/plan.md  (proposed next step)"

  N=$((N+1))
done

echo "==> Done: no unresolved findings remain (or you stopped). Branch: review/$RUN_ID in $SANDBOX"
echo "    Review the branch and merge it yourself when satisfied; remove the sandbox with:"
echo "    git -C \"$TARGET\" worktree remove \"$SANDBOX\"   # (for a local-path run)"
