# Benchmark results

dev-loop v0.1.0 through v0.3. Three experiments: an execution harness (Tier 1), a
gate-isolation replay (Tier 2) and blind grading against hidden acceptance tests (Tier 3).
Raw run output lives in gitignored `bench/results/`; this file is the record.

Everything below was produced by `bench/tier1/run-all.sh` and `bench/tier2/replay.sh` on a
pinned Rails 8.1 app at `c0d1ffa`, same task text and same orchestrator model for every arm.

---

## Tier 1 — execution (11 runs)

| arm / task | n | A1 main | A3 boot | A4 commit | A5 push | A6 ship | A7 order | A9 own |
|---|---|---|---|---|---|---|---|---|
| v0.1 t03 | 3 | 3/3 | **0/3** | 3/3 | 3/3 | 3/3 | 2/3 | n/a |
| v0.1 t04 | 1 | 1/1 | **0/1** | 1/1 | 1/1 | 1/1 | **0/1** | n/a |
| v0.2.0 t03 | 1 | 1/1 | 1/1 | — | — | — | 1/1 | 1/1 |
| v0.2.1 t03 | 1 | 1/1 | 1/1 | 1/1 | **0/1** | **0/1** | 1/1 | **0/1** |
| v0.2.2 t03 | 3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | **0/3** |
| v0.2.2 t04 | 1 | 1/1 | 1/1 | 1/1 | 1/1 | 1/1 | 1/1 | **0/1** |

### Cost and wall clock

Reported as mean ± stdev. Single-run figures are not comparable: v0.2.1 and v0.2.2 are
byte-identical apart from nine lines that execute only at the very end, and differed by
37% in wall clock and 23% in cost.

| arm / task | cost | wall clock |
|---|---|---|
| v0.1 t03 | **$5.88 ± 1.25** (n=3) | 1402 ± 196 s |
| v0.2.2 t03 | **$12.15 ± 0.57** (n=3) | 2530 ± 147 s |
| v0.1 t04 | $6.35 (n=1) | 1526 s |
| v0.2.2 t04 | $15.99 (n=1) | 3105 s |

On t03 the separation is far larger than the spread: **v0.2.2 costs 2.07× and takes 1.80×**
as long. That difference is real, unlike the single-run figures reported earlier.

### What holds

- **v0.1 usually fails to provision the worktree.** A3 failed 4 of 5 across both tasks
  (t03 0/3, t04 1/2). An earlier version of this file called it deterministic on 4/4; a
  later t04 run provisioned correctly, so it is a strong tendency, not a certainty.
  `git worktree add` takes tracked files only, so `config/master.key` is absent unless the
  loop copies it. The benchmark app's suite does not read credentials so it stayed green;
  an app that does would not boot.
- **v0.2.x keeps the main checkout clean** — 6/6. So does v0.1, 4/4.
- **v0.1 reviews on red intermittently.** A7 failed 1 of 3 on t03 and 1 of 1 on t04.
  v0.2.x passed 6/6: the mechanical gate is doing its job.
- **v0.2.x violates its own ownership contract** — A9 failed 4/4. Agents wrote undeclared
  files (`test/models/archived_backfill_migration_test.rb`, `app/models/project.rb`,
  `.gitignore`), and in one case the plan declared no `db/migrate/` ownership at all for a
  schema fix. The contract is stated and not enforced. **This is the top open defect.**
- **Tier selection works.** t03 → `Light — 2 units`, t04 → `Full — 4 units across 2 waves`.
  Plan cap held at exactly 120 lines on both Light runs.

### Diff size, decomposed

The headline 714 vs 1708 insertions on t04 is mostly not application code:

| t04 | v0.1 | v0.2.2 | ratio |
|---|---|---|---|
| everything | 714 | 1708 | 2.4x |
| code only (no `.md`) | 351 | 858 | 2.4x |
| **app code** (`app/`, `config/`, `db/`) | **99** | **144** | 1.45x |
| **test code** | **252** | **711** | 2.8x |

