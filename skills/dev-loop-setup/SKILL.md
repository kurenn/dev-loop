---
name: dev-loop-setup
description: "Scaffold a Rails project to use /dev-loop. Verifies @kurenn/roundhouse and @openai-codex/codex are installed, adds a '## Dev-loop config' block to CLAUDE.md (gate, critical paths, extra rating axes, learnings path, PR conventions), and creates the learnings file. Run once per repo before the first /dev-loop."
---

# /dev-loop-setup — prepare a repo for the loop

One-time setup. Make the smallest set of changes that lets `/dev-loop` run cleanly in
this repository, then tell the user what (if anything) they still need to do.

## Step 1 — Check prerequisites

Report whether each is installed; don't fail if missing (the loop degrades), but tell
the user what they lose:

```sh
ls -d ~/.claude/plugins/cache/kurenn/roundhouse/*/ 2>/dev/null   # /rails-feature, /rails-bugfix (Phase 2 army)
ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null  # /codex:adversarial-review (Phase 3)
```

- Missing roundhouse → Phase 2 falls back to directly-spawned Sonnet agents. Recommend
  `/plugin install roundhouse@kurenn`.
- Missing codex → Phase 3 falls back to an Opus adversarial reviewer agent. Recommend
  `/plugin install codex@openai-codex`.

## Step 2 — Scaffold the `## Dev-loop config` block in CLAUDE.md

If the repo has no `CLAUDE.md`, create one. If it has one but no `## Dev-loop config`
section, append the block below. If the section already exists, leave it and show the
user the current values. **Fill the placeholders by inspecting the repo** — don't leave
`<...>` in the file:

- **Critical paths:** infer from the domain (e.g. a fintech app → money / auth / KYC /
  compliance; a healthcare app → PHI / auth). If none are obvious, write `none`.
- **Extra rating axes:** add `design-system fidelity` if the repo has a component
  library / design system; otherwise `none`.
- **PR conventions:** capture any repo-specific quirks you can detect (private repo →
  screenshot embedding workaround; broken `gh pr edit`; assets-branch pattern).

```markdown
## Dev-loop config

Knobs read by the `/dev-loop` skill (@kurenn/dev-loop). Defaults shown; edit to taste.

- **Gate:** overall ≥ 8.5 AND every axis ≥ 7
- **Base rating axes:** correctness, simplicity, test coverage, naming, performance risk, security risk
- **Extra rating axes:** <e.g. design-system fidelity — or `none`>
- **Critical paths:** <e.g. money / auth / KYC — these axes also require ≥ 8.5 — or `none`>
- **Learnings file:** docs/dev-loop-learnings.md
- **Fix-round cap:** 2
- **PR conventions:** <repo-specific screenshot/embed/gh quirks — or `standard gh pr create`>
```

## Step 3 — Create the learnings file

If the configured learnings file (default `docs/dev-loop-learnings.md`) doesn't exist,
create it with this header so Phase 6 has somewhere to append:

```markdown
# Dev-loop learnings

Durable, reusable insight captured by `/dev-loop` (Phase 6). Append here — newest first.
Map, not diary. Nothing user-specific or secret.

## Entry format

### YYYY-MM-DD — <short title>
**Context:** <feature/bug + PR # if any>
**Learning:** <the durable, reusable insight>
**How to apply:** <what to do next time>
```

## Step 4 — Report

Tell the user: what was created/edited, which prerequisites are missing (with the exact
`/plugin install` commands), and that they can now run `/dev-loop <task>`.
