---
name: dev-loop
description: "Full quality-gated development loop for a non-trivial feature or bug in any stack: plan → independent plan critique → parallel implementation waves → mechanical gate → adversarial review → independent rating → gated fixes → commit and PR. Stops once after the plan for your approval, then runs unattended; --auto skips that stop. Expensive — many parallel agents and multiple review passes. Use only when the user explicitly runs /dev-loop or asks for 'the full loop'; for ordinary single-task work use the project's normal path. Run /dev-loop-setup once per repo first."
---

# /dev-loop — the virtuous development loop

You are the orchestrator. Run the request through Phases 1–9 in order. The only early
exits are the Phase 1 trivial triage and a hard stop you report to the user. Outside the
stops this skill names, a status note never ends your turn: put it in the same message as
your next tool call and keep going. To wait on background agents you may end the turn, but
first arm a timed check — e.g. Bash `sleep 900` with `run_in_background` — so you wake
within 15 minutes even if no notification arrives. On waking, check each awaited agent:
re-arm if any is still working; one idle with no result gets Phase 4's one re-dispatch.
Cancel a timer only by its own task id, never by pattern (`pkill -f sleep` kills other
agents' timers), and cancel yours before any stop that waits on the user.

**By default the loop stops once, after the plan, and waits.**

**Autonomous mode is opt-in and must be explicit.** Skip the checkpoint only when the user
says so *in this invocation* — `--auto`, "run it autonomously", "don't stop", "no
checkpoints" — or when the project profile sets `Checkpoints: none`. Never infer it from
urgency, from task size, from a deadline, or from a previous autonomous run. In autonomous
mode every question that would have been asked becomes an assumption recorded in
`PLAN.md` and repeated in the PR body.

If the user gave no task, ask what to build or fix.

---

## Step 0 — Resolve environment and config

Run as **one** Bash call (shell state does not persist between calls):

```sh
ROOT=$(git rev-parse --show-toplevel) || exit 1
MAIN=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$MAIN" ] || MAIN=$(git rev-parse --verify -q main >/dev/null && echo main || echo master)
git fetch -q origin "$MAIN" 2>/dev/null && BASE="origin/$MAIN" || BASE="$MAIN"   # never a stale local branch
CODEX_DIR=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1)
gh repo view >/dev/null 2>&1 && GH=ok || GH=unavailable   # auth AND a GitHub remote
echo "ROOT=$ROOT MAIN=$MAIN BASE=$BASE GH=$GH CODEX_DIR=${CODEX_DIR:-none}"
```

Record these; every later phase uses them. Then:

1. **Project profile.** Read the repo's `CLAUDE.md` for a `## Dev-loop config` block —
   it carries this project's commands, decomposition hints and critical paths. If it is
   absent, detect what you can from the repo (see the defaults table) and tell the user
   at the end that `/dev-loop-setup` would make future runs cheaper and more reliable.
   The rater reads this `CLAUDE.md`, so it must not state the gate, its thresholds or the
   waiver rules; if it does, tell the user at the end of the run which lines to remove —
   do not edit their `CLAUDE.md` yourself.
2. **Accelerators (optional, auto-detected).** Neither is required:
   - **Specialist subagents** — if the profile names subagent types for this stack (e.g.
     `roundhouse:rails-models` for Rails), use them as unit executors in Phase 4.
     Detect availability by whether the subagent type appears in your available agent
     types, not by globbing the plugin cache.
   - **Codex** — if `CODEX_DIR` is non-empty, it drives Phase 6. Verified against codex
     **1.0.6**; if the companion script or its flags are missing, fall back silently.

| Knob | Default when the profile is silent |
|---|---|
| Install / prepare | detect (`bin/setup`, `npm ci`, `go mod download`, `uv sync`, …) |
| Test / lint / typecheck / security | detect from the repo; a missing check is *skipped, and said so*, never assumed green |
| Local config to copy into the worktree | every gitignored file the app needs to boot (`.env*`, `config/master.key`, `*.local.*`) |
| Checkpoints | plan approval after Phase 3; autonomous only on explicit request |
| Critical paths | none |
| Fix-round cap | from the Phase 1 tier (Light 1, Full 2) |
| Learnings | `docs/dev-loop-learnings/`, one file per entry |
| Telemetry axes | correctness, simplicity, test coverage, clarity, performance, security |

---

## Model assignments

| Phase | Who | Model |
|---|---|---|
| 1 Triage & frame | you | this session |
| 2 Plan | one `dev-loop:planner` | **claude-opus-5-5**, effort `high` (pinned) |
| 3 Critique → revise | one *fresh* `dev-loop:critic`; you apply its edits | **claude-opus-5-5**, effort `high` (pinned) |
| 4 Execute | unit agents, parallel within a wave | **sonnet** |
| 5 Mechanical gate | you (repairs by sonnet agents) | — |
| 6 Adversarial review | Codex, else a fresh agent | external / **fable** |
| 7 Rate | a fresh, threshold-blind `dev-loop:rater` | **claude-opus-5-5**, effort `high` (pinned) |
| 8 Fix | unit agents | **sonnet** |
| 9 Learnings & ship | you | this session |

Phases 2, 3 and 7 use the plugin's agents, which pin `claude-opus-5-5` at `high` effort;
every other row is passed as `model:` on the Agent tool and must be one of `sonnet`,
`opus`, `haiku`, `fable`. You **cannot** set your own model — if this session is not
running a strong model, say so once and continue; the phase models still apply to the
agents you spawn.

## The agent brief contract

Subagents do **not** inherit your context and do **not** inherit your working directory —
their Bash calls and their Read/Edit/Glob resolve against the repo root, not the
worktree. Every brief you write in Phases 4, 5 and 8 **must** open with this preamble,
with the placeholders filled in:

```
Work exclusively inside <ABSOLUTE worktree path>. Begin every Bash call by cd-ing there,
and treat every file path as relative to it. Never read or edit anything under
<ROOT> outside that worktree — it is a separate checkout of the same repo.

Files you own (create/edit only these): <explicit list from the plan>
If your work requires touching a file you do not own, stop and report it instead of
editing it.

Your unit: <verbatim excerpt from PLAN.md>
Done when: <that unit's acceptance criteria>
Before returning, run: <the profile's test command, scoped to your files>

Return a handoff with exactly these four headings and nothing else:
CHANGED — each file you touched and what the change does.
NOT DONE — anything in your unit you could not complete, and why.
DEVIATIONS — where you departed from the unit as written, and why.
CONCERNS — problems you noticed outside your unit. Report them; do not fix them.
```

Omitting this preamble is the single most common way this loop silently corrupts the
main checkout.

---

## Phase 1 — Triage & frame

1. **Trivial?** A typo, a copy edit, a one-line config change, a comment, a single
   obviously-safe file. If yes: tell the user the loop is overkill, make the edit — in a
   worktree and PR if the profile's rules require one — and stop.
2. **Size tier — a hard branch, not a hint.** Estimate the work units the change
   needs (a unit is one agent's worth of work over a disjoint set of files). Then commit
   to a tier and *apply its whole row*.

   | Tier | When | Plan cap | Phase 3 | Waves | Fix cap | Codex |
   |---|---|---|---|---|---|---|
   | **Light** | ≤ 2 units **and** an expected diff under ~150 lines | 120 lines | one critic call | 1 | 1 | skip unless a critical path is touched |
   | **Full** | anything larger | 300 lines | one critic call | as many as the plan needs | 2 | yes |

   A schema or migration change does **not** by itself force Full — a migration plus its
   test is two units. Record the tier in `LOOP_STATE.md` and do not silently upgrade it
   later; if the plan needs more units than the tier allows, re-tier once, explicitly.
3. **Stack check.** If the repo's language/framework can't be identified at all, say so
   and stop — every later phase depends on knowing how to build and test it.
4. Restate the request as a crisp problem statement. Carry it into Phase 2 verbatim.

## Phase 2 — Plan (claude-opus-5-5)

**2a — Create and provision the worktree.** Never work on `$MAIN` directly.

```sh
SLUG=<short-kebab-name>            # directory name; keep it short
BR=<feature|fix|chore|refactor>/<branch-name>
WT="$ROOT/.worktrees/$SLUG"
ART="$ROOT/.worktrees/$SLUG.loop"  # the loop's own files — never inside $WT
git worktree add "$WT" -b "$BR" "$BASE" && mkdir -p "$ART"
```

- If `$WT` or the branch already exists: if `$ART/LOOP_STATE.md` describes *this* task,
  resume from the phase it names. Otherwise append `-2`, `-3`… to `SLUG` and `BR` and
  create a fresh one. Never delete someone else's worktree to make room.
- **Provision it.** A fresh worktree contains tracked files only, so it usually cannot
  boot: copy the profile's local-config files from `$ROOT` (e.g. `config/master.key`,
  `.env*`), then run the profile's install/prepare commands.
- **Capture a baseline** — run the profile's test, lint, typecheck and security commands
  now, before any change, and record the results in `LOOP_STATE.md`. Without a baseline
  you cannot tell a regression from a pre-existing failure. Phase 4 dispatches nothing
  until the baseline has finished.
- If the baseline cannot be made to run at all, **stop** and report exactly which command
  failed and what is missing. Do not implement against a broken environment.

**2b — Write `$ART/PLAN.md`.** Spawn one `subagent_type: "dev-loop:planner"`, told to
read the repo at `$WT` and change nothing; it returns the plan as text and you write the
file. Give it the **tier's plan cap** as a hard limit on what it returns (Light 120 lines,
Full 300); Phase 3's edits do not count against it. `PLAN.md` is a work contract, not a
design essay: it is the decomposition the army executes and the criteria the work is
judged against. If it does not fit the cap, cut the prose, not the units. It must contain:

