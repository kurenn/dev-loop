#!/usr/bin/env bash
# Phase 2b — write PLAN.md. SKILL.md "Phase 2 — Plan".
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=plan

WT="$(ctx '.worktree.worktree')"
TIER="$(ctx '.triage.tier')"
CAP=300; [ "$TIER" = "Light" ] && CAP=120

raw="$(agent "$(ctx '.models.plan' fable)" "$WT" "$(cat <<EOF
Work exclusively inside $WT. Begin every Bash call by cd-ing there, and treat every file
path as relative to it. Never read or edit anything outside that worktree.

Write PLAN.md in that worktree, following the phase definition below verbatim.

$(skill_section "Phase 2 — Plan")

Problem: $(ctx '.triage.problem')
Tier: $TIER — your hard plan cap is $CAP lines. If it does not fit, the decomposition is
being padded with prose: cut the prose, not the units.

After writing PLAN.md, emit one fenced json block and nothing after it:
\`\`\`json
{"waves": <int>, "units": <int>, "lines": <int>,
 "criteria": <int>, "assumptions": <int>}
\`\`\`
EOF
)")"

j="$(json_out "$raw")"
require_json "$j" waves units lines criteria assumptions
[ -f "$WT/PLAN.md" ] || fail "planner returned but PLAN.md does not exist in $WT"

# The cap is a check, not a request. An over-cap plan is the decomposition padding itself.
lines="$(wc -l < "$WT/PLAN.md" | tr -d ' ')"
jq -nc --argjson j "$j" --argjson lines "$lines" --argjson cap "$CAP" \
  '$j + {lines: $lines, over_cap: ($lines > $cap)}'
