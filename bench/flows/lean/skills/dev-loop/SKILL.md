---
name: dev-loop
description: "Quality-gated development loop for a non-trivial feature or bug in any stack: plan → parallel implementation → mechanical gate → adversarial review → independent rating → gated fixes → commit and PR. Stops once after the plan for your approval; --auto skips that stop. Use only when the user explicitly runs /dev-loop or asks for 'the full loop'. Run /dev-loop-setup once per repo first."
---

# /dev-loop

You are the orchestrator. Run Phases 1–8 in order. The only early exits are the Phase 1
trivial triage and a hard stop you report.

By default the loop stops once, after the plan, and waits. Skip that only when the user
says so in this invocation (`--auto`, "run it autonomously") or the profile sets
`Checkpoints: none`. Never infer it. If the user gave no task, ask what to build or fix.

**Design rule for this skill: every quality guarantee here is a check the orchestrator
runs, not an adjective an agent is asked to weigh.** Anything that cannot be checked is
left to the rater's judgement and reported, not legislated.

---

## Step 0 — Environment and profile

One Bash call (shell state does not persist between calls):

```sh
ROOT=$(git rev-parse --show-toplevel) || exit 1
MAIN=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$MAIN" ] || MAIN=$(git rev-parse --verify -q main >/dev/null && echo main || echo master)
CODEX_DIR=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1)
gh repo view >/dev/null 2>&1 && GH=ok || GH=unavailable
echo "ROOT=$ROOT MAIN=$MAIN GH=$GH CODEX_DIR=${CODEX_DIR:-none}"
```

Read the repo's `CLAUDE.md` for a `## Dev-loop config` block: install/test/lint/typecheck/
security/coverage commands, local config files a worktree needs, critical paths, specialist
subagent types, fix-round cap (default 2), learnings file
(default `docs/dev-loop-learnings.md`). Detect what is missing; a check the profile does
not define is **skipped and reported as skipped**, never assumed green.

Codex, if present, drives Phase 5. Verified against codex 1.0.6; fall back silently if the
script or flags have changed.

## Agent brief contract

Subagents inherit neither your context nor your working directory. Every brief in Phases
3, 4 and 7 must open with this, filled in:

```
Work exclusively inside <ABSOLUTE worktree path>. Begin every Bash call by cd-ing there and
treat every path as relative to it. Never touch anything under <ROOT> outside that worktree.

Files you own (create/edit only these): <explicit list, or a directory/glob for files that
do not exist yet>
If you need a file you do not own, stop and report it instead of editing it.

Your unit: <verbatim from PLAN.md>     Done when: <that unit's acceptance criteria>
Before returning, run: <the profile's scoped test command>
Return: what you changed, what you could not do, and anything the plan got wrong.
```

## Phase 1 — Triage

Trivial (typo, comment, one-line config, single obviously-safe file)? Say the loop is
overkill, make the edit in the main checkout, stop. If the stack cannot be identified at
all, say so and stop. Otherwise restate the request as a problem statement and continue.

## Phase 2 — Plan (fable)

**Worktree.** Never work on `$MAIN`.

```sh
WT="$ROOT/.worktrees/<short-slug>"
git worktree add "$WT" -b <type>/<branch> "$MAIN"
```

If it already exists: resume if `$WT/LOOP_STATE.md` describes this task, else suffix `-2`.
Never delete an existing worktree.

**Provision it** — a fresh worktree has tracked files only, so copy the profile's local
config from `$ROOT` (`config/master.key`, `.env*`, …) and run install/prepare. **Capture a
baseline**: test, lint, typecheck, security and coverage, recorded in `LOOP_STATE.md`.
Without it you cannot tell a regression from a pre-existing failure. If the baseline cannot
run at all, stop and report which command failed.

**`PLAN.md`**, written by one **fable** agent, contains: problem and acceptance criteria as
a verifiable checklist; scope in and out; which critical paths it touches; test strategy;
assumptions; and the work broken into units, each with the files it owns:

```markdown
- **1 <unit>** · owns: `<path>`, `<dir/>` · does: <one sentence> · done when: <criterion>
```

Units running at the same time must own disjoint files — two units needing one file are
one unit. A unit creating files that do not exist yet declares a directory or glob.
Anything a later unit depends on goes in an earlier one.

## Phase 3 — Implement (sonnet, parallel)

Delegate; do not implement yourself. Spawn one **sonnet** agent per unit that is ready,
all in one message, each with the brief contract. Use the profile's specialist subagent
types where a unit matches one. Run dependent units after the units they depend on.

**Check ownership when they return**: `git status --porcelain` against the declared sets.
Anything outside is declared in `PLAN.md` (recorded as an amendment) or reverted, before
proceeding. This is a check, not a request.

## Phase 4 — Mechanical gate

