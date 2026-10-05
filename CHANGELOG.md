# Changelog

## 0.6.2

Fixes from auditing the rest of the 2026-10-02 loops: 12 PRs from 0.6.0 loops, none of
them carrying an unrated commit.

**Learnings are one file per entry.** Every loop inserted its entry at the same spot in
`docs/dev-loop-learnings.md`, so each merge conflicted the next open PR. That happened at
least five times in one day, and each conflict cost a merge agent, a delta rating and a
CI run. Entries now go to `docs/dev-loop-learnings/<YYYY-MM-DD>-<slug>.md`. A profile
that still names the single file keeps it as the archive, and new entries go to the
directory of the same name, so no repo has to change its config. `/dev-loop-setup` now
creates the directory with a `README.md` that holds the entry format.

**The baseline finishes before Phase 4.** In one loop the baseline was still running
when the units started editing, and three tests failed against the units' half-written
code rather than the original. The orchestrator caught it, but it was luck.

**A wave's tests and commit have no required order.** Three loops committed a wave
seconds before testing it, with no harm: units run their own scoped tests, and Phase 5
runs everything. Running the tests after each wave stays; the order is gone.

**A delta brief says nothing about the verdict.** One orchestrator told its delta raters
"gate: 0 BLOCKING, 0 MAJOR" and which MINORs were "left by design", which is the
threshold the rater is meant to be blind to. A delta brief now carries the prior rating
verbatim and the diff, and nothing about the gate, the counts or what was left open.

**Project rules can require a MINOR fix.** Two loops fixed MINORs after the gate was met
because the project's own rules require comments to be true. MINORs are still listed
rather than fixed by default; a user or project rule can require a fix, which is then an
ordinary rated commit.

**The trivial path respects a project's worktree rule.** It said to edit in the main
checkout. Loops in a repo that forbids that rightly used a worktree and a PR, and the
text now says so.

## 0.6.1

Fixes found by monitoring and auditing the first 0.6.0 loops on 2026-10-02: 8 loops across
4 sessions, two of them running 5 loops each as parallel "lanes". No 0.6.0 loop shipped
an unrated commit. These are the gaps the audits found anyway.

**Everything is based on a fresh `origin/$MAIN`.** The skill branched worktrees from the
local `$MAIN` and diffed against it. In one loop that branch was days behind, so the rater
was given 138 files to judge instead of the change. Step 0 now fetches and sets `$BASE`,
and every worktree, diff, Codex base and merge uses it. `$MAIN` remains only as the
branch name for `gh pr create`.

**Timers are cancelled by their own task id.** One lane cancelled its timer with
`pkill -f "sleep 900"`. That killed the parent's timer and another lane's, because every
timer runs the same command, and it is exactly the silent stall the timer exists to
prevent. Timers are also cancelled before a stop that waits on the user. Leftover timers
had woken a lane parked at its checkpoint, and it re-sent its question each time.

**Two contradictions in 0.6.0's own text are resolved.** Phase 8 said "commit the fix"
while the new rule said nothing after a rating is committed by the orchestrator; the fix
agent now commits. Phase 9's learnings commit is named as the one exception: the
orchestrator's, unrated, and touching only the learnings file.

**A red suite is not a flake by assertion.** A lane went from 0 baseline failures to 2,
called them flakes because they passed in isolation and an open flake issue existed, and
moved on to rating. A new failure now counts as a flake only if the full suite passes on
one rerun.

**A lane's checkpoint reaches the user whole.** When a parent session relayed a lane's
plan for approval, it dropped the acceptance criteria and the assumptions, so the user
approved assumptions they never saw. A loop running as a subagent now returns the full
checkpoint summary, and the parent relays it unabridged.

## 0.6.0

These fixes come from an audit of 19 real loops across 7 sessions on 0.5.1 and 0.5.2. The
loop's core held: every loop stopped for plan approval, overran its fix-round cap only
with the user's consent, ran Codex where the rules require it, and never pushed outside
its repo. The guarantee leaked at the edges, where code reached a PR without being rated.

**No commit reaches the loop branch unrated.** The audit found unrated commits in every
session: the orchestrator's own tidies after the gate, merges of a moved `$MAIN` with
their conflict resolutions, CI fixes after the PR opened, MINOR fixes after the gate was
already met, and commits pushed to a loop's PR from outside any loop. Every commit after
the last rating is now made by a unit agent and gets a delta judgment before it is pushed.
Before every push, the loop lists the commits made since the last rating and rates any
that were missed. A met gate goes straight to Phase 9, and its MINORs are listed rather
than fixed.

