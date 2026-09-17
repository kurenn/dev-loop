#!/usr/bin/env bash
# Phase 8 — gate & fix. SKILL.md "Phase 8 — Gate & fix".
#
# The gate is mechanical: green against baseline, zero BLOCKING, every MAJOR fixed or
# waived on one of three enumerated grounds. The scores never gate anything.
#
# Fix rounds iterate, and the local engine has no `loop`, so the rounds are here. The
# cap comes from the tier: Light 1, Full 2.
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=fix

WT="$(ctx '.worktree.worktree')"
TIER="$(ctx '.triage.tier')"
CAP=2; [ "$TIER" = "Light" ] && CAP=1

blocking="$(ctx '.rate.blocking' 0)"
major="$(ctx '.rate.major' 0)"
round=1; waived=0

while { [ "$blocking" -gt 0 ] || [ "$major" -gt 0 ]; } && [ "$round" -le "$CAP" ]; do
  raw="$(agent "$(ctx '.models.fix' sonnet)" "$WT" "$(cat <<EOF
Work exclusively inside $WT. Begin every Bash call by cd-ing there.

Read RATING-round-$round.md. Fix the BLOCKING findings first, then the MAJORs, following
the phase definition below verbatim — including what counts as a legitimate fix, what a
waiver requires, and what you may never do to a test.

$(skill_section "Phase 8 — Gate & fix")

Then emit one fenced json block and nothing after it:
\`\`\`json
{"fixed": <int>, "waived": <int>,
 "waivers": [{"finding": "<one line>", "ground": "out-of-scope"|"pre-existing"|"contradicts-approved-assumption", "reason": "<one line>"}]}
\`\`\`
EOF
)")" || break

  j="$(json_out "$raw")"
  # A waiver must name one of the three grounds. Anything else is not a waiver.
  bad="$(jq -r '[.waivers[]? | select((.ground // "") | IN("out-of-scope","pre-existing","contradicts-approved-assumption") | not)] | length' <<<"$j")"
  [ "$bad" -gt 0 ] && fail "$bad waiver(s) named no valid ground; those findings must be fixed"
  waived=$(( waived + $(jq -r '.waived // 0' <<<"$j") ))

  # Re-run the mechanical gate, then re-rate as a delta judgment.
  "$(dirname "$0")/gate.sh" >/dev/null 2>&1 || true
  round=$((round+1))
  DEVLOOP_STEP=rate
  raw="$(agent "$(ctx '.models.rate' opus)" "$WT" "$(cat <<EOF
Work exclusively inside $WT. This is a delta judgment, not a fresh rating.

Read RATING-round-$((round-1)).md and \`git diff\` since that rating. For each prior
finding, verify it was actually addressed. Flag anything the fix broke. Write
RATING-round-$round.md, then emit one fenced json block and nothing after it:
\`\`\`json
{"blocking": <int>, "major": <int>, "minor": <int>, "regressions": <int>}
\`\`\`
EOF
)")" || break
  j="$(json_out "$raw")"
  blocking="$(jq -r .blocking <<<"$j")"; major="$(jq -r .major <<<"$j")"
  DEVLOOP_STEP=fix
done

# Never loosen the gate to pass, and never reclassify a BLOCKING finding to get through it.
gate_met=false
[ "$blocking" -eq 0 ] && gate_met=true

# Phase 9's learnings capture runs even when the loop stops here — failed runs teach the
# most — so the stop happens after ship.sh, not instead of it. Recorded, then honoured.
if [ "$gate_met" = false ]; then
  "$(dirname "$0")/ship.sh" >/dev/null 2>&1 || true
  halt "blocked" "$blocking BLOCKING finding(s) survived $((round-1)) of $CAP fix round(s). Stopped rather than lowering the bar."
fi

emit --argjson blocking "$blocking" --argjson major "$major" \
     --argjson rounds "$((round-1))" --argjson cap "$CAP" --argjson waived "$waived" \
     --argjson met "$gate_met" \
     '{blocking:$blocking, major:$major, fix_rounds:$rounds, fix_cap:$cap,
       waived:$waived, gate_met:$met}'
