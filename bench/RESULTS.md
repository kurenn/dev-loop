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

- **v0.1 never provisions the worktree.** A3 failed 4/4 across both tasks — deterministic.
  `git worktree add` takes tracked files only, so `config/master.key` is absent. The
  benchmark app's suite does not read credentials so it stayed green; an app that does
  would not boot.
- **v0.2.x keeps the main checkout clean** — 6/6. So does v0.1, 4/4.
- **v0.1 reviews on red intermittently.** A7 failed 1 of 3 on t03 and 1 of 1 on t04.
  v0.2.x passed 6/6: the mechanical gate is doing its job.
- **v0.2.x violates its own ownership contract** — A9 failed 4/4. Agents wrote undeclared
  files (`test/models/archived_backfill_migration_test.rb`, `app/models/project.rb`,
  `.gitignore`), and in one case the plan declared no `db/migrate/` ownership at all for a
  schema fix. The contract is stated and not enforced. **This is the top open defect.**
- **Tier selection works.** t03 → `Light — 2 units`, t04 → `Full — 4 units across 2 waves`.
  Plan cap held at exactly 120 lines on both Light runs.

### Unexplained

v0.2.2 produced 1708 insertions on t04 against v0.1's 714 — more than double the code for
the same task. Whether that is thoroughness or bloat is not something these assertions can
answer; it needs the blind-graded Tier 3 that has not been run.

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
