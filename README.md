# dev-loop

A development loop for Claude Code that won't ship while anything is blocking.

```
       plan
        │
        ▼
       critique                  a second agent, blind to the planner
        │
        ▼
       approve                   --auto skips this stop
        │
        ▼
       implement                 parallel, disjoint file ownership
        │
        ▼
 ┌──▶  gate                      build · test · lint · typecheck · coverage
 │      │
 │      ▼
 │     review                    codex, adversarial
 │      │
 │      ▼
 │     rate                      opus, blind to the threshold
 │      │
 │      ▼
 │     blocking? ── none ──▶ ship
 │      │
 │      │ some
 │      ▼
 └───── fix                      capped, then it stops rather than lowering the bar
```

Findings return to the **gate**, not to the reviewer — every fix is re-checked against the
baseline before it is re-judged.

## Install

```sh
/plugin marketplace add kurenn/dev-loop
/plugin install dev-loop@kurenn
```

## Use

```sh
/dev-loop-setup             # once per repo
/dev-loop <feature or bug>  # run the loop
```

`/dev-loop-setup` is what makes the loop stack-agnostic. It detects and **verifies** how
your project installs, tests, lints, typechecks and scans, which gitignored files a fresh
worktree needs to boot, and which specialist subagents exist — then writes a
`## Dev-loop config` block into `CLAUDE.md`. A command that fails verification is left
blank, and a blank check is *skipped and reported as skipped*, never assumed green.

## The gate

Not a score. It passes when all three hold:

- Mechanical checks green against a pre-change baseline, **coverage not below** it
- **Zero blocking findings** — wrong behaviour, data loss, a security hole, or an unmet
  acceptance criterion
- Every major finding fixed, or waived with a written reason

The rater still emits 1–10 axis scores. They go in the PR body as telemetry and gate
nothing, because an average cannot express severity.

## Optional

Both auto-detected, neither required:

```sh
/plugin install codex@openai-codex   # out-of-family adversarial review
/plugin install roundhouse@kurenn    # Rails specialist subagents
```

Without codex the review falls back to an in-family agent that shares blind spots with the
implementers; the PR says so. Without a GitHub remote the loop commits and pushes, then
hands you the PR command.

## Benchmark

Built against its own benchmark — 17 loop runs, 60 gate replays, 24 blind gradings, hidden
acceptance suites. Full method and raw numbers in **[bench/RESULTS.md](bench/RESULTS.md)**.

The short version, including the parts that don't flatter it:

- An unguarded loop failed to provision a bootable worktree in 4 of 5 runs and reviewed red
  code in 2 of 5. This one passes 8/8 mechanical assertions.
- A scored gate (`overall ≥ 8.5`) passed work its own rater had flagged as needing action
  before shipping. On a seeded corpus it blocked **30 of 30** artifacts, correct code
  included; the severity gate caught 23 of 25 defects and false-blocked none.
- It costs roughly **2×** a loop without the guarantees, and cutting 230 lines of
  instruction barely moved that — the spend is the phases, not the prose.
- On blind-graded code quality it reaches **parity**, not superiority. You are buying
  process guarantees, not better code.
- One Rails repo, two tasks. The stack-agnostic claim is designed for but unmeasured.

Use it where the guarantees bind: a worktree that can't boot without copied secrets,
genuinely parallel agent work, changes where a defect is expensive. On a small, safe change
the Light tier exists so you aren't paying for guarantees that were never going to fire.

## License

MIT © [Abraham Kuri](https://github.com/kurenn)
