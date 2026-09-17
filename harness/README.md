# The OpenSOP harness

`dev-loop.sop.json` is the loop's phase skeleton as an [OpenSOP](https://opensop.ai)
process. It is a **second way to run the same loop**, not a replacement for the Claude Code
plugin, and not a fork of it.

The division is strict, and it is the only thing keeping this directory honest:

> **The harness sequences the phases. `SKILL.md` defines them.**

No step script restates what a phase does. Each one lifts its phase verbatim out of
`skills/dev-loop/SKILL.md` via `skill_section` in `lib/phase.sh` and hands it to an agent.
If the two ever disagree about what Phase 5 means, a benchmark comparing the plugin against
the harness is measuring drift instead of design.

## Why bother

The plugin's whole design lesson, repeated across every entry in `CHANGELOG.md`, is that
guarantees expressed as checks hold and guarantees expressed as prose trade away. Ownership
was breached in *every* benchmark run until it became a mechanical check. A numeric gate was
theatre until severity became mechanical.

The phase sequence itself is still prose. Nothing mechanically stops an orchestrator from
reviewing on red or declaring the gate met — which is why `bench/tier1` assertion A7 is a
*best-effort reconstruction from the transcript*. The harness makes four things mechanical
that the skill can currently only ask for:

| | How it becomes mechanical |
|---|---|
| **Phase order** | The runner walks `steps[]`. Phase 6 cannot precede Phase 5. |
| **The plan checkpoint** | An `approval` step that genuinely pauses and writes a `waiting_for_approval` receipt. `RESULTS.md` calls this the loop's highest-value safeguard *and* its least-measured one, because it cannot be exercised headless. Here it can: `opensop submit <run_id> plan-approval --output decision=approve`. |
| **Ownership and handoffs** | `steps/execute.sh` parses the wave structure, checks every changed path against declared ownership in bash, and appends each unit's four-field handoff to `HANDOFFS.md`. Code, not instruction. |
| **What actually happened** | `audit.jsonl`, `manifest.json` and `context.json` per run. A7's transcript archaeology becomes a file read, and `context.json` resumes an interrupted run without re-running completed steps — worth real money on a loop that costs $11–16 a run. |

## Use

```sh
git clone https://github.com/Chosen9115/opensop /tmp/opensop
export PATH="/tmp/opensop/cli/bin:$PATH"

harness/bin/dev-loop "add cursor pagination to the projects API"
harness/bin/dev-loop --auto --profile myproject.json "…"
```

The run pauses at the plan checkpoint. Approve or abort it:

```sh
opensop submit <run_id> plan-approval --output decision=approve
opensop show <run_id>          # manifest + per-step receipts
opensop heal <run_id>          # diagnose or re-run a failed step
```

`--auto` **removes** the approval step rather than skipping it, so a run either has a
checkpoint in its receipts or visibly does not. No flag buried in the inputs can make an
unattended run look supervised. It is also the only option available: see below.

`harness/test/smoke.sh` exercises the whole control flow — real bash, real git, real file
assertions — with the agent calls stubbed, so it costs nothing and takes about five
seconds. It asserts what the CLI does *today*, which is why it is also the conformance list
in the next section.

## What the local engine does not implement yet

Measured against `opensop` CLI 0.9.0, not against `SPEC.md` — the spec is ahead of the local
profile in four places that matter here. Each one is a concrete gap with a workaround in
place, and the workaround is worse than the feature.

**`exit_when` — not implemented at all** (zero occurrences in `cli/bin/opensop`, though
SPEC §3.15 defines it). The process file declares `exit_when`/`exit_outputs` on all five
early exits because that is the correct declarative statement and the server honours it.
Locally they are inert, so `lib/phase.sh`'s `halt()` enforces the stop by exiting non-zero.
The cost is a wrong word in the receipt: a trivial task or an aborted plan reads `failed`
rather than completed-early. A loop that stopped should look stopped, so this is the right
behaviour with the wrong label — but it is still a label that will confuse someone reading
`opensop ps`.

**`condition` — not implemented locally either.** The CLI says so itself: *"The local
validator CANNOT evaluate arbitrary condition expressions (no ConditionEvaluator here)"*.
Two consequences. Autonomous mode cannot skip the approval step, hence `--auto` rewriting
the process file. And the Light-tier skip of the paid adversarial review had to move inside
`steps/review.sh`, where it is invisible to the receipt that is supposed to record it.

**No `fan_out`, no local `loop`.** SPEC §9 puts `subprocess` fan-out at roadmap phase 4, and
`loop` is validated but not dispatched locally. Phase 4 of the loop is a fan-out over a unit
count nobody knows until the planner has run, so the wave walk lives inside
`steps/execute.sh` and does its own concurrency with `&` and `wait`. The engine is
single-threaded by design ("no daemons, no background processes"), so this is the script's
concurrency, not OpenSOP's. **This is the largest loss.** The runner holds a receipt saying
"the execute step ran", not one per unit, so the per-unit ownership contract — the most
load-bearing structure in the skill, and the thing the benchmark found breached in every run
before it was enforced — is exactly what the receipts cannot see. Fix rounds and gate
repairs are hidden inside their steps for the same reason.

**No specialist subagents.** The skill routes a model unit to `roundhouse:rails-models` when
the profile names it. A step script shells out to `claude --print`, which has no
`subagent_type`, so that routing is unavailable here. A real capability regression against
the plugin, not a cosmetic one.

### What would close the gaps

In rough order of what this harness would gain:

1. **`fan_out:` on a step** (already roadmap phase 4) — one receipt per unit, and the
   ownership contract becomes visible to the runner instead of to a bash loop.
2. **`exit_when` in the local engine** — the five early exits stop reading as failures.
3. **`condition` in the local engine** — `--auto` stops needing to rewrite the file, and
   the tier-based review skip becomes a receipt rather than an `if`.
4. **Local `loop` with `repeat_until`** — fix rounds and the capped gate repairs become
   declarative, and their counts land in receipts rather than in a step's JSON output.

Worth noting what already lands well: `effects` on the `worktree` and `ship` steps makes
`opensop heal --apply` refuse to re-run a step that has already pushed a branch and opened a
PR, which is precisely the double-post that guard is for.

## Layout

```
harness/
  bin/dev-loop          entry point; --auto rewrites the process file to drop the checkpoint
  dev-loop.sop.json     the phase skeleton — sequencing, checkpoint, gates, receipts
  lib/phase.sh          skill_section (the single source of truth), agent, halt, ctx
  steps/*.sh            one script per phase; each lifts its brief from SKILL.md
  test/smoke.sh         control-flow tests with stubbed agents; free, ~5s
```

## Status

Unmeasured. The skeleton runs end to end against stubs and the control-flow claims above
are tested; no full-cost run has been made, and nothing in `bench/` compares the harness
against the plugin yet. Treat it as a working prototype of a second execution path, not as
the recommended way to run the loop.