- **Problem & acceptance criteria** — a checklist, each item independently verifiable.
- **Scope** — explicitly in and explicitly out.
- **Risk tier** — which project-declared critical paths this touches, if any.
- **Test strategy** — what gets tested at which level, and what deliberately isn't.
- **Assumptions** — every open question and the answer being assumed. This section is
  what the Phase 3 checkpoint exists to surface; in autonomous mode it ships unreviewed,
  so it must be complete.
- **Work breakdown into waves.** This is what makes parallel execution safe:

```markdown
### Wave 1 — <name>
- **1.1 <unit name>** · owns: `<path/one>`, `<path/two>` · does: <one sentence>
  · done when: <criterion>
```

  Rules, non-optional:
  - Within a wave, unit ownership sets are **disjoint**. Two units that need the same
    file are one unit.
  - A unit that will **create** files — a migration, a new test, a new module — must
    declare a **directory prefix** (`db/migrate/`) or a **glob**
    (`test/models/*_test.rb`). You cannot enumerate a filename that does not exist yet,
    and an under-declared unit leaves its agent no legal move.
  - Every acceptance criterion must be owned by exactly one unit.
  - A wave may depend only on waves before it. Interfaces, schemas, types and shared
    contracts go in the earliest wave; their consumers come later.
  - Tests for a unit belong to that unit unless the profile says otherwise.

