# Shipped-defect probes

Adversarial checks run against every finished branch, asking one question: **did a known
defect class reach main?**

## Why this exists

Across ten runs of the v0.2.6 / v0.3 matrix, every Tier 1 assertion passed on both arms, and
the Tier 3a hidden acceptance suite passed 8/8 on branches that carried a real defect. The
defect was found by reading controllers by hand. **No instrument in this harness could see
it.**

That is the gap. Tier 1 measures whether the loop performed its process. Tier 3a measures
whether the code does what the task asked. Neither asks whether something broken got
through, which is the only outcome the gate exists to produce.

The distinction that makes this work is **carried vs shipped**. A run that wrote a defect and
blocked at the gate is the loop succeeding; a run that wrote one and pushed is the loop
failing at its one job. Every other view in this harness collapses those into the same row.

## Running

```sh
bench/probes/run-probes.sh bench/results/<stamp>
python3 bench/probes/summarize.py bench/results/<stamp>
```

No model calls — it copies each worktree to scratch, drops the probe in, and runs it. About
30 seconds for ten runs. Shipped-vs-blocked is read from the `gate` disposition that
`bench/tier1/assert.py` records, so probe runs after the matrix.

## Writing a probe

One file per task, `<task-prefix>_defect_probe.rb`, in the style of `bench/tier3/hidden/`:
shape-tolerant, because arms return `{data:,pagination:}` or `{projects:,pagination:}` and
grading one shape over the other grades conformity to whichever implementation you read
first.

Three rules, each learned the hard way:

- **A failing probe means the defect is present.** Read the output inverted.
- **Every probe declares its own severity**, next to the check. The first writeup of this
  benchmark called an unbounded page echo a "CPU denial-of-service" on the strength of a
  measurement needing a 100,000-digit parameter no web server accepts; at real lengths it
  costs 0.76 ms. Severity next to the probe is how that inflation gets caught by the harness
  rather than by a later reread.
- **Probe only defects a rater actually found.** Every check in `t04_defect_probe.rb`
  corresponds to a finding in `bench/results/v03`, and each shipped in at least one run.
  Inventing defect classes turns this into a test of the author's imagination.

`run-probes.sh` runs `ruby -c` on the probe before using it. A probe that does not parse
errors every test, which the summarizer would otherwise report as every defect being present
in every run — a catastrophic-looking result from a broken file, which happened on the first
run of this directory.

## Known gaps

**The instrument is sound; its first application was not.** The v0.3 matrix ran each arm on a
different day, and the byte-identical v0.3 skill shipped a defect in 1 of 3 runs on one day and
3 of 3 two days later. Shipped-defect rate is at least that sensitive to the service, so a
comparison between arms means nothing unless the arms were interleaved within one session. The
numbers this directory produced for that matrix are withdrawn.

D2, D5 and D6 have never fired on any run in the corpus. They are unexercised, not
validated: a probe that has only ever passed has not been shown to be capable of failing.
