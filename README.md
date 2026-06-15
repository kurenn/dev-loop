# dev-loop

A **virtuous development loop** for Rails, as a Claude Code plugin. One command chains
six phases with deliberate model tiers and an independent quality gate:

| Phase | Who | Model |
|---|---|---|
| 1 · Plan & orchestrate | the session | **Opus**, max reasoning — writes `PLAN.md` (the grading contract) + worktree |
| 2 · Implement | specialist army | **Sonnet**, parallel, via `/rails-feature` (roundhouse) |
| 3 · Adversarial review | Codex | `/codex:adversarial-review` — challenges approach & assumptions |
| 4 · Rate against the plan | independent reviewer | **Opus** — scores each axis + overall plan-fidelity |
| 5 · Fix (gated) | specialist army | **Sonnet** — only if `overall < 8.5` or any axis `< 7`; ≤ 2 rounds |
| 6 · Learnings & ship | the session | Opus — appends durable learnings, opens the PR |

The point is the **separation of concerns**: a planner, an independent implementation
army, an adversarial reviewer, an *independent* rater (not the implementer grading
itself), a gated fixer, and a learning sink — so quality is enforced by structure, not
willpower.

## Install

```sh
/plugin marketplace add kurenn/dev-loop   # if not already on the kurenn marketplace
/plugin install dev-loop@kurenn
```

### Prerequisites (recommended)

dev-loop *wraps* two other plugins. It degrades gracefully without them, but it's
designed to run with both:

```sh
/plugin install roundhouse@kurenn      # Phase 2: the Sonnet specialist army
/plugin install codex@openai-codex     # Phase 3: the adversarial review
```

Without roundhouse, Phase 2 falls back to directly-spawned Sonnet agents. Without codex,
Phase 3 falls back to an Opus adversarial reviewer agent.

## Usage

```sh
/dev-loop-setup            # once per repo: checks prereqs, scaffolds config + learnings file
/dev-loop <feature or bug> # run the full loop
```

## Per-project configuration

The loop reads a `## Dev-loop config` block from the repo's `CLAUDE.md` (scaffolded by
`/dev-loop-setup`). Override any of:

- **Gate** — default `overall ≥ 8.5 AND every axis ≥ 7`
- **Base / extra rating axes** — e.g. add `design-system fidelity` for UI-heavy apps
- **Critical paths** — e.g. `money / auth / KYC`; those axes also require `≥ 8.5`
- **Learnings file** — default `docs/dev-loop-learnings.md`
- **Fix-round cap** — default `2`
- **PR conventions** — repo-specific screenshot/embed/`gh` quirks

Defaults apply when the block is absent, so `/dev-loop` works before setup — but
`/dev-loop-setup` tailors the gate and rigor tiers to the project.

## Why model tiers

- **Opus plans and rates** because planning and judging quality are the high-leverage,
  reasoning-heavy steps.
- **Sonnet implements and fixes** because the work is parallelizable and well-specified
  once the plan exists — an army of cheaper agents covers more ground.
- **A *separate* Opus rates** the work so the grader isn't the implementer. Self-rating
  inflates; independent rating against a written plan does not.
- **Codex challenges** from outside the Claude family for a genuinely adversarial second
  opinion on the approach, not just defect-spotting.

## License

MIT © Abraham Kuri