## Phase 3 — Critique the plan, then revise it

1. Spawn **one fresh** `subagent_type: "dev-loop:critic"` — not the planner. Give
   it only the original request and `PLAN.md`; it must not see the planner's reasoning.
   Brief it to attack: wrong problem framing, missing acceptance criteria, ownership
   collisions between units in the same wave, wave-ordering errors, unstated assumptions,
   under-tested risk, scope creep, and cheaper approaches that were not considered.

   **Bound it.** Judge the plan against the request and the repo *as it stands*. Do not
   read dependency or framework source, do not write probe scripts, do not try to prove
   framework behaviour empirically. A claim that would need that to settle is written down
   as **unverified** and moved past — verifying it is Phase 5's job, not the critic's.
   Reading the repo's own code is fine; leaving the repo is not.

   It returns, for each point: the problem, its severity, and **the specific edit it
   proposes to `PLAN.md`**. You write that to `$ART/PLAN-CRITIQUE.md`.
2. **You** apply the critique — do not spawn the planner again. For each point, either make
   the proposed edit to `PLAN.md` or record a one-line rebuttal in it. Silence is not
   allowed.
3. One critique round only.
4. **Checkpoint — present the plan and wait for a decision**, unless autonomous mode was
   explicitly requested. Show the user, compactly:
   - the problem statement and the acceptance-criteria checklist
   - the wave breakdown — unit name and owned paths, one line each
   - every assumption from `PLAN.md`, and the risk tier
   - what the critique changed, and anything you rebutted, with the reason
   - the cost shape — the tier, how many units, how many waves, whether Codex will run

   If you run as a subagent, this summary is your reply, whole, for your parent to show
   the user; a parent relays it unabridged. Then ask for **approve**, **revise** (with
   feedback), or **abort**. On revise, re-spawn the planner with the feedback, re-present,
   and repeat at most twice before asking for a final decision. On abort, remove the
   worktree, `$ART` and the branch you created, then stop.

   In autonomous mode, print that same summary without stopping — the run stays auditable
   even though nobody gated it.

