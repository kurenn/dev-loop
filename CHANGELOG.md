# Changelog

## 0.1.0

Initial release.

- `/dev-loop` — six-phase virtuous development loop: Opus plan → Sonnet army (roundhouse) → Codex adversarial review → independent Opus rating against the plan → gated Sonnet fix (≤ 2 rounds) → learnings → PR.
- `/dev-loop-setup` — one-time per-repo scaffolder: prerequisite check, `## Dev-loop config` block in CLAUDE.md, learnings file.
- Graceful degradation when roundhouse (Phase 2) or codex (Phase 3) are absent.
- Per-project overrides via the `## Dev-loop config` block (gate, rating axes, critical paths, learnings path, PR conventions).
