# Changelog

## 0.2.4

- **Disproportion is now a MAJOR rating finding.** Blind graders, shown two implementations
  of the same task with the flow identity stripped, unanimously preferred v0.1's — 8.25 vs
  3.75 on simplicity and 8.50 vs 5.75 on clarity — despite both passing an identical hidden
  acceptance suite. The loop's extra spend had gone into an abstraction with one caller, an
  error handler that cannot fire, and 45% comment density. Nothing in the rating rewarded
  proportion, so nothing checked it.
- The rater is told explicitly that more code is never better by itself, and fix rounds are
  told the fix must be the smallest change that resolves the finding, since fix rounds are
  where scaffolding accretes.

## 0.2.3

- **File ownership is now enforced, not merely instructed.** The agent brief already told
  each unit to stay inside its declared file set, and the benchmark breached it in 4 of 4
  runs — undeclared test files, `app/models/project.rb`, `.gitignore`. Phase 4 now checks
  `git status --porcelain` against the wave's ownership after every wave and requires each
  violation to be declared or reverted before the next wave starts.
- **Units that create files must declare a directory or glob.** A filename that does not
  exist yet cannot be enumerated, so a unit writing a migration or a new test was being
  set up to fail. One benchmark plan declared no `db/migrate/` ownership at all on a task
  whose whole purpose was a schema change.
- Every acceptance criterion must now be owned by exactly one unit.

## 0.2.2

- **Push and PR are separated.** Phase 9 gated the `git push` on `gh` being usable, so a
  repo with a working git remote and no GitHub had finished, committed work stranded on a
  local branch. Caught by a benchmark run against a bare local origin: the loop committed,
  correctly detected no GitHub, and then declined to push at all. Pushing is git; only the
  PR needs `gh`.

## 0.2.1

Latency and cost fixes, from measuring an actual run. A one-line bug fix — a missing
column default — took 35 minutes, cost $12.72 and produced a 397-line plan. The phase
breakdown showed where it went.

- **The size tier is a hard branch, not a hint.** It was one advisory sentence, and the
  orchestrator drifted past it into the full nine-phase treatment with three execution
  waves. Now it is a table the tier selects a whole row from: plan cap, Phase 3 shape,
  wave count, fix cap, and whether Codex runs. A schema change no longer forces Full on
  its own — a migration plus its test is two units.
- **The plan critic is bounded.** Phase 3 was 44% of the run (15.5 min), much of it the
  critic reading ActiveRecord source and writing probe scripts in /tmp to prove framework
  behaviour empirically. It now judges the plan against the request and the repo as it
  stands; a claim needing more than that is recorded as unverified and left to Phase 5.
- **Critique and revise are one round trip.** The separate revise agent cost ~5 of those
  15.5 minutes. The critic now proposes the specific edit for each point and the
  orchestrator applies it or rebuts it in one line. Independence is preserved — the critic
  still never authored the plan.
- **Plan size is capped by tier** (Light 120 lines, Full 300). PLAN.md is a work contract,
  not a design essay; overrunning the cap means prose, not decomposition.
- Light tier skips the paid adversarial review unless a critical path is touched, and the
  fix-round cap now derives from the tier rather than being a flat 2.
- `bench/flows/v0.2.1/` pins this version as a third benchmark arm. v0.2 stays pinned
  unchanged so it still matches the runs already completed against it.

## 0.2.0

Stack-agnostic rewrite. The loop no longer assumes Rails, gains a plan-critique phase, a
plan-approval checkpoint and a mechanical gate.

**Added**
- **Phase 3 — plan critique and approval checkpoint.** A *fresh* fable agent attacks the
  plan cold (it never sees the planner's reasoning); the planner applies or rebuts every
  point; then the loop presents the plan, the wave breakdown, the assumptions and the cost
  shape, and waits for approve / revise / abort. `--auto` or `Checkpoints: none` in the
  profile skips the stop — autonomous mode must be explicitly requested, never inferred.
- **Phase 5 — mechanical gate.** Build, test, lint, typecheck and security run against a
  pre-implementation baseline before any money is spent on review. Red never reaches the
  reviewer, and a check the project doesn't define is skipped *and reported as skipped*.
- **Dependency-ordered execution waves.** `PLAN.md` now decomposes work into units with
  disjoint file ownership grouped into waves — parallel within a wave, serial between —
  so a parallel army in a shared worktree can't collide.
- **Agent brief contract.** Every spawned agent is handed the absolute worktree path and
  its owned file list. Subagents inherit neither context nor working directory, so
  without this they edit the main checkout.
- **Worktree provisioning and baseline capture** — copies the gitignored local config a
  fresh worktree needs to boot, runs install/prepare, and records the pre-change state.
- **Artifact persistence and resumability** — `PLAN.md`, `PLAN-CRITIQUE.md`,
  `REVIEW-round-N.md`, `RATING-round-N.md`, `LOOP_STATE.md`.
- Size-tier triage, `.worktrees/` gitignoring, `gh auth` detection, and pre-existing
  worktree resume-or-suffix handling.

**Changed**
- **The gate is no longer numeric.** Was `overall ≥ 8.5 AND every axis ≥ 7`; now
  mechanical checks green + zero blocking findings + every major fixed or waived with a
  written reason. Axis scores remain, as PR telemetry.
- **The rater is threshold-blind** and ships with a literal prompt template — axes,
  severity definitions, explicit score polarity (10 is always best), required output
  sections, and a large-diff fallback. Fix rounds are **delta-judged** against the prior
  rating rather than re-scored from scratch.
- **Planning moved to fable**; rating stays on a different model family from the planner.
- **Roundhouse and codex are optional accelerators, not the backbone.** Rails units route
  to `roundhouse:rails-*` subagents *inside* this loop's plan and ownership boundaries,
  instead of delegating the feature to another orchestrating skill that would re-plan it.
- `/dev-loop-setup` now detects **and verifies** the project's commands for any stack and
  writes a full profile; an unverifiable command is left blank rather than guessed.

**Fixed**
- Phase 6 large-diff path: the companion script parses `--background` for reviews but
  ignores it, and `/codex:status` / `/codex:result` are `disable-model-invocation` — so
  the documented path could not work. Now uses Bash `run_in_background` plus the
  companion's `status` / `result` subcommands, with a 600s timeout on the foreground call.
- Phase 9 never committed or pushed, so `gh pr create` could not succeed.
- `<main-branch>` is now resolved rather than referenced; the `CODEX_DIR` block is marked
  single-call and guarded against being empty.
- Risk axes had undefined polarity — `security risk: 9` was ambiguous enough to invert the
  gate. Axes are renamed and polarity is stated.
- The learnings pipeline had no defined insertion point, no create-if-missing, no
  specified checkout, and was skipped on exactly the runs that taught the most.

## 0.1.0

Initial release. Six-phase Rails loop: Opus plan → Sonnet army (roundhouse) → Codex
adversarial review → independent Opus rating against the plan → gated Sonnet fix → PR.
