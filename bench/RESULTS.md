# Benchmark results

dev-loop v0.1.0 vs v0.2.x. Two experiments: a gate-isolation replay (Tier 2) and an
execution harness (Tier 1). Raw run output lives in gitignored `bench/results/`; this file
is the record.

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
