# dev-loop

<p align="center">
  <a href="https://kurenn.github.io/dev-loop/">Page</a> ·
  <a href="bench/RESULTS.md">Benchmark</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

A **development loop that stops when the work isn't ready**, as a Claude Code plugin. One
command chains nine phases with deliberate model tiers and a gate that can't be talked
around. Any stack.

| Phase | Who | Model |
|---|---|---|
| 1 · Triage & frame | the session | trivial work exits here; everything else picks a size tier |
| 2 · Plan | one agent | **fable** — worktree, provisioning, baseline, `PLAN.md` |
| 3 · Critique & revise | a *fresh* agent | **fable** — attacks the plan cold; then you approve |
| 4 · Execute | unit agents | **sonnet** — parallel within a wave, disjoint file ownership |
| 5 · Mechanical gate | the session | build · test · lint · typecheck · security · coverage |
| 6 · Adversarial review | Codex, else a fresh agent | challenges the approach, not just defects |
| 7 · Rate | an independent rater | **opus** — threshold-blind, severity-ranked |
| 8 · Gate & fix | unit agents | **sonnet** — zero blocking findings, delta-judged |
| 9 · Learnings & ship | the session | appends learnings, commits, pushes, opens the PR |

It stops **once**, after the plan, and waits for you. `--auto` runs it straight through.

## Install

```sh
/plugin marketplace add kurenn/dev-loop
/plugin install dev-loop@kurenn
```

## Usage

```sh
/dev-loop-setup             # once per repo
/dev-loop <feature or bug>  # run the loop
```

`/dev-loop-setup` is what makes the loop stack-agnostic. It detects and **verifies** how
this project installs, tests, lints, typechecks and scans, which gitignored files a fresh
worktree needs to boot, and which specialist subagents exist, then writes a
`## Dev-loop config` profile into `CLAUDE.md`. A command that fails verification is left
blank, and a blank check is *skipped and reported as skipped* — never assumed green.

## The gate

Not a score. It passes when all three hold:

1. Mechanical checks green against a pre-change baseline, **coverage not below** it
2. **Zero blocking findings** — incorrect behavior, data loss, a security hole, or an unmet
   acceptance criterion
3. Every major finding fixed, or waived with a written reason

The rater still emits 1–10 axis scores. They go in the PR body as telemetry and gate
nothing, because an averaged score cannot express severity — see the benchmark.

## Optional accelerators

Auto-detected, neither required:

```sh
/plugin install codex@openai-codex   # phase 6: out-of-family adversarial review
/plugin install roundhouse@kurenn    # phase 4: Rails specialist subagents
```

Without codex, phase 6 falls back to a fresh in-family agent — it shares training and blind
spots with the implementers, so it is materially weaker, and the PR says so. Without a
GitHub remote the loop still commits and pushes, then hands you the PR command.

## What the benchmark found

Full method and raw numbers in [`bench/RESULTS.md`](bench/RESULTS.md) — 17 full loop runs,
60 gate replays, 24 blind gradings, hidden acceptance suites, all on a pinned Rails app.

**For it**

- An unguarded loop failed to provision a bootable worktree in **4 of 5 runs** and reviewed
  red code in **2 of 5**. This loop: 8/8 on every mechanical assertion.
- A scored gate (`overall ≥ 8.5`) passed work its *own* rater flagged as needing action
  before shipping — a latent Postgres incompatibility. Severity catches what an average
  hides. On a seeded corpus the scored gate blocked **30 of 30** artifacts including
  correct code; the severity gate caught 23 of 25 defects and false-blocked none.
- Guarantees expressed as **checks** held across every version. Guarantees expressed as
  adjectives traded against each other — telling the loop to be proportionate cost test
  quality until coverage became a check.

**Against it**

- It costs roughly **2×** a loop without the guarantees. An ablation cutting 230 lines of
  instruction changed that almost not at all: the spend is the phases, not the prose.
- On blind-graded code quality it reaches **parity**, not superiority. You are buying
  process guarantees, not better code.

**Verified at release** — 0.2.6 passes 8/8 mechanical assertions on both regression runs.
Its coverage floor is carried over from an ablation that measured it, not from a blind
grading of 0.2.6 itself, and cost did not improve: $13.40 ± 1.35 against 0.2.4's
$11.44 ± 0.21, which the spreads cannot cleanly separate from run-to-run variance.

**Not established** — everything above is one Rails repo and two tasks. The stack-agnostic
claim is designed for but unmeasured, and no result here should be read as holding on a Go
or Node codebase until someone runs it there.

Use it where the guarantees bind: a repo whose worktree can't boot without copied secrets,
genuinely parallel agent work, or changes where a defect is expensive. On a small, safe
change, Light tier exists so you aren't paying for guarantees that were never going to fire.

## License

MIT © Abraham Kuri
