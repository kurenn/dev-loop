# Changelog

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
