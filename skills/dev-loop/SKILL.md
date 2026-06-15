---
name: dev-loop
description: "Run the virtuous development loop for a Rails feature or bug — Opus plans, a parallel Sonnet specialist army implements (via roundhouse /rails-feature), Codex adversarially reviews, a fresh Opus reviewer rates the work against the plan, Sonnet agents fix until the quality gate passes, learnings are captured, and a PR is opened. Use for any non-trivial feature or bug. Prefers @kurenn/roundhouse and @openai-codex/codex; degrades gracefully without them. Run /dev-loop-setup once per repo first."
---

# /dev-loop — the virtuous development loop

You are the **Opus orchestrator**. Run the user's request through all six phases in
order. Do not skip phases. Do not collapse phases into a single pass. The value of the
loop is the separation of concerns: a planner, an independent implementation army, an
adversarial reviewer, an independent rater, a gated fixer, and a learning sink.

If the user gave no task, ask what to build or fix, then start at Phase 1.

---

## Step 0 — Read prerequisites and project config

1. **Prerequisites (prefer, don't require):**
   - `/rails-feature` + `/rails-bugfix` from **@kurenn/roundhouse** drive Phase 2.
   - `/codex:adversarial-review` from **@openai-codex/codex** drives Phase 3.
   - If either is missing, use the documented fallback in that phase and note it in the
     PR. If neither is installed, suggest the user run `/dev-loop-setup` (it checks).
2. **Project config:** read the project's `CLAUDE.md` for a `## Dev-loop config` block
   and use its overrides. If absent, use the defaults below and suggest running
   `/dev-loop-setup` to scaffold one.

   | Knob | Default |
   |---|---|
   | Gate | overall ≥ **8.5** AND every axis ≥ 7 |
   | Base rating axes | correctness, simplicity, test coverage, naming, performance risk, security risk |
   | Extra rating axes | none (project-declared, e.g. `design-system fidelity`) |
   | Critical paths | none (project-declared, e.g. `money / auth / KYC` → those axes ≥ 8.5) |
   | Learnings file | `docs/dev-loop-learnings.md` |
   | Fix-round cap | 2 |

---

## Model assignments (non-negotiable)

| Phase | Who | Model |
|---|---|---|
| 1 Plan & orchestrate | you (this session) | **Opus, maximum reasoning** — think hard before writing the plan |
| 2 Implement | specialist agents | **Sonnet** (army, parallel) via `/rails-feature` |
| 3 Adversarial review | Codex | external (`/codex:adversarial-review`) |
| 4 Rate against plan | a fresh reviewer agent | **Opus** |
| 5 Fix (gated) | specialist agents | **Sonnet** |
| 6 Learnings & PR | you | Opus |

When you spawn agents with the Agent tool, pass `model: "sonnet"` for implementation
and fix agents, and `model: "opus"` for the Phase 4 rater. Roundhouse specialists
(`roundhouse:rails-*`) are the preferred Sonnet implementers for Rails work.

---

## Phase 1 — Plan & orchestrate (Opus, max reasoning)

1. **Triage.** Is this trivial (typo, copy edit, single-line config, comment fix,
   obviously-safe one-file change, pure docs/config)? If yes, tell the user the loop is
   overkill, make the edit directly, and stop. Everything else continues.
2. **Refine** the request into a crisp problem statement and acceptance criteria. (If
   `/prompt-refiner` is installed, use it once here.)
3. **Create the worktree** off the main branch (never work on it directly):
   ```sh
   git worktree add .worktrees/<short-name> -b <feature|fix|chore|refactor>/<branch>
   cd .worktrees/<short-name>
   ```
   Keep the directory name short; the branch name can be longer.
4. **Write `PLAN.md`** in the worktree. It is the **contract the work is graded against
   in Phase 4** — be explicit: scope, files/layers touched, data-model and migration
   impact, any critical-path surface (per project config), test strategy, and the
   acceptance criteria as a checklist. Follow a sane Rails implementation order:
   models/migrations → policies → form objects → controllers → services → serializers →
   views/Stimulus/Tailwind → tests.
5. **Flag the rigor tier.** If the change touches a project-declared critical path, say
   so in `PLAN.md` and raise the Phase 5 bar for the relevant axes.

Do **not** implement in this phase. Hand off to Phase 2.

## Phase 2 — Implement (Sonnet army, in parallel)

Delegate implementation — do not write the feature yourself.

- **Feature / multi-layer change:** invoke **`/rails-feature`** with the refined task. It
  refines once, triages, and dispatches the **Sonnet specialist army** (models,
  controllers, views, services, jobs, tests) in parallel with TDD red→green and its
  conditional security/database gates.
- **Bug with a stack trace, failing test, or reproducible misbehavior:** invoke
  **`/rails-bugfix`** instead.
- **Fallback (no roundhouse):** spawn Sonnet agents directly with the Agent tool
  (`model: "sonnet"`), one per layer in the implementation order above, writing tests
  first. Note the fallback in the PR.
- Don't hand-orchestrate individual specialists when roundhouse is present — let the
  skill triage; over-spawning is the most common failure mode.
- Confirm the suite is green before review. Never proceed to review on red tests.

## Phase 3 — Adversarial review (Codex)

Challenge the implementation — approach, assumptions, tradeoffs, real-world failure
modes — not just surface defects. Run it against the branch and **wait** for the result
(the loop needs the output to rate in Phase 4):

```sh
CODEX_DIR=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ | sort -V | tail -1)
node "${CODEX_DIR}scripts/codex-companion.mjs" adversarial-review "--base <main-branch> --wait"
```

(The `/codex:adversarial-review` command is the interactive equivalent; it is marked
`disable-model-invocation`, so inside this loop call the companion script directly as
above. For a very large diff, swap `--wait` for `--background`, poll `/codex:status`,
then collect with `/codex:result` before Phase 4.)

**Fallback (no codex):** spawn a fresh Opus agent (`model: "opus"`) prompted to
adversarially challenge the approach, assumptions, and tradeoffs — explicitly trying to
find where the design fails under real-world conditions. Note the fallback in the PR.

Capture the findings verbatim — they feed Phase 4 and Phase 5. Fix nothing in this phase.

## Phase 4 — Rate against the plan (fresh Opus reviewer)

Spawn **one Opus agent** (`model: "opus"`) as an independent rater. Give it: `PLAN.md`,
the branch diff (`git diff <main-branch>...HEAD`), the test results, and the Phase 3
findings. It must NOT edit code — it only judges. It returns:

1. A score **1–10 on each axis** (the base axes plus any project-declared extra axes).
2. An **overall plan-fidelity score (1–10)** — how completely and faithfully the work
   delivers the Phase 1 plan and acceptance criteria, weighing the Phase 3 findings.
3. The **single lowest axis** and the most valuable concrete fix for it.
4. A list of **blocking issues** (adversarial challenges that are real + any axis < 7).

## Phase 5 — Fix (Sonnet, gated)

**Gate (from project config; default):** pass when **overall ≥ 8.5 AND every axis ≥ 7**.
For changes touching a project-declared critical path, also require the relevant axes
(typically correctness and security risk) ≥ 8.5.

- If the gate is **met**, go to Phase 6.
- If **not met**, dispatch **Sonnet agents** (roundhouse specialists where they fit) to
  fix the blocking issues and lift the lowest axes. Then **re-run Phase 3 and Phase 4**
  on the updated branch.
- **Respect the fix-round cap** (default 2). If still below the gate after the last
  round, stop, write what's blocking to `PLAN.md`, and surface it to the user with the
  latest scores and the adversarial findings. Never loop indefinitely, and never lower
  the bar to pass.

## Phase 6 — Capture learnings & ship

1. **Append learnings** to the project's learnings file (default
   `docs/dev-loop-learnings.md`) — only durable, reusable insight (a non-obvious gotcha,
   a pattern worth repeating, an adversarial challenge that recurred, a place the plan
   was wrong). Skip the diary; capture the map. Nothing user-specific or secret. Use the
   entry format at the top of that file.
2. **Self-rate summary** — keep the final Phase 4 axis scores for the PR body.
3. **Open the PR** with `gh pr create`, following the project's PR conventions (from
   `## Dev-loop config`). The body must include:
   - **Summary** — what changed and why (1–3 bullets)
   - **Self-rating** — the final axis scores + overall plan-fidelity score
   - **Loop trace** — how many fix rounds ran, and the headline adversarial challenge(s)
   - **Improvement applied** — what the fix pass(es) changed, or follow-ups deferred
   - **Test plan** — how to verify, including manual steps for UI changes
   - **Screenshots** — for any visual/UI impact, per the project's PR conventions
4. Don't leave work uncommitted on the worktree branch.

---

## Guardrails

- **Cost is real.** A parallel army + iterative fix loop + Codex + an Opus rater is
  expensive. Don't run the full loop on trivial work (Phase 1 triage catches this), and
  respect the fix-round cap.
- **Never lower the gate to pass.** If the gate is genuinely unreachable in scope, that's
  a Phase 5 escalation, not a reason to soften the threshold.
- **The plan is the contract.** If implementation reveals the plan was wrong, update
  `PLAN.md` and say so in the rating — don't silently drift.