## Phase 4 — Execute (sonnet, parallel within waves)

Do not implement anything yourself.

- Walk the waves **in order**. For each wave, spawn one **sonnet** agent per unit, all in
  a single message so they run concurrently, each with the brief contract preamble and
  only its own owned files.
- If the profile names specialist subagent types for this stack, pass the matching one as
  `subagent_type` (e.g. a model/migration unit → `roundhouse:rails-models`). This gives
  you their expertise while keeping *your* plan, *your* ownership boundaries and *your*
  wave ordering — do not delegate the whole feature to another orchestrating skill, which
  would re-plan the work against a different contract.
- **After each wave**: check ownership, answer the handoffs, run the profile's test
  command and **commit the wave** —
  `git -C "$WT" add -A && git -C "$WT" commit -m "wave <n>: <name>"`. A broken wave 1
  makes every downstream wave garbage, and the commit is what makes `$BASE...HEAD` show
  the work to Phases 6 and 7.
- **A failed unit is re-dispatched once, then the loop stops.** If a unit agent errors out,
  returns without meeting its "done when", or leaves the wave red, re-dispatch that unit
  **once** to a fresh agent with the same brief plus the failed handoff. If the wave is
  still red after that, stop before the next wave: record what failed in `LOOP_STATE.md`,
  still run Phase 9's learnings step, and report to the user. Never finish a unit's work
  yourself — an orchestrator that starts implementing is the pathology this phase exists to
  prevent — and never re-plan around the failure, which is the user's decision, not yours.
- **Enforce ownership after each wave — mechanically, not on trust.** Run
  `git status --porcelain` in the worktree and check every changed path against that
  wave's declared ownership; the brief's instruction alone does not hold. For anything
  outside: amend `PLAN.md` only if the file is genuinely required by an acceptance
  criterion that unit owns, and record the amendment for the rater; otherwise revert it.
  Amending because the agent already wrote it turns the contract into a transcript of
  whatever happened. Never start the next wave with an unresolved violation, and never let
  an undeclared file reach the rating phase unexplained.
- If an agent reports it needed a file it did not own, resolve the overlap yourself,
  update `PLAN.md`, and note the amendment — do not let two agents fight over a file.
- **Collect the handoffs and answer them — silence is not allowed.** Append each unit's
  four-field handoff verbatim to `$ART/HANDOFFS.md`. Before the next wave, every
  `DEVIATIONS` and `CONCERNS` entry gets one of two dispositions: an amendment to `PLAN.md`,
  recorded, or a one-line rebuttal in `LOOP_STATE.md` saying why it needs no action.
  Handoffs travel **up only** — never hand one unit's handoff to another unit as context.

## Phase 5 — Mechanical gate

Objective checks, run in the worktree, **before** spending anything on review:

install/build · tests · lint · typecheck · security scan — whichever the profile defines.

- Compare against the Phase 2 baseline. New failures block; pre-existing ones don't. A new
  failure is a flake only if the full suite passes on one rerun — an isolated pass or an
  open flake issue does not make it one.
- **Coverage may not fall below the baseline.** If it has, the missing coverage is restored
  before anything proceeds. This is a check, not a request.
- Any check the profile doesn't define is **skipped and reported as skipped**.
- If red: dispatch **sonnet** agents to repair, commit the repair, then re-run. This is
  repair, not a fix round — it does not consume the fix-round cap, but cap it at 3 attempts
  and stop if the same failure survives all three.