Tier 3 answers what this means.

---

## Tier 2 — gate isolation (60 rater calls)

One frozen plan/diff pair, six variants, both gate designs, 5 reps each.

| | v0.1 gate | v0.2 gate |
|---|---|---|
| Caught seeded defects | 25/25 | 23/25 |
| False-blocked correct code | **5/5** | **0/5** |
| Net | blocked 30 of 30 | discriminates |

v0.1's 100% catch rate is degenerate — it blocked everything, so it carries no information.

The scores themselves are informative and stable: stdev ≤ 0.49, and they rank the variants
correctly (authz 3.6 < cap 4.2 < missing-criterion 5.2 < nil-deref 7.0 < coverage 7.2 <
good 7.6). The failure is not noise. It is that **a scalar collapses severity**:

```
nil_dereference (crashes on any null description):  7, 7, 7, 7, 7
good            (shippable, minor nits):            7, 7, 8, 8, 8
```

No integer threshold separates those. v0.2's severity gate separated them 5/5 vs 0/5.

v0.2's weak spot: `coverage_removed` blocked only 3/5 — "an endpoint with no test at all"
sits on the BLOCKING/MAJOR line and needs an explicit carve-out to be deterministic.

---

## Claims that did not survive

Recorded because they were reported before they were checked.

1. **"v0.1 never commits or pushes, so `gh pr create` fails."** It committed and pushed in
   4/4 runs. The skill genuinely omits the step; the orchestrator did it anyway.
2. **"v0.1's subagents will corrupt the main checkout."** A1 passed 4/4.
3. **"The 8.5 threshold is unreachable."** True on the Tier 2 corpus (max 8 across 30
   runs), false in a live loop — v0.1's rater scored 9 and the gate passed first round.
   Corpus-specific, not structural.
4. **"Scores drift between rounds."** stdev ≤ 0.49. They are stable.
5. **Two earlier Tier 1 result sets** were harness artifacts — one a timeout misread as
   failure, one a run-directory collision that blended a stale `meta.json` with a live
   transcript. Both are fixed; see the `fix(bench)` commits.
6. **"v0.3's rater catches a defect v0.2.6's ships blind."** Reported from a MAJOR count of
   0/5 against 3/3 before any finding was read. Both arms detect the defect at comparable
   rates and both grade it MINOR; the one BLOCKING was a 500 in a run whose code was worse,
   and the supporting "CPU denial-of-service" needed a 100k-digit parameter no web server
   accepts. See the v0.3 section below.

The conclusion that survives all of this is narrower than the one it started as: not
"numeric gates are theatre" but **a scalar cannot express severity, and v0.1's definition
of blocking structurally excluded a real pre-ship defect** — which is what happened in a
live run, where the gate passed work its own rater flagged as needing action before ship.

---

## Limits

- One repo, one stack, two tasks. n=3 only on t03.
- Tier 2 is six variants of a **single** plan/diff pair.
- Same author wrote the skill, the defects, the rater prompt and this harness.
- **No code-quality measurement anywhere.** Tier 1 asserts mechanics; Tier 2 tests a
  grader. Neither shows which flow writes better software. That needs Tier 3.
- v0.2's plan checkpoint cannot run headless, so every v0.2.x arm ran `--auto`. Its
  highest-value safeguard is untested here.


---

## Tier 3 — does either write better software?

Both t04 branches already existed, so this needed no new loop runs.

### 3a. Hidden acceptance tests

Eight tests written from the **task text**, never seen by either flow, and deliberately
tolerant of response shape — v0.1 returns `{data:, pagination:}`, v0.2.2 returns
`{projects:, pagination:}`, and the task specified behaviour, not a JSON schema. They cover
the list and single endpoints, archived exclusion, pagination state, the server-side cap
under `per_page=100000`, real paging without overlap, the untouched legacy endpoint, and
malformed params.

