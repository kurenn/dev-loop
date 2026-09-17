#!/usr/bin/env bash
# Phase 3 (2) — apply the critique to PLAN.md. SKILL.md "Phase 3 — Critique the plan".
#
# Measured: a separate revise agent cost ~5 of the 15.5 minutes Phase 3 consumed, so the
# orchestrator applies the edits itself. Here that is a step of its own purely so the
# receipt distinguishes "critique written" from "critique answered".
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=apply-critique

WT="$(ctx '.worktree.worktree')"

raw="$(agent "$(ctx '.models.apply' fable)" "$WT" "$(cat <<EOF
Work exclusively inside $WT. Follow the phase definition below verbatim — specifically
step 2, applying the critique.

$(skill_section "Phase 3 — Critique")

Read PLAN.md and PLAN-CRITIQUE.md. For each point, either make the proposed edit to
PLAN.md or record a one-line rebuttal in it. Silence is not allowed.

Then emit one fenced json block and nothing after it:
\`\`\`json
{"applied": <int>, "rebutted": <int>,
 "changes": ["<one line per edit made>"],
 "rebuttals": ["<one line per point rebutted, with the reason>"]}
\`\`\`
EOF
)")"

j="$(json_out "$raw")"
require_json "$j" applied rebutted

# Every point gets a disposition. An unanswered critique point is the same defect as an
# unenforced ownership contract: the information was produced and then thrown away.
pts="$(ctx '.critique.points' 0)"
tot="$(( $(jq -r .applied <<<"$j") + $(jq -r .rebutted <<<"$j") ))"
[ "$tot" -ge "$pts" ] || fail "critique had $pts points but only $tot were answered"

printf '%s' "$j"
