#!/usr/bin/env bash
# Phase 7 — independent rating. SKILL.md "Phase 7 — Rate".
#
# The rater is threshold-blind: the brief below never mentions what passes. The gate is
# applied by the next step, from the finding severities this one reports.
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=rate

WT="$(ctx '.worktree.worktree')"
ROUND="$(ctx '.round' 1)"

raw="$(agent "$(ctx '.models.rate' opus)" "$WT" "$(cat <<EOF
Work exclusively inside $WT.

$(skill_section "Phase 7 — Rate")

Fill the bracketed placeholders from this run: the worktree is $WT, the base branch is
$(ctx '.["resolve-env"].main'), the review file is REVIEW-round-$ROUND.md, the mechanical
results are: $(ctx '.gate.new_failures' "none"). Extra axes: $(ctx '.profile.axes' none).
Critical paths in this change: $(ctx '.profile.critical_paths' none).

Write the full result to RATING-round-$ROUND.md, then emit one fenced json block and
nothing after it:
\`\`\`json
{"blocking": <int>, "major": <int>, "minor": <int>,
 "unmet_criteria": <int>,
 "scores": {"correctness": <int>, "simplicity": <int>, "test_coverage": <int>,
            "clarity": <int>, "performance": <int>, "security": <int>},
 "headline": "<the most serious finding, one line>"}
\`\`\`
EOF
)")"

j="$(json_out "$raw")"
require_json "$j" blocking major minor scores
[ -f "$WT/RATING-round-$ROUND.md" ] || fail "rater returned but RATING-round-$ROUND.md does not exist"

# An unmet acceptance criterion is BLOCKING by definition, so it can never be reported as
# unmet while blocking is zero. Catching that here keeps the gate honest.
unmet="$(jq -r '.unmet_criteria // 0' <<<"$j")"
blocking="$(jq -r .blocking <<<"$j")"
[ "$unmet" -gt 0 ] && [ "$blocking" -eq 0 ] && \
  fail "rater reported $unmet unmet criteria but zero BLOCKING findings; unmet criteria are BLOCKING"

printf '%s' "$j"
