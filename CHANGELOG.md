# Changelog

## 0.3.0

Four changes to how information moves between the agents, from reading Cursor's *Towards
self-driving codebases* against this skill. That harness optimises throughput across
hundreds of agents over a week; this one optimises a guarantee on a single change, so most
of what it removed — the judge, the integrator, per-commit correctness, the upfront plan —
is load-bearing here and stays. What survives the change of regime is smaller.

**Measured at Tier 1, 10 runs, two tasks** — pre-registered in `bench/PLAN-v0.3.md` before
the run, results in `bench/RESULTS.md`, pinned arm in `bench/flows/v0.3/`. Every mechanical
assertion passes on both arms and cost is flat (+7.6% on one task, −12.3% on the other).
**Nothing in this matrix separates the two arms on quality.** v0.2.6 found zero MAJOR
findings in five runs and v0.3 found one in each run of the harder task, but tracing that
gap to its source dissolves it: both arms' raters detect the one real defect at comparable
rates and both call it MINOR, the single BLOCKING was a genuine 500 in a run whose code was
worse, and the run that blocked did so over an issue measured at 0.76 ms. That last one is
closer to C4's pre-registered *failure* mode — over-fixing — than to a catch. C4 itself
stays unmeasured, since v0.2.6 never found a MAJOR and so never faced a waiver decision.

**No quantitative comparison between the arms survived review**, including ones an earlier
draft of this entry stated as findings. Each arm ran on its own day, so arm and date were the
same variable. Re-running the byte-identical v0.3 text two days later cost 65% more, ran 89%
longer, and shipped a defect in 3 of 3 runs where it had shipped 1 of 3 — a bigger swing than
any effect attributed here to a change in the skill. The cost regression this entry once
reported for v0.3.1, and the claim that v0.3 ships fewer defects than v0.2.6, are both
withdrawn. Details in `bench/RESULTS.md`; the harness now requires arms to be interleaved
within a single session, which is the rule whose absence caused this.

Two instruments came out of it and are worth keeping. A **waiver replay** isolates the gate on
a fixed corpus, and is how the inert ground below was caught. **Shipped-defect probes** ask
whether something broken reached main — the question nothing else here asked, and the reason
the one real defect in this matrix was originally found by reading controllers by hand while
every Tier 1 assertion and all 8 hidden acceptance tests passed on the branch carrying it.
Both are sound instruments that were pointed at a confounded experiment.

- **Unit agents return a four-field handoff** — CHANGED, NOT DONE, DEVIATIONS, CONCERNS —
  and the orchestrator must answer it. The brief already asked for roughly this
  information, but nothing in the loop consumed it, so an implementer writing "the plan was
  wrong here" went nowhere. Handoffs are now collected into `HANDOFFS.md`, every deviation
  and concern gets an amendment or a written rebuttal before the next wave, and the rater
  receives them labelled as claims to verify rather than as evidence. Handoffs travel up
  only; the failed experiment this avoids is worker-to-worker coordination.
- **A failed unit is re-dispatched once, then the loop stops.** Previously undefined: the
  skill ran the suite after each wave and said nothing about red, so the orchestrator
  improvised, and improvising here means finishing the unit itself — the exact pathology of
  an executor holding too many roles. Re-planning around the failure stays the user's call.
- **`LOOP_STATE.md` is rewritten, not appended**, to a fixed schema under ~40 lines with a
  `Trace` line. It is the one artifact that has to survive a context compaction intact, and
  a diary buries the resume path in its own history.
- **MAJOR waivers are restricted to three enumerated grounds** — declared out of scope,
  pre-existing on main, or arguing against an assumption, scope decision or resolved
  critique point `PLAN.md` records — and in autonomous mode nothing on a critical path may
  be waived at all. The orchestrator is simultaneously the party under cost pressure and the
  party deciding what to waive, which is the one place in this loop where the judge and the
  executor are the same agent. Constraining it follows the pattern the rest of this changelog
  keeps rediscovering: guarantees expressed as checks hold, guarantees expressed as judgement
  trade away.

  The third ground originally read "contradicts an assumption the **Phase 3 checkpoint
  approved**", and the waiver replay showed that wording was inert: the checkpoint never
  fires in an autonomous run, so nothing is ever approved and the ground was unavailable in
  every run of every benchmark here. It accounted for **the entire over-fixing rate** — the
  gate fixing findings that merely disagreed with a decision it had already written down.
  Keying it to the plan's record instead took over-fixing from 45% to 0% on that corpus, at
  the cost of one finding that should not have been waivable. The corpus is author-written
  with two contested labels at n=5, and the inertness — not the rate — is the part that holds
  without it, because it follows from the checkpoint never firing. See `bench/waivers/`.
  A rebuttal disposition for findings that are factually wrong, and a requirement to cite the
  line or identifier a waiver rests on, were both written, benchmarked and **cut**. Neither was
  used once in nine end-to-end runs, and the corpus that motivated the rebuttal contained no
  wholly-false finding to exercise it. The shipped gate is the smallest change that fixes a
  ground provably unreachable in autonomous mode, and nothing more.

Benchmark harness: three new Tier 1 assertions (A10 handoffs collected, A11 handoffs
answered, A12 state rewritten), applicability-gated on each arm's own skill body so an arm
is never marked down for omitting something it never claimed. `HANDOFFS.md` added to A9's
loop-artifact list, without which the new arm would fail its own ownership check.

Two scoring bugs were found mid-matrix and fixed. A4–A6 scored a run that stopped at a
blocked gate identically to one that failed to commit, which penalised the arm whose gate
is strictest for the gate working; they are now withheld on a blocked gate, each run
records a `gate` disposition, and **A14** checks the inverse — a blocked gate that pushes
anyway. A9's `covered()` honoured a glob only in trailing position, so a unit declaring
`test/controllers/api/v1/*_test.rb` was scored as violating the path it had just declared.
`bench/tier1/rescore.sh` re-runs every run through the identical final version and keeps
the original score as `results-asrun.json`. Every false negative these fixes corrected fell
on v0.3, which is the same-author confound at its sharpest and is flagged as such in
`bench/RESULTS.md`.

Two new harnesses. `bench/waivers/` replays a fixed rating through different gate texts to
isolate waiver behaviour, which is how the inert third ground was caught. `bench/probes/`
runs adversarial checks against every finished branch and separates a defect that was
*carried* from one that *shipped* — a run that wrote a defect and blocked is the loop
working, and every other view in this harness collapsed those into the same row. Neither
needs model calls.

## 0.2.6

- **Coverage floor moved into the mechanical gate.** 0.2.5 protected test rigour with a
  written caution not to weaken a test. An ablation arm that instead refused to let coverage
  fall below baseline beat 0.2.4 on test quality in both blind pairings (+1.25, +0.75),
  reproducing the pattern that has held all through this benchmark: guarantees expressed as
  checks hold, guarantees expressed as adjectives trade against each other. The written
  caution stays, but the check is what enforces it.

## 0.2.5

- **Disproportion findings may no longer be satisfied by weakening a test.** 0.2.4 told fix
  rounds that removing code is a legitimate fix; graders found it had been applied to test
  assertions, costing the `:id`-tiebreaker regression test and weakening a page-cap check to
  a bound the fixture could not exercise. Blind test-quality scoring fell 8.12 to 7.25
  against the arm without the rule. Coverage may now only fall when the code it covered is
  gone, and a test counts as disproportionate only if it tests the framework, exactly
  duplicates another, or asserts nothing.

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
