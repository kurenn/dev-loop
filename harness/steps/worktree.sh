#!/usr/bin/env bash
# Phase 2a — create, provision and baseline the worktree. SKILL.md "Phase 2 — Plan".
#
# The baseline is the load-bearing part: without it you cannot tell a regression from a
# pre-existing failure, which is why baseline_ok gates the rest of the run via exit_when.
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"

ROOT="$(ctx '.["resolve-env"].root')"
MAIN="$(ctx '.["resolve-env"].main')"
SLUG="$(ctx '.triage.slug')"
BR="$(ctx '.triage.branch')"
[ -n "$ROOT" ] && [ -n "$SLUG" ] && [ -n "$BR" ] || fail "missing root/slug/branch in context"

WT="$ROOT/.worktrees/$SLUG"
n=1
while [ -e "$WT" ]; do n=$((n+1)); WT="$ROOT/.worktrees/$SLUG-$n"; BR="$BR-$n"; done

git -C "$ROOT" worktree add "$WT" -b "$BR" "$MAIN" >/dev/null 2>&1 \
  || fail "git worktree add failed for $WT on $BR"

# Provision: a fresh worktree has tracked files only, so it usually cannot boot. Copy the
# gitignored files the profile says the app needs. Benchmarked: an unprovisioned worktree
# failed to boot in 4 of 5 runs.
copied=()
for pat in "config/master.key" ".env" ".env.local" ".env.development"; do
  if [ -f "$ROOT/$pat" ] && [ ! -e "$WT/$pat" ]; then
    mkdir -p "$WT/$(dirname "$pat")"
    cp "$ROOT/$pat" "$WT/$pat" && copied+=("$pat")
  fi
done

# Baseline. A check the profile does not define is skipped and reported as skipped,
# never assumed green.
declare -A BASE
for kind in install test lint typecheck security; do
  cmd="$(ctx ".profile.$kind")"
  if [ -z "$cmd" ]; then BASE[$kind]="skipped"; continue; fi
  if ( cd "$WT" && eval "$cmd" ) >/dev/null 2>&1; then BASE[$kind]="pass"; else BASE[$kind]="fail"; fi
done

# Only the test command failing means the environment is unusable; a red lint baseline is
# information, not a blocker, because later phases compare against it rather than to green.
ok=true
[ "${BASE[test]}" = "fail" ] && ok=false
[ "$ok" = false ] && halt "baseline_unrunnable" \
  "The test baseline could not be made to run in $WT. Nothing is implemented against a broken environment."

emit --arg wt "$WT" --arg br "$BR" \
     --arg install "${BASE[install]}" --arg test "${BASE[test]}" \
     --arg lint "${BASE[lint]}" --arg typecheck "${BASE[typecheck]}" \
     --arg security "${BASE[security]}" \
     --argjson ok "$ok" --argjson copied "$(printf '%s\n' "${copied[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')" \
     '{worktree:$wt, branch:$br, provisioned:$copied, baseline_ok:$ok,
       baseline:{install:$install, test:$test, lint:$lint, typecheck:$typecheck, security:$security}}'
