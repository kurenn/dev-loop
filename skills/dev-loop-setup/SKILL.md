---
name: dev-loop-setup
description: "Prepare any repository — any language or framework — to run /dev-loop. Detects and verifies the project's install, test, lint, typecheck and security commands, checks gh auth and optional accelerators (codex, stack specialist subagents), writes a '## Dev-loop config' profile into CLAUDE.md, gitignores .worktrees/, and creates the learnings file. Run once per repo before the first /dev-loop."
---

# /dev-loop-setup — prepare a repo for the loop

One-time setup. `/dev-loop` runs mostly unattended and spends real money, so its job is to
never guess at runtime. Your job is to write down, once, everything it would otherwise
have to guess — **verified, not assumed** — then report what the loop still can't do.

Make the smallest set of changes that achieves that. Do not restructure the project.

## Step 1 — Detect the stack and its commands

Identify the language, framework and package manager from the repo's manifest files
(`Gemfile`, `package.json`, `go.mod`, `pyproject.toml`, `Cargo.toml`, `pom.xml`, …), the
lockfiles present, and any existing CI workflow — **CI config is the best source of truth
for how this project is actually built and checked**, so read it before guessing.

Fill in each of these. A blank is fine; a wrong one is not:

| Field | What it is |
|---|---|
| Install / prepare | what makes a *fresh checkout* runnable and testable |
| Test | the full suite, non-interactive |
| Test (scoped) | how to test a subset of files — unit agents use this |
| Lint | formatter/linter check (not autofix) |
| Typecheck | if the stack has one |
| Security | dependency audit or static scanner, if the project has one |
| Local config | the **gitignored** files a fresh worktree needs to boot |

**Verify before writing.** Run each command you detected. If it fails or does not exist,
leave the field blank and say so in the report — `/dev-loop` treats a blank as "skipped
and reported", which is safe, whereas a command that doesn't work stalls the loop's
mechanical gate on every future run.

The **local config** field is the one most often missed and the one that most reliably
breaks the loop: `git worktree add` checks out tracked files only, so anything gitignored
that the app needs to boot (`config/master.key`, `.env`, `.env.local`, service-account
JSON, `*.local.yml`) must be listed here to be copied in. Check `.gitignore` against what
the app actually reads at startup.

## Step 2 — Check tooling

Report each; none is fatal, but say what is lost:

```sh
gh repo view                                                      # Phase 9: push + PR (auth AND a GitHub remote)
ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null   # Phase 6: adversarial review
```

- **No `gh`, not authenticated, or no GitHub remote** → the loop stops at a commit and
  hands the user the push and PR commands. `gh auth status` is not enough on its own: it
  succeeds in a repo that has no GitHub remote, where `gh pr create` still fails.
  Recommend `gh auth login`, or adding the remote.
- **No codex** → Phase 6 falls back to an in-family reviewer, which shares training and
  blind spots with the implementers and is materially weaker. Recommend
  `/plugin install codex@openai-codex`. If codex *is* present, also recommend running
  `/codex:setup` — a cached plugin directory does not prove the Codex CLI is installed
  and authenticated.
- **Specialist subagents** — check your available agent types for ones matching this
  stack (e.g. `roundhouse:rails-*` for a Rails repo). If they exist, list them in the
  profile so Phase 4 can route units to them. If not, the loop uses general agents,
  which is fine.

## Step 3 — Write the profile into CLAUDE.md

If there is no `CLAUDE.md`, create one. If it has no `## Dev-loop config` section, append
the block below. If the section exists, leave it and show the user its current values.
**Fill in every placeholder from Step 1** — never leave a `<...>` in the file.

For **critical paths**, infer from the domain: fintech → money / auth / KYC; healthcare →
PHI / auth; infrastructure → migrations / deploy. If nothing is obvious, write `none`.
For **specialist subagents**, list what Step 2 found, or `none`.

```markdown
## Dev-loop config

Project profile read by the `/dev-loop` skill (@kurenn/dev-loop). Verified <YYYY-MM-DD>.

**Stack:** <language / framework / package manager>

**Commands**
- Install / prepare: <cmd>
- Test: <cmd>
- Test (scoped): <cmd <paths>>
- Lint: <cmd — or blank>
- Typecheck: <cmd — or blank>
- Security: <cmd — or blank>

**Worktree**
- Local config to copy: <e.g. config/master.key, .env — or none>

**Execution**
- Checkpoints: plan   <!-- "plan" = stop for approval after the plan critique; "none" = fully autonomous -->
- Specialist subagents: <e.g. roundhouse:rails-models, roundhouse:rails-tests — or none>
- Decomposition hint: <natural wave order, e.g. schema/types → services → API → UI → tests>

**Quality**
- Critical paths: <e.g. money / auth — extra scrutiny and a codex re-review on fix rounds — or none>
- Extra rating axes: <e.g. design-system fidelity — or none>
- Fix-round cap: 2

**Ship**
- Learnings file: docs/dev-loop-learnings.md
- PR conventions: <repo-specific quirks — or standard gh pr create>
```

## Step 4 — Gitignore the worktree directory

`/dev-loop` creates worktrees under `.worktrees/` inside the repo. Untracked, that is a
second full checkout sitting in the working tree: `git status` noise, and test runners,
linters and file watchers descending into it. Add `.worktrees/` to `.gitignore` if it
isn't there.

## Step 5 — Create the learnings file

If the configured learnings file doesn't exist, create it with this header so Phase 9 has
a defined insertion point:

```markdown
# Dev-loop learnings

Durable, reusable insight captured by `/dev-loop`. Map, not diary — a gotcha worth
remembering, a pattern worth repeating, a place a plan was wrong. Nothing user-specific
or secret.

## Entry format

New entries go directly below this heading, newest first.

### YYYY-MM-DD — <short title>
**Context:** <feature/bug + PR # if any>
**Learning:** <the durable, reusable insight>
**How to apply:** <what to do next time>
```

## Step 6 — Report

Tell the user, concretely:

1. What was created or edited.
2. **Which commands were verified working**, and which fields were left blank because
   nothing was found or the command failed — each blank is a mechanical check `/dev-loop`
   will skip, so the user knows exactly where the gate has holes.
3. Missing tooling with the exact commands to fix it (`gh auth login`,
   `/plugin install codex@openai-codex`, `/codex:setup`).
4. That `/dev-loop <task>` is now ready, that it stops once after the plan for approval,
   and that `--auto` (or `Checkpoints: none` in the profile) runs it straight through to a
   PR instead.