**Phases 5, 6 and 7 run in strict order**, inside fix rounds too. Loops had started Codex
alongside the test suite and the rater alongside Codex. In one loop the rater rated
without the adversarial findings it was supposed to judge.

**The rater sees verbatim records and no threshold.** Ratings had been saved as the
orchestrator's summaries, and the next delta rater was told the summary was
authoritative. Ratings are now saved verbatim. Subagents also load the project's
`CLAUDE.md`, and one project stated the gate there, so every rater knew the threshold.
The loop and `/dev-loop-setup` now flag those lines for removal.

**A wait cannot stall silently.** One loop sat idle for 11 hours on a notification that
never arrived; others sat for 20 to 26 minutes. Before ending a turn to wait on
background agents, the orchestrator now arms a 15-minute background timer. When it wakes,
it checks every agent it is waiting on and re-dispatches an idle one once. The timer
reports through the same notification channel as the agents. If a stall recurs, a
scheduled task (CronCreate) is the next step.

**The planner and critic are plugin agents**, like the rater: `dev-loop:planner` and
`dev-loop:critic`, pinned to `claude-opus-5-5` at `high` effort. The Agent tool only
accepts `sonnet`, `opus`, `haiku` or `fable` as a model, so the skill's
`model: "claude-opus-5-5"` failed on every run. The planner and critic got Opus 5.5 anyway
only because the `opus` alias currently resolves to it.

**Two rules nobody followed are gone.** Loops were told to announce the tier before
planning, before the unit count can be known; the tier is now shown at the plan
checkpoint. The PR's "Improvement applied" section was missing from nearly every PR; its
content now sits in the loop trace.

## 0.5.2

Two changes from Anthropic's *Prompting Claude Opus 5.5* guide, applied where they fit this
loop.

**The rater is a plugin agent pinned at `high` effort.** `agents/rater.md` fixes the model
at `claude-opus-5-5`, the effort at `high`, and the tools at read-only. Before this, the
rater inherited the effort from each user's own Claude Code settings, so the same change
could be judged at different depths on different machines. The guide says to set effort
explicitly because its levels do not carry across models. `high` is the level every
recorded rating ran at, and 0.5.1's measurement found no level that rates better. Phase 7
now spawns `dev-loop:rater`.

**A status note no longer ends the orchestrator's turn.** The guide says Opus 5.5 sometimes
ends a turn on a progress report partway through a long task, which would stall a loop
that is meant to run unattended after the checkpoint. Its recommended fix is to name the
stops you do want. The skill already names them, and now it says that a status note goes
in the same message as the next tool call.

**Two corrections.** The plugin description still promised the second rating that 0.5.1
removed. And `bench/README.md` now says that a Tier 2 "pass" means no BLOCKING finding,
not that the change ships, which is the misreading that kept the second rating alive.

## 0.5.1

**The second rating on the margin is gone.** 0.4.0 added it because the rater sometimes
labelled an untested endpoint BLOCKING and sometimes MAJOR. The 7%-to-2% figure behind it
came from Tier 2, which scores a rating as passing whenever it has no BLOCKING finding. The
gate is stricter than that: a MAJOR must also be fixed unless it is waived on one of three
grounds, and an in-scope defect fits none of them. So for a real defect the two labels lead
to the same fix round. The second rating only mattered when a mislabelled defect would
otherwise have been waived. That case was never measured, and the waiver grounds plus the
waiver list in every PR body already cover it. The second rating itself was not occasional:
the correct variant drew a MAJOR on 10 of 10 reps, so it would have run on nearly every
loop.

**Rater effort was measured and left alone.** `bench/PLAN-rater-effort.md` ran the rater at
`medium`, `high` and `xhigh`, n=10 each on every variant, with the decision rule
pre-registered. No level made `coverage_removed` consistent (3/10, 0/10 and 3/10 blocked),
so none is pinned. The brief's own definition files an untested branch under MAJOR, and
the rater follows it at every level. `bench/tier2/replay.sh` gained `BENCH_EFFORT` to run
this.

