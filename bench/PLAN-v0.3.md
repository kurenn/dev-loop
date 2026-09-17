# Benchmark plan — v0.2.6 vs v0.3

Four changes ship together in v0.3. They came from reading Cursor's *Towards self-driving
codebases* (Feb 2026) against this skill and keeping only what survives the change of
regime — that harness optimises throughput across hundreds of agents over a week, this one
optimises a guarantee on a single change. Nothing here is measured yet. This file is the
pre-registration: what is being changed, which instrument can see it, what is predicted,
and what result would send each change back out.

## The four changes

| # | Change | SKILL.md |
|---|---|---|
| C1 | Unit agents return a four-field handoff (CHANGED / NOT DONE / DEVIATIONS / CONCERNS); the orchestrator collects them into `HANDOFFS.md` and must give every deviation and concern a disposition — an amendment or a written rebuttal — before the next wave. The rater receives them labelled as claims, not evidence. | brief contract, Phase 4, Phase 7 inputs |
| C2 | A unit that fails is re-dispatched **once** to a fresh agent, then the loop stops before the dependent wave rather than improvising. Previously undefined. | Phase 4 |
| C3 | `LOOP_STATE.md` is rewritten at every phase boundary to a fixed schema under ~40 lines, including a `Trace` line, instead of being appended to. | Artifacts |
| C4 | A MAJOR may be waived only on three enumerated grounds, and in autonomous mode nothing on a critical path may be waived at all. Previously "waived with a one-line written reason", judged freely. | Phase 8 |

C1 and C3 are Cursor's handoff and freshness mechanisms, which are regime-independent.
C2 is their anti-fragility principle in the only form that fits a loop that ships once.
C4 is the opposite of what they did — they removed the judge; this constrains ours —
because their justification ("other agents will fix it soon") has no analogue here.

## Which instrument sees which change

The reason this is not one experiment: the four changes are visible to different things,
and C4 is invisible to the loop-level harness entirely.

| | Tier 1 | Tier 2-style replay | Tier 3 |
|---|---|---|---|
| C1 handoffs | A10, A11 — produced and answered | — | 3b: does the information change the code? |
| C2 failure path | A13 (fault-injected, capability check) | — | — |
| C3 state file | A12 | — | — |
| C4 waivers | invisible — waivers need MAJORs, which healthy runs may not produce | **the only instrument** | — |

### New Tier 1 assertions (built)

Applicability is read from each arm's own `SKILL.md`, recorded as `flow_dir` in
`meta.json`, so v0.2.6 comes back `n/a` rather than failing for omitting something it never
claimed. Same principle as A9.

- **A10 handoffs collected** — `HANDOFFS.md` exists, carries at least one entry per plan
  unit, and every entry has all four headings. Catches the handoff being requested and
  then dropped on the floor.
- **A11 handoffs answered** (best-effort) — if any DEVIATIONS or CONCERNS body has real
  content, `LOOP_STATE.md`'s `Amendments & rebuttals` section is non-empty. Whether each
  disposition is *good* is a judgement call and does not belong in Tier 1. Returns `n/a`
  when nothing was raised, which is a legitimate outcome and not a pass.
- **A12 state rewritten** — exactly one `Phase:` marker survives in the final file, ≤ 60
  lines, and no schema key missing. The single marker is the proxy for rewrite-not-append:
  an appended log accumulates one per phase boundary. Bound is ~40 lines in the skill; 60
  here so formatting slack is not scored as a failure.

`HANDOFFS.md` was also added to A9's loop-artifact list, without which the new arm would
have failed its own ownership assertion for writing a file the loop authors by design.

### Correction, made mid-run: C4 is not invisible to Tier 1 — it is *mis-scored* by it