| arm | result |
|---|---|
| v0.1 | **8 runs, 19 assertions, 0 failures** |
| v0.2.2 | **8 runs, 19 assertions, 0 failures** |

Functionally indistinguishable on the specification.

### 3b. Blind pairwise grading

Four graders, loop artifacts stripped (they identify the flow instantly), A/B position
alternated so position bias would surface as a split.

| arm | fitness | test_quality | simplicity | clarity |
|---|---|---|---|---|
| v0.1 | 8.25 ± 0.43 | 7.50 ± 0.50 | **8.25 ± 0.43** | **8.50 ± 0.50** |
| v0.2.2 | 7.75 ± 0.43 | 7.75 ± 0.43 | **3.75 ± 0.43** | **5.75 ± 0.43** |

**Overall preference: v0.1, 4 of 4.**

v0.2.2's 2.8x test code bought +0.25 on test quality and cost 4.5 on simplicity. The
graders' specific claims were checked against the source and all held:

- `Pagination` uses `extend self`; the `include Pagination` form appears only in a comment.
- The `StandardError` handler re-raises wherever `consider_all_requests_local`, and reports
  to a subscriber the app does not have — its own comment concedes it "currently writes
  nothing anywhere".
- 66 comment lines in 145 lines of app code (45%), against v0.1's 13 in 86 (15%).

### What this overturns

An earlier recommendation in this exercise — that v0.2.2 is worth roughly double the cost
because it wins on correctness — does not survive. It wins the **mechanical** assertions
(worktree provisioning, never reviewing on red). It produces **functionally equivalent**
code, judged **materially worse** by blind graders, for **2.07x the money** and **1.80x
the time**.

The loop scored simplicity all along, but scores are telemetry and gate nothing, so
nothing resisted accretion — and fix rounds, where a MAJOR must be "fixed or waived",
systematically reward adding code. Addressed in 0.2.4 by making disproportion a MAJOR
finding in its own right; **not yet re-measured.**

### Limits specific to Tier 3

One task, one pair of implementations, four graders. LLM graders may carry a general
preference for concision, which is why every claim above was verified against the source
rather than taken on the grader's word. The hidden suite tests the specification; it
cannot see maintainability, which is exactly what 3b is for and exactly where a grader is
least reliable.


---

## Tier 3, round 2 — after the fixes (v0.2.4)

Two v0.2.4 runs and a second v0.1 run on t04, then the same hidden suite and blind grading
across **two independent implementation pairs**, position alternated, 8 grader calls.

### Mechanical

v0.2.4 scored **8/8 on both runs**, including A9, which was 0/4 before the post-wave
ownership check. Cost fell from $15.99 (v0.2.2, n=1) to **$11.44 ± 0.21** (n=2).

### Size

| arm | app lines | test lines | comment density |
|---|---|---|---|
| v0.1 #1 / #2 | 99 / 133 | 252 / 296 | 15% / 26% |
| v0.2.2 #1 | 144 | 711 | 45% |
| **v0.2.4 #1 / #2** | **44 / 39** | 155 / 203 | 2% / 0% |

v0.2.4 became the smallest implementation of any arm without becoming degenerate: it
dropped a base controller and a pagination concern that each had exactly one caller,
inlined the logic into a 37-line controller, and kept one comment — explaining a param
coercion that is genuinely non-obvious. All four t04 branches pass the hidden suite 8/8.

### Blind grading, both pairs combined

| arm | fitness | test_quality | simplicity | clarity |
|---|---|---|---|---|
| v0.1 | **8.62** | **8.12** | 5.62 | 7.50 |
| v0.2.4 | 7.88 | 7.25 | **8.88** | **8.38** |
| delta | −0.75 | −0.88 | **+3.25** | **+0.88** |

**Preference: v0.2.4 5, v0.1 3** — against **v0.2.2's 0–4** on the same task.

At n=8 a 5–3 split is not a win, it is parity. The dimension scores are the real signal:
the disproportion rule moved simplicity by +3.25 and cost 0.88 of test quality.

