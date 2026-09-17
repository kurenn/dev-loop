#!/usr/bin/env bash
# Phase 9 — learnings & ship. SKILL.md "Phase 9 — Learnings & ship".
#
# Declares `effects`, so `opensop heal --apply` refuses to re-run it without
# --force-effects. Re-running a step that already pushed a branch and opened a PR is
# exactly the double-post this guard exists for.
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=ship

WT="$(ctx '.worktree.worktree')"
BR="$(ctx '.worktree.branch')"
MAIN="$(ctx '.["resolve-env"].main')"
GH="$(ctx '.["resolve-env"].gh')"

# Learnings run even when the loop stopped at the gate — failed runs teach the most.
agent "$(ctx '.models.ship' sonnet)" "$WT" "$(cat <<EOF
Work exclusively inside $WT. Begin every Bash call by cd-ing there.

$(skill_section "Phase 9 — Learnings & ship")

Do step 1 only: append learnings to the profile's learnings file inside the worktree.
Capture only durable, reusable insight. Do not commit; the harness does that.
Gate status for this run: $(ctx '.fix.gate_met' false) (blocking: $(ctx '.fix.blocking' 0))
EOF
)" >/dev/null 2>&1 || true

pushed=false; pr=""
if [ "$(ctx '.fix.gate_met')" = "true" ]; then
  ( cd "$WT" && git add -A && git commit -q -m "$(ctx '.triage.problem' 'dev-loop change')" ) || true

  # Pushing is git; only the PR needs gh. Never withhold the push because gh is missing —
  # that strands finished work on a local branch for no reason.
  if git -C "$WT" remote get-url origin >/dev/null 2>&1; then
    git -C "$WT" push -q -u origin "$BR" && pushed=true
  fi
  if [ "$pushed" = true ] && [ "$GH" = "ok" ]; then
    pr="$( cd "$WT" && gh pr create --base "$MAIN" --fill 2>/dev/null | tail -1 )"
  fi
fi

emit --argjson pushed "$pushed" --arg pr "$pr" --arg wt "$WT" --arg br "$BR" \
     '{pushed:$pushed, pr_url:$pr, worktree:$wt, branch:$br,
       next: (if $pr != "" then "pr opened"
              elif $pushed then "pushed; open the PR on your host"
              else "committed locally" end)}'
