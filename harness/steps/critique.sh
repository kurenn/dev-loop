#!/usr/bin/env bash
# Phase 3 (1) — critique the plan. SKILL.md "Phase 3 — Critique the plan".
#
# A separate step from apply-critique so the receipts show a critic that never edited the
# plan it judged. That independence is the whole reason the phase exists.
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=critique

WT="$(ctx '.worktree.worktree')"

raw="$(agent "$(ctx '.models.critique' fable)" "$WT" "$(cat <<EOF
Work exclusively inside $WT. You are a fresh critic. You did not write this plan and you
have not seen the planner's reasoning. Follow the phase definition below verbatim.

$(skill_section "Phase 3 — Critique")

The original request: $(ctx '.triage.problem')
Read PLAN.md in the worktree. Write PLAN-CRITIQUE.md. Do not edit PLAN.md.

After writing it, emit one fenced json block and nothing after it:
\`\`\`json
{"points": <int>, "severities": {"high": <int>, "medium": <int>, "low": <int>},
 "headline": "<the single most important point, one line>"}
\`\`\`
EOF
)")"

j="$(json_out "$raw")"
require_json "$j" points headline
[ -f "$WT/PLAN-CRITIQUE.md" ] || fail "critic returned but PLAN-CRITIQUE.md does not exist"

# The critic must not have touched the plan. Cheap to check, and it is the one thing that
# makes the critique independent rather than a second draft.
if ! git -C "$WT" diff --quiet -- PLAN.md 2>/dev/null; then
  git -C "$WT" status --porcelain -- PLAN.md | grep -q . && \
    fail "critic modified PLAN.md; the critique must propose edits, not make them"
fi

printf '%s' "$j"