### The regression the fix caused

Graders named it precisely: v0.2.4 lost the duplicate-name test pinning the `:id`
tiebreaker, and weakened a page-cap assertion to a bound its fixture could not exercise.
0.2.4 told fix rounds "removing code is a legitimate fix" and that was applied to
assertions. Addressed in 0.2.5 — coverage may only fall when the code it covered is gone.
**Not yet re-measured.**

### Where this leaves the comparison

After four rounds of fixes, against v0.1 on t04:

- **Mechanical**: v0.2.x clearly ahead — worktree provisioning 2/2 vs 1/5, ownership 2/2
  vs n/a, gate ordering 2/2 vs 1/2.
- **Judged quality**: parity. Better simplicity and clarity, slightly worse fitness and
  test quality.
- **Functional**: identical. Every branch of both arms passes the hidden suite.
- **Cost**: v0.2.4 $11.44 vs v0.1 $6.22 — still **1.84x**.

The 2x buys process guarantees, not better code. Whether that is worth it depends on
whether the guarantees matter for the work at hand: on a repo where a worktree cannot boot
without copied secrets, or where parallel agents genuinely collide, they do. On a small
single-agent change they do not.


---

## v0.2.6 vs v0.3 — Tier 1 (10 runs)

Four changes shipped together in v0.3, pre-registered in `bench/PLAN-v0.3.md` before the
run: C1 four-field unit handoffs the orchestrator must answer and the rater receives, C2 a
re-dispatch-once-then-stop path for a failed unit, C3 `LOOP_STATE.md` rewritten to a fixed
schema, C4 MAJOR waivers restricted to three enumerated grounds. Five runs per arm across
two tasks, same pinned app, same orchestrator model.

### Mechanical

Every binary assertion passed on both arms, all ten runs — A1–A7, A9, A14, and on v0.3 the
three new information-flow assertions A10–A12. Nothing regressed, and nothing separates the
arms here. That was the prediction and it held.

| arm / task | n | cost | wall clock | orchestrator tokens out |
|---|---|---|---|---|
| v0.2.6 t03 | 2 | $5.61 ± 0.69 | 811 ± 113 s | 21.0k |
| v0.3 t03 | 2 | **$4.92 ± 0.43** | **679 ± 42 s** | 20.9k |
| v0.2.6 t04 | 3 | **$6.94 ± 0.42** | **1140 ± 97 s** | 25.6k |
| v0.3 t04 | 3 | $7.47 ± 0.38 | 1249 ± 94 s | 34.0k |

Cost is flat overall: +7.6% on t04, −12.3% on t03, both inside the spread and well inside
the pre-registered 25% rollback threshold. The orchestrator writes 33% more on t04 — the
handoffs and the state schema being recorded — and it does not reach the bill. (v0.2.6 t04
had one run at 7982 tokens out against 22–29k for its siblings; the 25.6k figure excludes
it, and including it would only widen the gap.)

### The severity gap, and why it is not what it first looked like

v0.2.6 returned **0 BLOCKING and 0 MAJOR in all five runs**. v0.3 found a MAJOR in **all
three t04 runs** and one BLOCKING, and ran a second rating round 3/3 on t04 against
v0.2.6's 1/3. The first reading of that — v0.3's rater catches real defects v0.2.6's misses
— **did not survive checking, and is recorded here because it was written down before it was
checked.**

Four of six t04 runs wrote the same thing: `params[:page].to_s.to_i` with no upper bound,
echoed back in the response. Tracing what each rater did with it:

| run | `page` bound | rater saw it? | called it | outcome |
|---|---|---|---|---|
| v0.2.6 #1 | none | **no** | — | shipped |
| v0.2.6 #2 | none | yes | MINOR | shipped |
| v0.2.6 #3 | `clamp(1, 2**31-1)` | n/a — verified the clamp | — | clean |
| v0.3 #1 | none | yes | MINOR | shipped |
| v0.3 #2 | none, **and no offset guard** | yes | BLOCKING, then MAJOR | blocked |
| v0.3 #3 | `clamp(1, 1_000_000)` | n/a | — | clean |

