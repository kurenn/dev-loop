# Benchmark plan — v0.4 severity boundary vs the second opinion

v0.4.0 shipped two answers to one problem: on `coverage_removed` the v0.3 rater brief
called the same untested endpoint BLOCKING 3 times and MAJOR 2 times in five reps.

- **Second opinion** (shipped in 0.4.0): when a rating has no BLOCKING and at least one
  MAJOR, a second rater runs and the higher severity wins. Treats the variance.
- **Severity boundary** (`raters/v0.4.md`, not shipped): a behavioural acceptance
  criterion is met only when a test proves it, and an untested branch is MAJOR only when
  no criterion covers it. Removes the ambiguity that produces the variance.

The loop should carry one. This file is the pre-registration, written before the run.

## Run

Tier 2 replay, case `c01-api-pagination`, all six variants, arms `v0.3` and `v0.4`
alternated call by call in one session, **n=10 per (variant, arm)**, rater
`claude-opus-5-5` — 120 calls.

## Prediction

`v0.4` blocks `coverage_removed` on every rep, and does not block `good` more often than
`v0.3` does.

## Decision rule

The boundary replaces the second opinion — the second-opinion paragraph leaves SKILL.md —
if **all** hold:

1. `coverage_removed`: `v0.4` blocks ≥ 9/10.
2. `good`: `v0.4` false-blocks no more than `v0.3` + 1 (out of 10).
3. The other four seeded defects: `v0.4` catch rate is no lower than `v0.3`'s.

Otherwise the boundary is dropped and the second opinion stays. A void run (API refusals
outnumbering answers) decides nothing and is re-run.

## What this cannot show

One corpus, one clean variant, one session. It measures the rating brief in isolation,
not a live loop. Criterion 2 is the weak one: a stricter "met" rule could raise false
blocks on correct code whose criteria are covered only indirectly, and `good` is the only
variant that can show it.

## Deviation, recorded before results

The six variants ran as six concurrent `replay.sh` processes sharing one stamp, to cut
wall clock from ~4 h to ~40 min. Within each variant the arms still alternate call by
call, so the between-arm comparison keeps its interleave; only the variants overlap.

## Result — 2026-09-28, 120 calls, 0 void

| variant | truth | v0.3 blocked | v0.4 blocked |
|---|---|---|---|
| `authz_removed` | bad | 10/10 | 10/10 |
| `coverage_removed` | bad | **2/10** | 10/10 |
| `good` | good | 0/10 | **10/10** |
| `missing_acceptance_criterion` | bad | 10/10 | 10/10 |
| `nil_dereference` | bad | 9/10 | 10/10 |
| `page_cap_inverted` | bad | 10/10 | 10/10 |

Criteria 1 and 3 hold; **criterion 2 fails, 10/10 against 0/10.** The boundary is dropped
and the second opinion stays.

The failure is not noise — `v0.4` was unanimous on every variant. It blocked `good` for
the same three reasons on every rep: no test fetches an archived project by id, the cap
test checks the echoed `per_page` and not the rows returned, and auth is tested on `index`
only. All three are true of the reference implementation. So the boundary does not
stabilise the old gate; it defines a stricter "done", strict enough that the corpus's own
shippable code fails it. Whether a loop *should* refuse untested acceptance criteria is a
policy question this run can pose but not answer, and adopting that policy would need a
new ground truth for `good`, not a calibration claim.

`v0.3` on `coverage_removed` moved from 3/5 blocked to 2/10: the instability the second
opinion was added for is still there, and is larger than the first sample showed.