The table above says C4 is invisible to Tier 1 because waivers need MAJORs. That is right
about C4 itself and wrong about its consequences. When a MAJOR does appear and no ground
allows waiving it, the gate blocks and the loop correctly stops without shipping — and
A4, A5 and A6 scored that identically to a loop that simply failed to commit. Tier 1 was
therefore set up to penalise v0.3 *for the change working*, which is worse than being blind
to it. This surfaced on `v0.3/t04-api-v1-2`, the first run in the matrix to produce a MAJOR
at all.

Fixed by withholding A4–A6 on a blocked gate and recording a `gate` disposition per run
(see `bench/README.md`), plus **A14**, which checks the inverse: that a blocked gate did not
push anyway. Two things to keep honest about this:

- It does **not** make Tier 1 an instrument for C4. Nothing here shows v0.2.6 *would* have
  waived that finding — all three of its `t04` runs found zero MAJORs, so its gate never
  faced the decision. The waiver replay is still the only instrument. The fix stops Tier 1
  producing a *wrong* number; it does not produce a right one.
- The blocked run was blocked by a defect its own Phase 8 fix round introduced. Fix rounds
  adding MAJORs is worth watching on its own, independent of either arm.

A9 was also fixed at the same time: `covered()` only honoured a glob in trailing position,
so a unit declaring `test/controllers/api/v1/*_test.rb` was scored as violating the path it
had just declared. Both fixes landed mid-matrix, so every run is re-scored by the identical
final version with `bench/tier1/rescore.sh` before any number here is quoted.

### A13 — the failure path (to build)

C2 never fires on a healthy run, so it needs fault injection. The cheapest deterministic
version is a task containing one unit that cannot succeed: a new task file requiring a gem
the pinned bench app cannot install offline, leaving the rest of the plan sound. Assert
that exactly one re-dispatch occurred, the dependent wave never started, `LOOP_STATE.md`
names the failure, Phase 9's learnings step still ran, and the main checkout is clean.

This is a **capability check, not a comparison** — v0.2.6 specifies no behaviour here, so
there is nothing to be better than, the same way the README treats genericity.

### The waiver replay (to build)

C4 is orchestrator-side, so Tier 1 cannot reach it and Tier 3 cannot see it. It needs its
own isolation experiment in Tier 2's shape: freeze the artifacts, vary one prompt, no loop
and no tools.

```
bench/waivers/
  corpus/w01-<case>/
    plan.md            the contract, with an explicit out-of-scope section
    diff.patch         the implementation
    rating.md          a RATING-round-1 with ~6 MAJORs, mixed
    truth.json         per finding: waivable | not-waivable, and on which ground
  gates/v0.2.6.md      "fixed or waived with a one-line written reason"
  gates/v0.3.md        the three enumerated grounds
  replay.sh / score.py mirroring tier2/
```

The MAJORs must be mixed by construction: some genuinely out of scope per `PLAN.md`, some
pre-existing on main, some contradicting an approved assumption, and — the ones that matter
— several that are none of those but are *tempting*, because fixing them costs a round.
Report waiver rate, wrong-waiver rate (waived something not waivable), and over-fixing rate
(fixed something legitimately waivable, which is the cost side of C4). Run both gates at
n=5, as Tier 2 does.

## Arms, tasks, and n

Both arms need fresh runs. **v0.2.6 has never been run in Tier 1** — `RESULTS.md` carries
v0.2.2 and v0.2.4 only — so the published numbers are not a usable baseline.

```sh
BENCH_STAMP=v03 bench/tier1/run-all.sh \
  v0.2.6:t04-api-v1 v0.3:t04-api-v1 \
  v0.2.6:t03-archived-nil-bug v0.3:t03-archived-nil-bug
```

- **t04-api-v1** is the Full-tier task — 4 units across 2 waves — and the only one where
  waves, handoffs and fix rounds actually fire. **n=3 per arm.**
- **t03-archived-nil-bug** is Light — 2 units, 1 wave — included only to check the new
  bookkeeping does not inflate small work. **n=2 per arm.**
- t01 and t02 have never been run. Leave them out; they would add a variable, not a
  measurement.

