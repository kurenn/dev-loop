# Installing dev-loop — instructions for a coding agent

You are being asked to install **dev-loop**, a Claude Code plugin, for the user. Follow the
route that matches the tool you are running in. Report which route you took and what the
verification step returned.

Repository: https://github.com/kurenn/dev-loop

## What this is, before you start

dev-loop is a **Claude Code plugin**. It runs inside Claude Code — it is not a standalone
CLI and it cannot be run by Codex or any other agent runtime. If you are Codex or a similar
tool, you can still perform the installation (route B) and edit the user's project config,
but the loop itself will run in their Claude Code session.

## Route A — inside Claude Code (preferred)

Slash commands must be typed by the user; you cannot invoke these two yourself. Print them
and ask the user to run them in order:

```
/plugin marketplace add kurenn/dev-loop
/plugin install dev-loop@kurenn
```

Then, in the repository they want to use it on, they run `/dev-loop-setup` once. That
command *is* model-invocable, so once the plugin is installed you can run it for them.

## Route B — from a local checkout (any agent with shell access)

Use this when the marketplace route is unavailable, or the user wants to pin a version.

```sh
git clone https://github.com/kurenn/dev-loop.git ~/src/dev-loop
```

The user then starts Claude Code with the plugin loaded for that session:

```sh
claude --plugin-dir ~/src/dev-loop
```

`--plugin-dir` is repeatable and takes a directory or a `.zip`. It loads the plugin for
that session only, which is also the right way to try a branch before installing it
permanently.

## After either route

1. Confirm the plugin loaded: `/dev-loop` and `/dev-loop-setup` should appear in the user's
   available skills.
2. Run `/dev-loop-setup` in the target repository. It writes a `## Dev-loop config` block
   into `CLAUDE.md` recording that project's install, test, lint, typecheck, security and
   coverage commands, the gitignored files a fresh worktree needs in order to boot, and any
   stack-specific specialist subagents.
3. **Report the blanks.** Setup verifies each command by running it and leaves a field blank
   when it fails. Every blank is a check the loop will skip, so tell the user exactly which
   ones are empty rather than presenting the setup as complete.

## Optional, and worth mentioning to the user

```sh
/plugin install codex@openai-codex   # out-of-family adversarial review
/plugin install roundhouse@kurenn    # Rails specialist subagents
```

Neither is required and both are auto-detected. Without codex, the adversarial review falls
back to an in-family agent that shares blind spots with the implementers — materially
weaker, and the PR records that it degraded.

## Do not

- Do not copy the plugin into an internal cache directory by hand. Use the marketplace or
  `--plugin-dir`; the cache layout is an implementation detail and will change.
- Do not run `/dev-loop` to test the installation. It plans, spawns parallel agents, runs
  reviews and opens a PR — it costs real money and is not a smoke test. `/dev-loop-setup`
  and the skills listing are the verification.
