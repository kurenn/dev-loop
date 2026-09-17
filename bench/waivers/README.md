# Waiver replay — isolating the Phase 8 gate

C4 (v0.3's three enumerated waiver grounds) cannot be measured by running the loop. Waivers
need MAJOR findings, and across ten full runs in `bench/tier1` the raters produced almost
none — v0.2.6's gate never faced a waiver decision at all. This replays one frozen
plan/diff/rating triple through both gate designs so the only variable is the waiver rule.

Same shape as `bench/tier2`, which isolates the rater. This isolates the gate.

## Running

```sh
BENCH_REPS=5 BENCH_STAMP=w01 bench/waivers/replay.sh
python3 bench/waivers/score.py bench/results/w01/waivers/w01-api-v1-pagination
```

Roughly 20 minutes and a few dollars at n=5. `BENCH_MODEL` defaults to opus for both arms.

## What it measures

| rate | meaning |
|---|---|
| waiver rate | how often the gate waived rather than fixed — descriptive, not a score |
| wrong-waiver | waived something the truth marks not-waivable: **a real defect ships** |
| over-fixing | fixed something legitimately waivable: **fix rounds a human would not have spent** |

Plus ground accuracy for v0.3, which is the only arm asked to name one. Claiming a ground
the truth does not support is how an enumeration gets talked around rather than applied.

## The corpus

`corpus/w01-api-v1-pagination/` — `plan.md` and `diff.patch` are the real artifacts from
`bench/results/v03/v0.2.6/t04-api-v1-2`, unmodified. `rating.md` is constructed: four
findings re-graded from that run's real MINOR findings with their probe evidence kept, four
written fresh against the same contract. Four are legitimately waivable and four are not,
and the not-waivable ones are deliberately *tempting* — each has a plausible-sounding reason
to let it through, because a gate that only refuses obvious nonsense is not being tested.

**`truth.json` is author-labelled.** The same person wrote the skill, the gate under test,
this corpus and these labels. `bench/PLAN-v0.3.md` predicted this would be the experiment's
most exposed component and it was right: in the first run, both headline rates turned out to
rest on the labels for exactly two findings, and the gates produced reasoned technical
rebuttals against both. Have someone else review the labels before quoting a number.

## Adding a case

Create `corpus/<id>/` with `plan.md`, `diff.patch`, `rating.md` and `truth.json`, then pass
the id to `replay.sh`. Prefer real plans and real diffs from `bench/results/`; a constructed
contract tends to make its own findings easy to classify, which is the failure mode this
whole directory exists to avoid.