- Start Phase 6 only after every check has finished green — never while one is running.

## Phase 6 — Adversarial review

Challenge the approach, assumptions and real-world failure modes — not just defects.

**Light tier skips this phase** unless the change touches a project-declared critical
path. A two-unit change that already passed the mechanical gate does not earn a paid
external review; say in the PR that it was skipped by tier.

Run as one Bash call from inside the worktree, with `timeout: 600000`:

```sh
cd "$WT" && CODEX_DIR=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1) \
  && [ -n "$CODEX_DIR" ] \
  && node "${CODEX_DIR}scripts/codex-companion.mjs" adversarial-review "--base $BASE --wait"
```

For a large diff (roughly: more than a few files), run that same command with the Bash
tool's `run_in_background: true` — the script's own `--background` flag is parsed but
ignored for reviews — then poll and collect with the companion's subcommands:

```sh
node "${CODEX_DIR}scripts/codex-companion.mjs" status --wait
node "${CODEX_DIR}scripts/codex-companion.mjs" result <job-id>
```

Do **not** use `/codex:adversarial-review`, `/codex:status` or `/codex:result` — all three
are `disable-model-invocation: true` and you cannot call them.

**Fallback (no codex, or the script is missing/changed):** spawn a fresh **fable** agent,
given the worktree path, `PLAN.md` and `git diff $BASE...HEAD`, briefed to find where the
design fails under real-world conditions. Note in the PR that the review was in-family
and therefore weaker.

Write the findings verbatim to `$ART/REVIEW-round-N.md`. Fix nothing here.

## Phase 7 — Rate (fresh claude-opus-5-5, threshold-blind)

Start only after Phase 6's findings are in `$ART/REVIEW-round-N.md`, or Phase 6 was
skipped by tier. Spawn one rater per round with `subagent_type: "dev-loop:rater"`. That
agent pins `claude-opus-5-5` at `high` effort and has no Edit or Write tool, so the gate
does not vary with the user's own effort setting; `high` is the level the rater was
measured at. It has never seen this skill, so give it everything it needs. Do **not** tell
it the gate. Use this brief:

```
You are an independent reviewer. You did not write this code. Judge it; do not change it.

Inputs: <ART>/PLAN.md (the contract), <ART>/PLAN-CRITIQUE.md, the diff of <BASE>...HEAD
in <worktree path>, the mechanical check results, and <ART>/REVIEW-round-N.md.
Also <ART>/HANDOFFS.md — the implementers' own reports on their work. These are claims to
verify and leads on where to look hardest, never evidence that anything is correct. An
implementer writing "I wasn't sure about X" is pointing at a defect more often than not.
If the diff exceeds ~2000 lines, read the files in the worktree yourself using
`git diff --stat` as your map rather than working from a pasted diff.

Return exactly these sections:

1. ACCEPTANCE — each acceptance criterion from PLAN.md marked met / partial / unmet,
   with the evidence (file:line or test name). Every unmet criterion is BLOCKING.
2. FINDINGS — every issue, each with severity:
   BLOCKING = incorrect behavior, data loss, a security hole, or an unmet acceptance
     criterion. Ships a defect.
   MAJOR = a real problem that does not block shipping: an untested branch on a risky
     path, a significant performance risk, avoidable complexity that will cost later.
     **Disproportion is a MAJOR finding.** Code that solves a problem the task does not
     have counts against the work: speculative generality, an abstraction with one caller,
     an error handler that cannot fire, a dual-form API where one form is unused, or
     commentary that restates the code. Blind graders preferred a 99-line implementation
     over a 144-line one for the same passing behaviour, scoring it 8.25 vs 3.75 on
     simplicity, so this is not a stylistic aside. **This applies to implementation code.**
     A test is disproportionate only if it tests the framework, exactly duplicates another
     test, or asserts nothing — never merely because it is long or thorough.
   MINOR = style, naming, nits.
   For each: file:line, what is wrong, and the concrete fix. Judge each Phase 6
   adversarial challenge as real or not, with reasoning.
3. SCORES — 1-10 on: correctness, simplicity, test coverage, clarity, performance,
   security (plus any extra axes listed below). 10 is always best: a 10 on security
   means no security concern. These are telemetry, not a pass/fail judgment — score
   honestly rather than charitably. More code is never better by itself: judge fitness
   to the task, and mark down a solution that is larger than the problem.
4. PLAN DRIFT — where the implementation departed from PLAN.md, and whether each
   departure was justified.

Extra axes: <from the profile, or "none">
Critical paths in this change: <from the profile, or "none">
```