**The project page was redesigned** (#13): an opensop.ai-style layout with an animated
terminal run, in Omarchy's Tokyo Night palette. It is still one self-contained file with
no external requests.

## 0.5.0

A release that makes the text match the loop. It adds no mechanism, and the skill is 22
lines shorter than 0.4.0's.

**The rater was reviewing an empty diff.** Phases 6 and 7 are given `$MAIN...HEAD`, and
nothing was committed until Phase 9, so read literally that diff was empty. Each wave is now committed once it is green, and so are
Phase 5 repairs and Phase 8 fixes. The per-wave ownership check reads cleaner too:
`git status` now shows only the wave in hand.

**The loop's own files moved out of the worktree** into `$ART`
(`.worktrees/<slug>.loop/`). The planner, critic and rater return text and the
orchestrator files it. Nothing the loop writes for itself can reach a commit now, and
none of it can turn a project's own checks red. The per-unit-worktree trial's Phase 5 went
red on exactly that: its repo has a spec that forbids stray files at the root (#9).

**The fix-round cap now covers every round.** Before, it only said what to do with a
BLOCKING that survived the cap, so a MAJOR raised by the last delta rater had no rule, and
both recorded runs went past the cap. Now a round is one fix, one Phase 5 and one delta
judgment. At the cap the loop stops and hands the surviving findings to you, whatever
their severity. The same sentence ends the delta loop, which had no end (#9).

**The plan cap limits what the planner returns.** Phase 3's edits don't count against it
(#9).

**The "Measured:" rationale left the skill.** It lives here and in `bench/`. One of those
lines called a resampled figure measured.

**A rater brief was tried and rejected.** `raters/v0.4.md` stated the line between an
unmet criterion and an untested branch, aiming at the same instability the second opinion
targets. Pre-registered in `bench/PLAN-v0.4.1.md`, then run at n=10 per arm with the arms
interleaved: it blocked `coverage_removed` 10/10 (v0.3: 2/10), and it also blocked the
correct variant 10/10 (v0.3: 0/10). It was unanimous, not noisy: it held the reference
implementation to "every acceptance criterion proven by a test", which that code does not
meet. That is a stricter definition of done, not a calibration fix, so it was dropped and
the second opinion stays. The same run puts v0.3's `coverage_removed` instability at 2/10
blocked, worse than the 3/5 that motivated the second opinion.

## 0.4.0

0.3.0 was written up below but never tagged or published, so the last installable release
is 0.2.6. Installing 0.4.0 brings both batches; read the 0.3.0 entry as part of this one.

**Phases 2, 3 and 7 move to a pinned `claude-opus-5-5`.** The pin is not decoration: the
`opus` alias resolves to a provider's *recommended* Opus, which trails the newest release
and differs per provider, so naming the alias is not a way to ask for Opus 5.5. Phase 6's
fallback still names an alias, deliberately — it does not ask for a specific version.

Phase 7 is the consequential one, and it comes with a correction. The rater has always
been spawned as `opus`, so every rating this project has ever recorded — including every
number in `bench/RESULTS.md` — was made by whatever Opus the provider recommended at the
time, which the docs put two to four minor versions behind the current release. Results
collected before this change were not produced by the model the write-ups call "opus", and
a rating is the only agent output the gate reads, so this is the one model substitution
that can silently change what the loop ships.

**Phase 7 takes a second opinion on the margin.** When a rating returns no BLOCKING but at
least one MAJOR, a second independent rater runs on the same inputs and the two are merged
with the higher severity winning. A BLOCKING already fails the gate and a MINOR is nowhere
near one, so only the band where a single opinion decides the outcome pays for the extra
call.

The reason is the Tier 2 corpus rather than taste: asked five times about identical code,
the rater called the same real defect BLOCKING three times and MAJOR twice. That is not a
gate failure — the gate executed faithfully — it is an unstable judgement upstream of
every rule the gate applies, and no amount of waiver prose reaches it. Resampling those
reps in pairs puts wrong gate outcomes at 2% against 7% for a single rater, with no false
blocks, though the false-block half rests on one clean variant in one corpus and is the
weaker claim.

**The Tier 2 harness gained the instrument that produced that figure.** `score.py` now
reports the top severity each rep assigned, which is the only thing the gate acts on and
the thing a findings count hides; it also tells a run refused by the API apart from a rater
returning nonsense, and prints `RUN VOID` rather than a table when refusals outnumber
answers — a calibration run that reported a clean $0.00 result is what prompted that.
`replay.sh` discovers arms dynamically and alternates them call by call, applying last
release's interleave rule to Tier 2. The current Phase 7 brief joins as a third arm in
`raters/v0.3.md`, with a header recording that it drops `PLAN-CRITIQUE.md` and
`HANDOFFS.md` because a static corpus cannot supply them, so it isolates the rating brief
rather than all of v0.3's Phase 7.

**Neither change has been measured end to end**, and per the rule added last release it
cannot be until the arms are run interleaved in a single session. The 2%-versus-7% figure
is resampled from ratings already collected, not from a live two-rater run.

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