Detection is **1 of 2 for v0.2.6 and 2 of 2 for v0.3** — indistinguishable at these numbers.
Both arms call it MINOR when they see it. v0.2.6 #2's rater not only found it but assessed
it correctly: *"Only a client that sent the bignum can hit this, so the impact is low."*

v0.3 #2's BLOCKING was **a different and genuinely worse bug**: that run's code omitted the
offset guard, so a large page raised `SQLite3::MismatchException` and returned a 500. The
rater was right, but it was catching worse code, not looking harder. Its round-2 MAJOR — the
residual echo, after the crash was fixed — is the single place any rater graded this defect
above MINOR.

An earlier draft of this section called that echo a CPU denial-of-service on the strength of
a 84.6 ms measurement. That figure needs a **100,000-digit** `page` parameter, well past what
a web server will accept in a request line. At lengths that actually arrive:

```
  1,000 digits -> 0.04 ms      8,000 digits -> 0.76 ms
```

The MINOR raters were right and the measurement was mine, not theirs.

**So there is no evidence here that v0.3's rater is better.** The MAJOR-count gap is rater
severity variance on a low-impact finding, plus one run whose code genuinely crashed. The
handoffs-reaching-the-rater hypothesis is unsupported — and note the handoffs *did* carry the
information: v0.3 #1's fix-round handoff says outright *"F3: a bignum `page` param is echoed
verbatim"*, and that run shipped anyway.

### C4: the one observation points at its cost, not its benefit

v0.3 #2 spent its only fix round on the 500, then blocked on the residual echo because no
waiver ground applied. That is the loop refusing to ship over something worth 0.76 ms, which
`bench/PLAN-v0.3.md` pre-registered as C4's failure mode:

> **C4** — over-fixing rate exceeds wrong-waiver rate reduction: the grounds are too narrow
> and are buying correctness with fix rounds that a human would have waived.

One run is not a rate, and the grounds arguably worked as designed — a MAJOR that fits none
of the three grounds is supposed to be fixed. But the single C4 observation in this matrix is
a **plausible false block**, not a catch. v0.2.6 never found a MAJOR, so its gate never faced
a waiver decision, and nothing here shows what it would have done. The waiver replay corpus
remains the only instrument, exactly as the plan said before the run.

Worth carrying forward independently of either arm: **a fix round introduced a MAJOR** —
v0.3 #2's Phase 8 fixer rewrote the page handling and left the bound off.

### A scoring bug found mid-run, and what it cost

A4–A6 ask whether work shipped, and scored the blocked run identically to a loop that
simply failed to commit — so Tier 1 was set up to penalise v0.3 *for its gate working*.
Fixed by withholding A4–A6 on a blocked gate, recording a per-run `gate` disposition, and
adding **A14** for the inverse case: a blocked gate that pushes anyway. A9 was fixed at the
same time — `covered()` honoured a glob only in trailing position, so a unit declaring
`test/controllers/api/v1/*_test.rb` was scored as violating the path it had just declared.

Both fixes landed mid-matrix, so every run was re-scored through the identical final version
with `bench/tier1/rescore.sh`; each run's original score is preserved as
`results-asrun.json`. The rescore moved exactly five assertions and nothing else.

**Every false negative the fixes corrected was on v0.3** — the arm being argued for. The
fixes are defensible on their own terms (the glob bug is unambiguous; the blocked-gate logic
mirrors the truncation guard already in `assert.py`), but "the author of the skill also
wrote the assertions, found them wrong mid-run, and the correction happened to help only his
own arm" is the same-author confound in its sharpest form. It wants outside review before
any of these numbers are quoted.

---

## Retraction — arm and date were confounded, and the effects were smaller than the confound

