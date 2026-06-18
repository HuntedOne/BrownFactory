# CodeReviewDev — a four-agent harness for reviewing & improving an existing repo

A learn-by-reading harness that points an agent **team** at a repository that already exists,
**audits** it, then **improves** it one change at a time — while logging everything the agents think
and do, and **pausing for you** at two human-review gates per iteration. Built with Claude Code
configuration + shell hooks (the same style as [CodeFactory](https://github.com/HuntedOne/CodeFactory),
adapted from greenfield "build from nothing" to brownfield "improve what's there").

## The four agents

| Agent | Role | Can edit code? |
|---|---|---|
| **Surveyor** | Reads the repo, maps architecture & modules, captures the baseline, writes a prioritized findings backlog; proposes & negotiates each iteration's plan | ❌ (reports only) |
| **Implementer** | Makes the change for one iteration in the sandbox branch, keeps the baseline green, captures evidence, commits | ✅ (sandbox only) |
| **Reviewer** | Independent QA: re-runs the full suite, checks for regressions vs baseline, reviews the diff; emits `PASS`/`NEEDS_WORK` | ❌ (report only) |
| **Mentor** | **Your** guide at each pause — explains the team's decisions in plain English, surfaces risks, and co-drafts your guidance back | ❌ (`guidance.md` only) |

Why a separate Reviewer *and* a separate Mentor? Same core insight as the article: an agent grading
its own work over-praises it, so QA is split off; and a beginner needs a neutral teacher to make the
team's reasoning legible, so guidance is split off too.

## The loop and your two gates

```
setup sandbox + baseline
        │
        ▼
   SURVEY (audit.md, findings.json)
        │
   ┌────▼─────────────────────────────────────────────┐
   │  per iteration:                                   │
   │  Surveyor proposes + Implementer feasibility      │
   │            → iterations/N/plan.md                 │
   │                    │                              │
   │            ⏸ GATE 1  (you + Mentor → guidance.md) │
   │                    │                              │
   │            Implementer builds (sandbox branch)    │
   │                    │                              │
   │            Reviewer QA (regression vs baseline)   │
   │                    │  ↺ NEEDS_WORK retries        │
   │            Reviewer+Surveyor draft NEXT plan      │
   │                    │                              │
   │            ⏸ GATE 2  (you review the path forward)│
   └────────────────────┼──────────────────────────────┘
                         ▼  approve → next iteration / stop
```

- **Gate 1 — before any code is written.** You read the agreed `plan.md`, talk it through with the
  Mentor, co-author `guidance.md`, and may edit the plan. Nothing is built until you type `approve`.
- **Gate 2 — review the path forward.** After the change is built and QA'd, the Reviewer + Surveyor
  draft the *next* iteration. You review **that draft** (not just the QA) with the Mentor, then
  approve or stop.

## Logging — the emphasis (three layers)

Everything lives under `runs/<run-id>/logs/` and survives sandbox cleanup:

1. **`transcripts/*.stream.jsonl`** — the full event stream of each headless agent run
   (`claude -p --output-format stream-json --verbose`), including the model's reasoning and every
   tool call. The complete record.
2. **`actions.jsonl`** — one structured line per tool call, **tagged by which agent acted**
   (`log-action.sh` hook), plus prompts (`log-prompt.sh`) and session boundaries
   (`session-marker.sh`). A single greppable timeline across all four agents.
3. **`journals/<role>.md`** — each agent's own "what I considered / chose / rejected & why."

The **Mentor reads all three** — that's *why* we log everything: so it (and you) can reconstruct and
interrogate any decision instead of guessing. Try: `jq -r '"\(.ts) \(.agent) \(.event) \(.tool)"' runs/<id>/logs/actions.jsonl`.

## Safety: the sandbox + protection hook

- **Sandbox.** A local repo is reviewed in a **git worktree** (`sandbox/<run-id>/`, own branch, same
  history, trivial rollback); a GitHub URL is **cloned** into the sandbox. Your real working copy is
  never touched.
- **`protect.sh`** (a `PreToolUse` hook) enforces the rules as machinery: blocks `git push`,
  `--force`, and switching onto `main`/`master`; forbids edits to the harness (`.claude/`); allows
  edits to `sandbox/` code **only** for the Implementer; limits the Mentor to `guidance.md`.

The harness config + logs stay in `CodeReviewDev/`; the code under review stays in `sandbox/`. Agents
run *from* `CodeReviewDev` with `--add-dir sandbox/<run-id>` so they can read/modify the sandbox while
config and logs stay put.

## Usage

```bash
./review.sh /path/to/your/local/repo          # local → git worktree sandbox
./review.sh https://github.com/owner/repo.git  # remote → clone sandbox
```
At each gate, in another terminal (or via `/mentor` in an interactive `claude` session here):
```bash
AGENT_ROLE=mentor RUN_DIR="$(cat .claude/.current-run)" claude --agent mentor --add-dir sandbox/<run-id>
```
When satisfied, review branch `review/<run-id>` and merge it yourself; then
`git -C <target> worktree remove sandbox/<run-id>`.

**Tunables (env):** `PERM` (permission mode, default `bypassPermissions` — the `protect.sh` hook still
enforces safety regardless), `MAX_FIX` (NEEDS_WORK retries per iteration, default 2), `SKIP_BASELINE=1`.

> First runs may surface permission prompts depending on your Claude Code settings. `protect.sh`
> blocks the genuinely dangerous actions; `PERM` controls how much else is auto-approved. Start
> supervised, watch the logs, then loosen as you trust it.

## Reading list
Same backbone as CodeFactory — see that repo's README. Most relevant here:
[Harness Design for Long-Running App Development](https://www.anthropic.com/engineering/harness-design-long-running-apps),
[Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) (evaluator-optimizer),
[Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents).

## A caveat worth keeping
Every guardrail here encodes an assumption about what the model can't yet be trusted to do alone
(grade itself, stay in scope, not break the baseline). As models improve, re-test whether each piece
still earns its place — and delete what's become unnecessary.
