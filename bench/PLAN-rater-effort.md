# Benchmark plan — rater effort on Claude Opus 5.5

Every rating this project has recorded on `claude-opus-5-5` ran at `high` effort, because
that is the user-level Claude Code setting on the machine that ran them. Nothing in the
skill chose it. Anthropic's Opus 5.5 guide says effort levels do not map across models,
that `medium` (the API default) matches Opus 5 at `high` on code review, and that effort
should be measured, not carried over.

The one open defect in the gate is rater instability: on `coverage_removed` the shipped
v0.3 brief blocked 2/10 at `high` (bench/PLAN-v0.4.1.md). The second opinion on the margin
exists only because of that instability. If an effort level makes the verdict stable, the
second opinion can go.

## Run

Tier 2 replay, case `c01-api-pagination`, all six variants, brief `v0.3`, rater
`claude-opus-5-5`, three arms by effort: `medium`, `high`, `xhigh`. n=10 per (variant,
arm), 180 calls. The arms run as three concurrent processes, one per effort level, so they
overlap in time rather than alternating call by call; `high` is re-run in the same session
instead of reusing the 2026-09-28 result.

## Prediction

`xhigh` is more stable than `high` on `coverage_removed`; `medium` is no worse than `high`.

## Decision rule

A level is **stable** if every variant is unanimous (10/10 the same top severity), no
known-bad variant passes more than 1/10, and `good` blocks no more than 1/10.

1. If exactly one level is stable, pin the rater at that level, and remove the second
   opinion in a separate, measured change.
2. If more than one level is stable, pin the lowest.
3. If none is, pin nothing. If `medium`'s per-variant block counts are within 1/10 of
   `high`'s everywhere, record that `medium` is equivalent; take no action.

## What this cannot show

One corpus and one brief, rated outside a live loop, and a single `good` variant.