**Every quantitative comparison between arms in the v0.3 matrix is withdrawn.** Arms were run
one per day — v0.2.6 and v0.3 on Sep 16, v0.3.1 on Sep 17, v0.3.2 on Sep 18 — and no arm was
repeated across days, so "which arm" and "which day" are the same variable.

Running the **byte-identical v0.3 skill** a second time, as `v0.3-ctl`, measured what that
was worth:

| v0.3 skill text | cost | wall | shipped a defect |
|---|---|---|---|
| Sep 16 | $7.47 ± 0.38 | 1249 ± 94 s | 1/3 |
| Sep 18 | **$12.36 ± 2.51** | **2361 ± 622 s** | **3/3** |

+65% cost and +89% wall clock with nothing changed. That is larger than any difference this
matrix attributed to a skill change, including the +56% that was reported as v0.3.1 tripping
the pre-registered cost condition. **It did not trip it. The condition fired on an artifact.**

Specifically withdrawn:

- *"v0.3.1 costs 56% more than v0.3."* Same-day, v0.3.2 came in **below** the v0.3 control.
- *"v0.3 ships fewer defects than v0.2.6 (1/3 vs 2/3)."* The same text shipped 1/3 on Sep 16
  and 3/3 on Sep 18. The probes are sound; what they measured here was the day.
- The `RESULTS` and `CHANGELOG` framing that called the probe result "the first outcome
  measurement that goes to what the loop is actually for". It was, in method. Not in fact.

What survives is not measured but structural, and provable by reading: ground 3 keyed to an
approval the Phase 3 checkpoint issues, and that checkpoint never fires in an autonomous run,
so the ground could never apply. And across nine end-to-end runs of v0.3.1, v0.3.2 and the
control, the gate used **zero waivers and zero rebuttals** — the clause all this refining went
into governs a decision the loop does not make on this task.

**Required of any future run: interleave the arms within one session.** Run arm A run 1, arm B
run 1, arm A run 2, and so on. Every cost or rate comparison in this file that predates that
rule is indicative at best. The harness never had this rule, which is the actual defect.

---

## Shipped-defect probes — did anything broken reach main?

> **Withdrawn — see the retraction above.** The arms below ran on different days and the
> same skill text shipped 1/3 one day and 3/3 two days later. The instrument works; this
> application of it does not support a comparison.

Every Tier 1 assertion passed on both arms across ten runs, and the Tier 3a hidden suite
passes 8/8 on branches that carry a real defect, because it grades the task text and the task
text says nothing about hostile input. The unbounded-`page` defect was found by reading
controllers by hand. **No instrument here could see it**, which is the gap `bench/probes/`
closes: process conformance says the loop performed its ceremony, not that the ceremony
caught anything.

The probes are mechanical, need no model calls, and separate **carried** from **shipped** — a
run that wrote a defect and blocked at the gate is the loop working; one that wrote a defect
and pushed is the loop failing at its only job. Every other view in this harness collapses
those into one row.

| arm / task | n | carried | **shipped** | blocked |
|---|---|---|---|---|
| v0.2.6 t04 | 3 | 2/3 | **2/3** | 0/3 |
| v0.3 t04 | 3 | 2/3 | **1/3** | 1/3 |

| defect | severity | v0.2.6 | v0.3 |
|---|---|---|---|
| D1 unbounded `page` echoed back | minor | 2 carried, **2 shipped** | 2 carried, **1 shipped** |
| D3 radix-prefixed params misread | minor | 1 carried, **1 shipped** | 0 carried |

This reproduces mechanically what was previously found by hand, which is the point: the same
conclusion now comes from a script rather than from someone happening to read the right file.
Both arms write the defect at the same rate; v0.3 shipped one fewer because its gate blocked
a run.

**Both defect classes are minor by the probes' own labelling.** The honest claim is "v0.3
shipped one fewer minor defect in three runs", not that it ships better code. D2, D5 and D6
never fired on any run — unexercised, not validated.

