#!/usr/bin/env bash
# Phase 6 — adversarial review. SKILL.md "Phase 6 — Adversarial review".
#
# Codex when it is installed, a fresh in-family agent otherwise. The fallback is recorded
# so the PR can say the review was weaker, which is the honesty the skill insists on.
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=review

WT="$(ctx '.worktree.worktree')"
MAIN="$(ctx '.["resolve-env"].main')"
CODEX="$(ctx '.["resolve-env"].codex_dir')"
OUT="$WT/REVIEW-round-1.md"

# Light tier does not earn a paid external review unless it touches a critical path. This
# would be a `condition` on the step if the local engine had one.
if [ "$(ctx '.triage.tier')" = "Light" ] && [ -z "$(ctx '.profile.critical_paths')" ]; then
  echo "(skipped by tier: Light, no critical path touched)" > "$OUT"
  emit '{ran:false, skipped_by_tier:true, in_family:false}'
  exit 0
fi

degraded=true
if [ -n "$CODEX" ] && [ -f "${CODEX}scripts/codex-companion.mjs" ]; then
  if ( cd "$WT" && timeout 600 node "${CODEX}scripts/codex-companion.mjs" \
        adversarial-review "--base $MAIN --wait" ) > "$OUT" 2>/dev/null; then
    degraded=false
  fi
fi

if [ "$degraded" = true ]; then
  agent "$(ctx '.models.review' fable)" "$WT" "$(cat <<EOF
Work exclusively inside $WT. You are an adversarial reviewer. Read PLAN.md and
\`git diff $MAIN...HEAD\`. Find where this design fails under real-world conditions —
challenge the approach and the assumptions, not just the defects.

$(skill_section "Phase 6 — Adversarial review")

Write your findings to REVIEW-round-1.md in the worktree. Fix nothing.
EOF
)" >/dev/null 2>&1 || true
fi

[ -f "$OUT" ] || echo "(no review produced)" > "$OUT"

emit --argjson degraded "$degraded" \
     '{ran:true, in_family:$degraded,
        note: (if $degraded then "in-family review; shares blind spots with the implementers" else "codex, out-of-family" end)}'
