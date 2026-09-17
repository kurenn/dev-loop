#!/usr/bin/env bash
# Phase 1 — triage & frame. SKILL.md "Phase 1 — Triage & frame".
#
# Emits `trivial`, which the process file turns into an early exit. That is the skill's
# own first instruction — tell the user the loop is overkill and stop — expressed as a
# predicate instead of a sentence the orchestrator has to remember to honour.
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=triage

ROOT="$(ctx '.["resolve-env"].root')"
TASK="$(ctx '.task')"
[ -n "$TASK" ] || fail "no task given"

raw="$(agent "$(ctx '.models.triage' opus)" "$ROOT" "$(cat <<EOF
You are triaging a task for a quality-gated development loop, following the phase
definition below verbatim. Do not implement anything. Do not create a worktree.

$(skill_section "Phase 1 — Triage")

The task: $TASK

After your reasoning, emit one fenced json block and nothing after it:
\`\`\`json
{"trivial": true|false, "tier": "Light"|"Full", "units": <int>,
 "problem": "<crisp problem statement, carried verbatim into Phase 2>",
 "slug": "<short-kebab-name>", "branch": "<feature|fix|chore|refactor>/<name>",
 "stack": "<language/framework, or \"unknown\">",
 "reason": "<one line: why this tier, or why trivial>"}
\`\`\`
EOF
)")"

j="$(json_out "$raw")"
require_json "$j" trivial tier units problem slug branch stack reason

# The skill stops outright when the stack cannot be identified, because every later phase
# depends on knowing how to build and test it.
[ "$(jq -r .stack <<<"$j")" = "unknown" ] && fail "stack could not be identified; every later phase depends on it"

[ "$(jq -r .trivial <<<"$j")" = "true" ] && halt "trivial" \
  "The loop is overkill for this change: $(jq -r .reason <<<"$j"). Make the edit directly in the main checkout."

printf '%s' "$j"