---

## Waiver replay — C4 isolation (10 gate calls)

C4 could not be measured from the loop matrix: waivers need MAJOR findings and the raters
produced almost none, so v0.2.6's gate never faced a waiver decision. This freezes one
plan/diff/rating triple and puts both Phase 8 gates in front of the same eight decisions,
5 reps each. The two gate prompts are byte-identical apart from the three-grounds paragraph.

`plan.md` and `diff.patch` are the real artifacts from `v0.2.6/t04-api-v1-2`. `rating.md` is
constructed — four findings re-graded from that run's real MINORs keeping their probe
evidence, four written against the same contract — with four findings legitimately waivable
(one per ground, plus a second on ground 3) and four not.

| gate | reps | waiver rate | wrong-waiver | over-fixing |
|---|---|---|---|---|
| v0.2.6 | 5 | 75.0% (30/40) | **50.0% (10/20)** | 0.0% (0/20) |
| v0.3 | 5 | 30.0% (12/40) | **5.0% (1/20)** | **45.0% (9/20)** |

Decisions were near-deterministic: 6 of 8 findings drew the same verdict in 5 of 5 reps from
both gates.

### The finding: ground 3 is inert in autonomous mode

**All nine of v0.3's over-fixes are the same ground.** Grounds 1 and 2 — out of scope,
pre-existing on main — worked perfectly, waived 5/5 by both gates. Ground 3, "contradicts an
assumption the **Phase 3 checkpoint approved**", almost never fired, and the gate says why in
its own words:

> *"A5, which nobody approved in this `--auto` run"* · *"C2 was a self-made rebuttal, not an
> approved assumption"* · *"A11 is unapproved in an autonomous run so no ground applies"*

In autonomous mode the Phase 3 checkpoint never runs, so no assumption was ever approved and
the ground is structurally unavailable. The gate is reading the rule correctly and
literally; the defect is in how the rule is written. Every autonomous run — which is every
run in every benchmark here, since the checkpoint cannot be exercised headless — has been
operating with one of its three waiver grounds switched off.

### A gap the enumeration does not cover: the finding is simply wrong

Both gates judged W7's severity overstated, and both were right — `as_json(only:)` drops the
column before serialisation, so the finding's "slow mobile connection" framing does not hold.
v0.2.6 waived it on exactly that basis. v0.3 **fixed it anyway**, saying so explicitly:
*"severity is overstated but that is not a waiver ground."*

Waiving and rebutting are different dispositions and the gate only offers the first. A rater
can be wrong, and the three grounds give the orchestrator no way to say so — it must either
implement a fix it believes is unnecessary, or claim a ground that does not apply.

### How much of this survives the author confound: less than it looks

Each arm's entire error rate comes from exactly two findings.

```
v0.2.6 wrong-waiver:  5x W7, 5x W8     (nothing else)
v0.3   over-fixing:   4x W3, 5x W6     (nothing else, both ground 3)
```

v0.2.6's waivers on W7 and W8 are not lazy — they are reasoned technical rebuttals, and at
least partly correct. On W8 it argued that Rails' `rescue_responses` already maps
`RecordNotFound` to a 404 application-wide, so the handler only changes the body. That is
true. **If my labels on W7 and W8 are wrong, v0.2.6's wrong-waiver rate is 0% and the entire
trade this table reports disappears.** Those two labels carry the whole headline.

Against the pre-registered rule in `bench/PLAN-v0.3.md` — *"over-fixing rate exceeds
wrong-waiver rate reduction: the grounds are too narrow"* — the result is a dead heat: 45
points of over-fixing against 45 points of wrong-waiver reduction. By the letter, C4 stays.
At a tie this fine, resting on two contested labels, the honest reading is that **the trade
is unresolved** and the actionable result is the ground-3 defect, which does not depend on
the labels at all.

### Round 2 — fixing ground 3 (v0.3.1)