Write the rater's reply to `$ART/RATING-round-N.md` verbatim, never a summary.

## Phase 8 — Gate & fix

**The gate is mechanical, not numeric.** It passes when all three hold:

1. Phase 5 is green against the baseline (or its failures are pre-existing).
2. **Zero BLOCKING findings.**
3. Every MAJOR finding is either fixed or waived with a one-line written reason.

**A MAJOR may be waived only on one of three grounds**, and the waiver must name which:
it falls in what `PLAN.md` declared out of scope; it is pre-existing on `$BASE` and this
change does not touch it; or it argues against an assumption or scope decision that
`PLAN.md` records. The ground is the plan's record, not who signed it.
Anything else is fixed — you are both the party under cost pressure and the party deciding
what to waive, so the grounds are closed. **In autonomous mode, nothing on a
project-declared critical path may be waived at all**: no human approved the assumptions
that run is shipping under.

The 1–10 scores never gate anything — they go in the PR body as telemetry.

- **Gate met** → Phase 9. MINOR findings are listed in the PR, not fixed, unless the user
  or the project's own rules require it; such a fix is an ordinary rated commit.
- **Not met** → dispatch **sonnet** agents (brief contract preamble, ownership from the
  plan) to fix the BLOCKING findings first, then the MAJORs. A fix must be the smallest
  change that resolves the finding; removing implementation code is a legitimate fix.
  **Never satisfy a disproportion finding by weakening a test.** Dropping an assertion,
  widening a bound, or deleting a case removes coverage, not complexity. Coverage may
  only fall when the code it covered is gone. The fix agent commits its fix; **re-run
  Phase 5**, and re-run Phase 7 as a **delta judgment**: give the new rater
  `RATING-round-N.md` verbatim plus the diff of the fix commit, and nothing about the gate,
  the finding counts or what was left open; ask it to verify each prior finding was
  actually addressed and to flag anything the fix broke.
- Re-run Phase 6 on a fix round only if the fix touched a critical path or changed the
  approach; otherwise the delta judgment is enough.
- **A fix round runs in strict sequence — fix, Phase 5, Phase 6 if required, then the
  delta judgment given any new review file — and the tier caps the rounds** (Light 1,
  Full 2). If the gate is not met after the last round — a BLOCKING survives, or a MAJOR
  is neither fixed nor waivable, including one the delta judgment itself raised — stop:
  write what is unresolved into `LOOP_STATE.md`, still run Phase 9's learnings capture,
  and report the surviving findings to the user. Another round, a waiver outside the
  three grounds, or abandoning the change is their call, not yours. Never loosen the gate
  to pass, and never reclassify a BLOCKING finding as MAJOR to get through it.
- **No commit reaches `$BR` unrated.** Every commit after the last rating — a tidy, a
  merge of `$BASE` and its conflict resolution, a CI fix, a fix the user asks for after
  the PR is open — is made by a **sonnet** unit agent, never by you, and gets a delta
  judgment before it is pushed; a judgment that raises a new MAJOR or BLOCKING is a fix
  round and counts against the cap. Fetch, then merge a moved `$BASE` as its own commit,
  re-run Phase 5 against the new base, and include the merge in the next delta judgment.
  Phase 9's learnings commit is the one exception: yours, unrated, and touching only its
  learnings entry. Before every push, list the commits on `$BR` since the last rating —
  yours or anyone's — and rate any that no delta judgment has seen.

## Phase 9 — Learnings & ship

