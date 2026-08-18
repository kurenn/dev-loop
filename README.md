# dev-loop

A **virtuous development loop** as a Claude Code plugin — for any stack. One command
chains nine phases with deliberate model tiers and a gate that can't be talked around:

| Phase | Who | Model |
|---|---|---|
| 1 · Triage & frame | the session | trivial work exits here; everything else picks a size tier |
| 2 · Plan | one agent | **fable** — worktree, provisioning, baseline, `PLAN.md` |
| 3 · Critique & revise | a *fresh* agent, then the planner | **fable** — attacks the plan cold, planner answers every point, then you approve |
| 4 · Execute | unit agents, parallel *within* a wave | **sonnet** — disjoint file ownership, dependency-ordered waves |
| 5 · Mechanical gate | the session | build · test · lint · typecheck · security, against a baseline |
| 6 · Adversarial review | Codex, else a fresh agent | challenges the approach, not just defects |
| 7 · Rate | an independent rater | **opus** — threshold-blind, severity-ranked findings |
| 8 · Gate & fix | unit agents | **sonnet** — zero blocking findings, ≤ 2 rounds, delta-judged |
| 9 · Learnings & ship | the session | appends durable learnings, commits, opens the PR |

The point is **separation of concerns**: a planner, an independent critic of the plan, an
implementation army, an adversarial reviewer, an independent rater, a gated fixer, and a
learning sink — so quality comes from structure, not willpower.

It stops **once**, after the plan, and waits for you — the cheapest quality lever in the
loop, since a wrong direction caught there costs less than any fix round. Everything after
that runs unattended. `/dev-loop --auto <task>` skips the checkpoint and runs straight
through to a PR; autonomous mode is never assumed, only asked for.

## Install

```sh
/plugin marketplace add kurenn/dev-loop   # if not already on the kurenn marketplace
/plugin install dev-loop@kurenn
```

## Usage

```sh
/dev-loop-setup            # once per repo: detects and verifies the project profile
/dev-loop <feature or bug> # run the full loop
```

`/dev-loop-setup` is not optional busywork — it is what makes the loop stack-agnostic. It
detects and **verifies** how this project installs, tests, lints, typechecks and scans,
which gitignored files a fresh worktree needs to boot, and which specialist subagents
exist for the stack, then writes it all into a `## Dev-loop config` block in `CLAUDE.md`.
The loop reads that profile instead of guessing at runtime.

## Optional accelerators

Neither is required; both are auto-detected:

```sh
/plugin install codex@openai-codex     # Phase 6: out-of-family adversarial review
/plugin install roundhouse@kurenn      # Phase 4: Rails specialist subagents
```

Without codex, Phase 6 uses an in-family reviewer — which shares training and blind spots
with the implementers, and is labelled as weaker in the PR. Without stack specialists,
Phase 4 uses general agents. `gh` is likewise optional: unauthenticated, the loop stops at
a commit and hands you the push and PR commands.

## Design notes

**Why waves.** Parallel agents in one worktree collide. So `PLAN.md` must decompose the
work into units with **disjoint file ownership**, grouped into waves — parallel within a
wave, serial between them, interfaces and schemas before their consumers. Ownership is
declared in the plan and enforced in every agent brief.

**Why the gate is mechanical.** An unanchored 1–10 self-report clusters in the 7–9 band
and drifts between rounds, so it makes a poor control. The gate here is: mechanical checks
green against a pre-implementation baseline, **zero blocking findings**, every major
finding fixed or waived with a written reason. The 1–10 axis scores still get produced —
they go in the PR body as telemetry, where being approximate is harmless.

**Why the rater is blind.** It is a fresh agent that never sees the threshold, judges
against `PLAN.md` and the acceptance criteria, and ranks findings by severity rather than
being asked for a number to compare against a bar it already knows.

**Why model tiers.** Fable plans and critiques, because plan errors are amplified by every
phase downstream and are the most expensive errors in the loop. Sonnet implements and
fixes, because the work is parallelizable and well-specified once the plan exists. A
*different* model — opus — rates, so the grader shares neither the implementer's context
nor the planner's.

**Everything is a file.** `PLAN.md`, `PLAN-CRITIQUE.md`, `REVIEW-round-N.md`,
`RATING-round-N.md` and `LOOP_STATE.md` all live in the worktree — so the loop is
auditable, resumable after an interruption, and survives context compaction.

## License

MIT © Abraham Kuri