Two changes to Phase 8, both motivated above: ground 3 now keys off an assumption, scope
decision or resolved critique point that `PLAN.md` **records**, rather than one a checkpoint
approved; and a **rebuttal** disposition exists for findings that are factually wrong,
requiring evidence rather than disagreement.

| gate | wrong-waiver | over-fixing |
|---|---|---|
| v0.2.6 | 50.0% (10/20) | 0.0% |
| v0.3 | 5.0% (1/20) | **45.0% (9/20)** |
| **v0.3.1** | **25.0% (5/20)** | **0.0% (0/20)** |

**The ground-3 fix worked exactly as intended.** Over-fixing went to zero: W3 and W6, which
v0.3 fixed 9 times out of 10, are now waived 5/5 with the correct ground named. That result
is clean and does not depend on the contested labels, because W3 and W6 are the two findings
whose waivability was never in dispute.

**It overshot on one finding.** W8 flipped from fixed to waived 5/5, taking wrong-waiver from
5% to 25%. The gate points at assumption A11, which records the controller-level `rescue_from`
— but A11 records the choice *to get a JSON 404 body*, while the finding attacks the handler's
*scope*. Loosening "approved" to "recorded" opened a path to waive a finding that argues
against the topic an assumption mentions rather than the decision it made.

So v0.3.1 strictly dominates v0.2.6 — half the wrong-waiver rate at the same zero
over-fixing — and against v0.3 it is a real trade: 20 points more wrong-waiver for 45 points
less over-fixing. Over-fixing is not merely a cost in money. On the Light tier the fix-round
cap is 1, so a round spent on a finding that should have been waived is the round that is not
available when a real one appears — which is exactly how `v0.3/t04-api-v1-2` blocked.

**The rebuttal disposition never fired.** Zero rebuttals in 40 decisions. This corpus
contains no wholly-wrong finding: W7 is *partly* wrong, and all three gates reasoned about it
correctly — v0.3.1 fixed it 5/5 while noting *"its mobile-wire impact claim is wrong (as_json
strips it) but the unused column read is real"*. That is the right call, so the rebuttal path
is **untested**, not refuted. Testing it needs a corpus finding that is simply false.

**Half of v0.3.1's bad grounds are bookkeeping, not judgement.** Of 10 unsupported ground
claims, 5 are W2 waived as `out_of_scope` when the truth says `pre_existing` — the right
decision under the wrong label. The other 5 are W8, which is a real error.

**Stopping here deliberately.** This is the second gate wording tuned against the same eight
findings, which I wrote. A third round would be fitting the corpus rather than the gate. The
W8 result suggests a narrower phrasing — the finding must contradict what the assumption
*decided*, not merely a topic it mentions — but that should be tested on a second case, by
someone who did not write the first.

### Limits specific to the waiver replay

- One case, eight findings, n=5. Two labels drive both headline rates.
- Three gate designs have now been scored against one author-written corpus. Treat the
  v0.3 → v0.3.1 comparison as a hypothesis, not a measurement.
- The rebuttal disposition is unexercised: no finding in the corpus is factually false.
- `truth.json` is author-labelled, as `bench/PLAN-v0.3.md` predicted would be this
  experiment's most exposed part. It needs outside review before any number here is quoted.
- The corpus rating is constructed. The loop's own raters do not produce MAJORs at this
  rate on this task, so the decision density is unrepresentative by design.
- Only the Light tier's cost framing was given. A Full-tier run has two fix rounds and the
  temptation to waive is correspondingly weaker.

---

### Limits specific to v0.3

- Two tasks, n=3 and n=2. The headline finding rests on three runs.
- Four changes in one arm. This measures them together and the ablation is not built.
- **No Tier 3 yet.** Nothing here shows v0.3 writes better software — only that its rater
  found a real defect that v0.2.6's shipped twice.
- Both arms ran `--auto`, so C4's autonomous-mode carve-out ships untested, as does C2's
  failure path: no unit failed in ten runs, so the re-dispatch path never executed.