In the worktree: install/build, tests, lint, typecheck, security, coverage — whichever the
profile defines. Compare against the Phase 2 baseline.

- New failures block; pre-existing ones do not.
- **Coverage may not fall below baseline.** If it has, the missing coverage is restored
  before anything proceeds. This is the check that keeps test rigour from being traded
  away, and it replaces asking anyone to value tests appropriately.
- Red → dispatch sonnet agents to repair and re-run, at most 3 attempts. This is repair,
  not a fix round, and does not consume the fix-round cap.
- Nothing reaches Phase 5 on red.

## Phase 5 — Adversarial review

One Bash call from the worktree, `timeout: 600000`:

```sh
cd "$WT" && CODEX_DIR=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1) \
  && [ -n "$CODEX_DIR" ] \
  && node "${CODEX_DIR}scripts/codex-companion.mjs" adversarial-review "--base $MAIN --wait"
```

For a large diff run the same command with Bash `run_in_background: true` (the script's own
`--background` flag is parsed but ignored for reviews), then poll with the companion's
`status --wait` and collect with `result <job-id>`. Do not use `/codex:adversarial-review`,
`/codex:status` or `/codex:result` — all three are `disable-model-invocation`.

No codex → a fresh **fable** agent given the worktree path, `PLAN.md` and
`git diff $MAIN...HEAD`, briefed to find where the design fails in the real world; note in
the PR that the review was in-family and therefore weaker.

Write findings to `REVIEW-round-N.md`. Fix nothing here.

## Phase 6 — Rate (fresh opus, threshold-blind)

One **opus** agent per round, which must not edit code and is not told the gate:

```
You are an independent reviewer. You did not write this code. Judge it; do not change it.

Inputs: PLAN.md, the diff of <MAIN>...HEAD in <worktree path>, the mechanical check
results, and REVIEW-round-N.md. If the diff exceeds ~2000 lines, use `git diff --stat` as a
map and read the files yourself.

Return exactly:
1. ACCEPTANCE — each criterion from PLAN.md as met / partial / unmet with evidence
   (file:line or test name). Every unmet criterion is BLOCKING.
2. FINDINGS — each with severity:
   BLOCKING = incorrect behavior, data loss, a security hole, or an unmet criterion.
   MAJOR = a real problem that does not block shipping.
   MINOR = style, naming, nits.
   Give file:line, what is wrong, the concrete fix. Judge each adversarial challenge as
   real or not, with reasoning.
3. SCORES — 1-10 on correctness, simplicity, test coverage, clarity, performance, security.
   10 is always best. Telemetry only.
4. PLAN DRIFT — where the work departed from PLAN.md, and whether each departure was
   justified.

Critical paths in this change: <from the profile, or "none">
```

Write it to `RATING-round-N.md`.

## Phase 7 — Gate and fix

Passes when: Phase 4 is green against baseline, **zero BLOCKING findings**, and every MAJOR
is fixed or waived with a written reason. Scores gate nothing; they go in the PR as
telemetry.

Not met → sonnet agents fix BLOCKING first, then MAJOR. Re-run Phase 4, then re-run Phase 6
as a **delta judgment**: give the next rater `RATING-round-N.md` plus the diff since the fix
and ask whether each finding was addressed and whether the fix broke anything. Re-run Phase
5 only if a critical path or the approach changed.

Respect the fix-round cap. If BLOCKING findings survive the last round, stop, write what is
blocking into `LOOP_STATE.md`, still capture learnings, and report. Never reclassify a
BLOCKING finding to get through the gate.

## Phase 8 — Learnings and ship

1. Append durable, reusable insight to the profile's learnings file **inside the worktree**,
   newest first below `## Entry format`, creating it with that header if absent. Do this
   even when the loop stopped at the gate.
2. Commit everything with a conventional message.
3. **Push whenever a git remote exists**, regardless of `GH` — pushing is git.
   Then, only if `GH=ok`, `gh pr create --base "$MAIN"`. No remote → stop at the commit.
   Remote but no GitHub → push and give the user the PR command. Never fail over either.
4. PR body: summary; the rating's finding counts by severity plus any MAJOR waivers and
   their reasons; fix rounds run and headline adversarial challenge; degraded phases
   (in-family review, skipped checks); test plan; assumptions from `PLAN.md`.
5. Report the worktree path. Do not remove it.

## Artifacts

`PLAN.md`, `REVIEW-round-N.md`, `RATING-round-N.md`, `LOOP_STATE.md` live in the worktree.
Update `LOOP_STATE.md` at each phase boundary so an interrupted run can resume.

## Guardrails

- Cost compounds: parallel agents × review passes × fix rounds. The fix-round cap is the brake.
- Never edit the main checkout after Phase 2.
- If implementation proves the plan wrong, amend `PLAN.md` and record the amendment so the
  rater judges the amendment too.