n=3 on the Full task follows this harness's own lesson: byte-identical arms differed by
37% in wall clock and 23% in cost, so any cost claim under n=3 is reading noise. The binary
assertions are near-deterministic and n=2 is enough for them.

Ten full runs at roughly $11–16 each for the Full tier: **budget ~$120–140** before the
waiver replay and blind grading, which are cheap by comparison.

Then Tier 3 on the t04 branches, reusing the existing machinery unchanged:

```sh
bench/tier3/run-hidden.sh                        # both arms must stay 8/8
bench/tier3/grade.sh v0.2.6 v0.3 t04-api-v1      # BENCH_REPS=8, position alternated
```

## Predictions, recorded before running

Written down so a null result stays legible and cannot be reinterpreted afterwards.

1. **A10 passes 5/5 on v0.3, `n/a` on v0.2.6.** Low confidence in the count check
   specifically — the entry-per-unit regex assumes handoffs get appended verbatim, and an
   orchestrator that summarises three units into one entry fails A10 while doing the right
   thing. If that is what happens, the assertion is wrong, not the loop.
2. **A12 passes 5/5 on v0.3.** High confidence; it is a format check against a schema
   given verbatim in the skill.
3. **A11 fires on t04 and returns `n/a` on t03.** A four-unit, two-wave task should
   surface at least one deviation; a two-unit bugfix may legitimately surface none.
4. **Cost rises under 10% on t04.** The added work is text, not agents or rounds. Cutting
   230 lines of instruction barely moved cost in an earlier arm, so prose is not where the
   money is. If cost moves more than 10%, something behavioural changed that was not
   intended and needs finding before anything else is read.
5. **Blind grading moves less than ±0.5 on every axis.** C1 is the only change that could
   plausibly reach code quality, and it does so indirectly. Anything larger — in either
   direction — is more likely a confound than an effect at n=8.
6. **The waiver replay separates the arms.** This is the one place a real effect is
   expected: v0.2.6's gate should waive some tempting non-waivable MAJORs, v0.3's should
   not, at the cost of over-fixing some legitimately waivable ones.

## What sends a change back out

- **C1** — A10/A11 pass but findings-by-severity and blind grades are unchanged across
  n=3: handoffs are ceremony. Keep the four-field return (it costs nothing), drop the
  orchestrator's disposition obligation, which is the part that spends attention.
- **C1** — blind test_quality or fitness drops more than 0.5: the orchestrator's
  bookkeeping is displacing attention from the work. This is the specific risk of giving
  the orchestrator another role, which is the failure mode Cursor documented.
- **C3** — A12 passes but the `Trace` line is never accurate, or nobody ever reads one:
  keep the rewrite rule and the schema, cut `Trace` to what Phase 9 demonstrably uses.
  Honest caveat now: `Trace` only pays off if someone aggregates it across PRs. It is
  committed with the branch, so the data will exist either way.
- **C4** — over-fixing rate exceeds wrong-waiver rate reduction: the grounds are too
  narrow and are buying correctness with fix rounds that a human would have waived. Widen
  the enumeration; do not return to unbounded judgement.
- **Any** — cost on t04 rises more than 25% with no assertion or grade moving.

## Confounds, stated up front

1. **Four changes ship in one arm.** This measures them together. Isolating any one needs
   an ablation arm — a flow directory with that section removed — which the harness
   supports and which is worth paying for only if the combined arm moves something.
2. **The plan checkpoint is still unmeasured.** Both arms run `--auto` because it cannot
   be exercised headless. C4's autonomous-mode carve-out — nothing on a critical path may
   be waived without a human — therefore ships untested, and the bench app declares no
   critical paths anyway. Check it by hand.
3. **A11 is best-effort**, like A7 and A9: it checks that dispositions were recorded, not
   that they were right.
4. **Same author** wrote the skill, these changes, the assertions and this plan. The
   mechanical ground truth limits the damage; the waiver corpus's `truth.json` is the part
   most exposed to it and should be reviewed by someone else before a number is quoted.
