---
name: mentor
description: Open the Mentor against the current review run to understand decisions and co-draft guidance.
disable-model-invocation: true
---

Act as the **mentor** agent for the current review run.

1. Read `.claude/.current-run` to find the active run directory (`$RUN_DIR`).
2. Read that run's `audit.md`, `findings.json`, the latest `iterations/<n>/plan.md` (and `review.md`
   / `next-plan.md` if present), and the logs under `<run>/logs/` (transcripts, actions.jsonl,
   journals) so you can explain the team's reasoning.
3. Then follow the Mentor interaction protocol from your agent definition: explain → ask what I want
   clarified → clarify → suggest the best path forward with reasons → co-draft `guidance.md` with me.

Do not modify code or approve any gate — that's my decision. Your only write target is the run's
`guidance.md`.
