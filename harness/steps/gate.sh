#!/usr/bin/env bash
# Phase 5 — mechanical gate. SKILL.md "Phase 5 — Mechanical gate".
#
# Objective checks, compared against the Phase 2 baseline, before anything is spent on
# review. Repairs are capped at 3 and do not consume the fix-round cap.
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=gate

WT="$(ctx '.worktree.worktree')"

run_checks() {
  local red=""
  for kind in install test lint typecheck security; do
    local cmd base
    cmd="$(ctx ".profile.$kind")"; base="$(ctx ".worktree.baseline.$kind")"
    [ -z "$cmd" ] && continue
    if ! ( cd "$WT" && eval "$cmd" ) >/dev/null 2>&1; then
      # New failures block; pre-existing ones do not.
      [ "$base" = "pass" ] && red="$red $kind"
    fi
  done
  echo "${red# }"
}

attempts=0
red="$(run_checks)"
while [ -n "$red" ] && [ "$attempts" -lt 3 ]; do
  attempts=$((attempts+1))
  agent "$(ctx '.models.repair' sonnet)" "$WT" "$(cat <<EOF
Work exclusively inside $WT. Begin every Bash call by cd-ing there.

These mechanical checks are failing and were green at baseline: $red
Repair them. This is repair, not a feature change: make the smallest change that makes
the check pass, and do not touch anything the failure does not require.

$(skill_section "Phase 5 — Mechanical gate")
EOF
)" >/dev/null 2>&1 || true
  prev="$red"; red="$(run_checks)"
  # Stop early if the same failure survives a repair attempt.
  [ "$red" = "$prev" ] && [ "$attempts" -ge 2 ] && break
done

# Coverage may not fall below the baseline. Measured: the arm carrying this as a check
# beat the arm carrying it as a written caution on test quality in both blind pairings.
cov_cmd="$(ctx '.profile.coverage')"
cov_ok=true
if [ -n "$cov_cmd" ]; then
  cur="$( ( cd "$WT" && eval "$cov_cmd" ) 2>/dev/null | tail -1 | grep -oE '[0-9]+(\.[0-9]+)?' | tail -1)"
  base="$(ctx '.worktree.coverage_baseline')"
  if [ -n "$cur" ] && [ -n "$base" ]; then
    awk -v a="$cur" -v b="$base" 'BEGIN{exit !(a+0 < b+0)}' && cov_ok=false
  fi
fi

# Nothing proceeds to a paid review on red.
{ [ -n "$red" ] || [ "$cov_ok" = false ]; } && halt "gate_red" \
  "Mechanical checks red against the baseline after $attempts repair attempt(s). New failures:${red:- none}. Coverage ok: $cov_ok."

emit --arg red "$red" --argjson attempts "$attempts" --argjson cov_ok "$cov_ok" \
     '{new_failures:$red, repair_attempts:$attempts, coverage_ok:$cov_ok,
       green: (($red == "") and $cov_ok)}'