1. **Write learnings** as one new file, `<YYYY-MM-DD>-<slug>.md`, in the profile's
   learnings directory **inside the worktree**, so they ship with the PR and two PRs never
   touch the same lines. If the profile names a single file such as
   `docs/dev-loop-learnings.md`, leave it as the archive and write to a directory of the
   same name without `.md`. Use the entry format from the directory's `README.md`, or from
   the archive file. Capture only durable, reusable insight — a non-obvious gotcha, a
   pattern worth repeating, a recurring adversarial challenge, a place the plan was
   wrong. Map, not diary. Nothing user-specific or secret. **Run this step even when the
   loop stopped at the gate** — failed runs teach the most.
2. **Commit the learnings.** The work itself is already committed, wave by wave. The loop's
   own files stay in `$ART` and are never committed.
3. **Push, then open the PR — these are two separate decisions.**
   - **Push whenever the repo has a git remote**, regardless of `GH`:
     `cd "$WT" && git push -u origin "$BR"`. Pushing is git; a repo can have a perfectly
     good remote and no GitHub at all. Never withhold the push because `gh` is missing —
     that strands finished, committed work on a local branch for no reason.
   - **Then**, only if `GH=ok` from Step 0: `gh pr create --base "$MAIN" ...`.
   - No remote at all → stop at the commit. Remote but no GitHub → push, then give the
     user the exact PR command for their host.
   - Never fail the loop over either.
4. **PR body:**
   - **Summary** — what changed and why (1–3 bullets)
   - **Independent rating** — the axis scores as telemetry, plus the finding counts by
     severity and every MAJOR waiver with its reason and which of the three grounds it
     claimed
   - **Loop trace** — the `Trace` line from `LOOP_STATE.md`: fix rounds run and what they
     changed, headline adversarial challenge(s), unit re-dispatches and ownership
     violations, degraded phases (in-family review, skipped mechanical checks, no
     specialist agents), and follow-ups deferred
   - **Test plan** — how to verify, including manual steps for UI changes
   - **Assumptions** — the ones from `PLAN.md`, marked as approved at the Phase 3
     checkpoint or shipped unreviewed under autonomous mode
5. Report the worktree path to the user. Do not remove it — they may still want it.

---

## Artifacts & resumability

Everything the loop learns lives in files in `$ART`, not in your context. `$ART` sits
beside the worktree, not in it, so the loop's files never reach a commit or trip a
project's own checks.

| File | Written by |
|---|---|
| `PLAN.md` | Phase 2, amended in 4 and 8 |
| `PLAN-CRITIQUE.md` | Phase 3 |
| `HANDOFFS.md` | Phase 4, one entry per unit |
| `REVIEW-round-N.md` | Phase 6 |
| `RATING-round-N.md` | Phase 7 |
| `LOOP_STATE.md` | rewritten at every phase boundary — schema below |

**`LOOP_STATE.md` is rewritten at every phase boundary, not appended to**, and stays under
~40 lines. It is the loop's current state, not its diary: an appended log buries the resume
path in history, and this is the one artifact that has to survive a context compaction
intact. Keep these sections:

```markdown
Task: <problem statement>   Tier: <Light|Full>   Mode: <checkpointed|autonomous>
Worktree: <path>   Branch: <name>   Base: <BASE>@<sha>
Baseline: <each check: pass | fail | skipped>
Phase: <n — name>   Fix round: <n of cap>
Amendments & rebuttals: <one line each, from ownership checks and handoffs>
Degraded: <in-family review | skipped checks | no specialist agents | none>
Trace: <per phase — wall clock, agents spawned, repair attempts, ownership violations,
        findings by severity, waivers and their grounds>
Gate: <green | blocked by …>
```

If the loop is interrupted, a later run reads this and resumes instead of starting over.
`Trace` is what Phase 9 reports in the PR body, which makes the PR the lasting record of
what a run cost.

## Guardrails

- **Cost is real, and it compounds.** Parallel army × review passes × fix rounds. The
  Phase 1 tier decision and the fix-round cap are the two brakes — use both.
- **Never edit the main checkout after Phase 2.** Every path is under `$WT` or `$ART`.
- **The plan is the contract.** If implementation proves it wrong, amend `PLAN.md`,
  record the amendment, and make sure the rating judges the amendment too. Amending the
  contract to make the work look faithful is the one way to cheat this loop.
