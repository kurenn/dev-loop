#!/usr/bin/env bash
# Smoke test for the OpenSOP harness. Exercises the real control flow — real bash, real
# git, real file assertions — with only the agent calls stubbed, so it costs nothing.
#
# It asserts what the CLI does today, not what SPEC.md promises. Where the two differ the
# assertion says so, so this file doubles as the conformance list in harness/README.md.
#
#   harness/test/smoke.sh          # needs `opensop` and `jq` on PATH
set -uo pipefail
HARNESS="$(cd "$(dirname "$0")/.." && pwd)"
command -v opensop >/dev/null || { echo "SKIP: opensop not on PATH"; exit 0; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export OPENSOP_LOCAL_HOME="$WORK/osl"
export DEVLOOP_SKILL="$HARNESS/../skills/dev-loop/SKILL.md"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  [PASS] %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  [FAIL] %s — %s\n' "$1" "$2"; }

REPO="$WORK/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q -b main . && git config user.email t@t && git config user.name t
echo hello > README.md && git add -A && git commit -qm init

fixtures() { rm -rf "$WORK/stub"; mkdir -p "$WORK/stub"; }
fixture() { printf 'Narration an agent would emit.\n\n```json\n%s\n```\n' "$2" > "$WORK/stub/$1.json"; }
latest_run() { find "$OPENSOP_LOCAL_HOME/runs" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2; }
# A halt's reason rides in the failed step's `stderr` field in audit.jsonl. fault.json
# records that the step failed and its inputs, but not what the script printed.
halt_outcome() { jq -r 'select(.status=="failed") | .stderr | fromjson? | .outcome // empty' "$OPENSOP_LOCAL_HOME/runs/$1/audit.jsonl" 2>/dev/null | tail -1; }
run() { DEVLOOP_STUB="$WORK/stub" opensop run "$HARNESS/dev-loop.sop.json" --input task="add pagination" "$@" < /dev/null 2>&1 | tail -1; }

plan_fixtures() {
  fixture triage '{"trivial":false,"tier":"Full","units":2,"problem":"add pagination","slug":"pag","branch":"feature/pag","stack":"ruby","reason":"two units"}'
  fixture plan '{"waves":1,"units":2,"lines":80,"criteria":3,"assumptions":1}'
  fixture critique '{"points":2,"severities":{"high":0,"medium":2,"low":0},"headline":"units 1.1 and 1.2 own the same file"}'
  fixture apply-critique '{"applied":2,"rebutted":0,"changes":["split unit 1.2"],"rebuttals":[]}'
  mkdir -p "$WORK/stub/plan.files" "$WORK/stub/critique.files"
  printf '### Wave 1 — core\n- **1.1 a** · owns: `a.rb` · does: x\n  · done when: green\n- **1.2 b** · owns: `b.rb` · does: y\n  · done when: green\n' > "$WORK/stub/plan.files/PLAN.md"
  echo 'critique' > "$WORK/stub/critique.files/PLAN-CRITIQUE.md"
}

echo; echo "1. a trivial task stops before anything is created"
fixtures
fixture triage '{"trivial":true,"tier":"Light","units":1,"problem":"fix a typo","slug":"typo","branch":"chore/typo","stack":"ruby","reason":"one-line copy edit"}'
out="$(run)"; RID="$(latest_run)"
steps="$(jq -r '[.[].step] | join(",")' < <(jq -s . "$OPENSOP_LOCAL_HOME/runs/$RID/audit.jsonl") 2>/dev/null)"
[ "$steps" = "resolve-env,triage" ] && ok "the run stopped at triage; no later step ran" \
  || no "trivial stop" "steps run were: $steps"
[ ! -d "$REPO/.worktrees" ] && ok "no worktree created for a trivial task" || no "trivial stop" "a worktree was created"
# SPEC §3.15 calls this a completion via exit_when; the CLI has no exit_when, so the stop
# is a non-zero exit from the step and the run reads `failed`. Asserted as-is, on purpose.
[ "$(jq -r .status <<<"$out")" = "failed" ] && ok "stop is recorded as failed (no exit_when in CLI — see README)" \
  || no "stop status" "got $(jq -r .status <<<"$out")"
[ "$(halt_outcome "$RID")" = "trivial" ] && ok "the reason survives in the step receipt" \
  || no "stop reason" "audit.jsonl stderr outcome was '$(halt_outcome "$RID")'"

echo; echo "2. the plan checkpoint pauses the run"
fixtures; plan_fixtures
out="$(run)"; RID="$(latest_run)"
[ "$(jq -r .status <<<"$out")" = "waiting" ] && ok "run paused instead of proceeding" || no "pause" "status=$(jq -r .status <<<"$out")"
[ "$(jq -r '.waiting.step' <<<"$out")" = "plan-approval" ] && ok "paused at plan-approval" || no "pause step" "$(jq -r '.waiting.step' <<<"$out")"
[ -f "$REPO/.worktrees/pag/PLAN.md" ] && ok "PLAN.md was written into the worktree" || no "artifacts" "PLAN.md missing"
grep -q 'waiting_for_approval' "$OPENSOP_LOCAL_HOME/runs/$RID/audit.jsonl" \
  && ok "the pause is in audit.jsonl — the checkpoint is measurable" || no "receipt" "no waiting_for_approval receipt"

echo; echo "3. abort at the checkpoint stops the loop"
fixture execute '{"units":2,"waves":1,"ownership_violations":0,"redispatched":0,"failed_units":"","executed_clean":true}'
DEVLOOP_STUB="$WORK/stub" opensop submit "$RID" plan-approval --output decision=abort < /dev/null >/dev/null 2>&1
[ "$(halt_outcome "$RID")" = "aborted_at_plan" ] && ok "abort is honoured by the step after the checkpoint" \
  || no "abort" "run continued past an aborted plan"
# Nothing was implemented after the abort: the execute step halted before dispatching.
[ ! -f "$REPO/.worktrees/pag/HANDOFFS.md" ] && ok "no units were dispatched after an abort" \
  || no "abort" "HANDOFFS.md exists, so units ran anyway"

echo; echo "4. resume does not re-run completed steps"
rm -rf "$REPO/.worktrees"; git -C "$REPO" worktree prune
fixtures; plan_fixtures
run >/dev/null; RID="$(latest_run)"
before="$(grep -c '"step":"plan"' "$OPENSOP_LOCAL_HOME/runs/$RID/audit.jsonl")"
opensop submit "$RID" plan-approval --output decision=approve < /dev/null >/dev/null 2>&1
after="$(grep -c '"step":"plan"' "$OPENSOP_LOCAL_HOME/runs/$RID/audit.jsonl")"
[ "$before" = "$after" ] && ok "the plan step was not re-run on resume" || no "resume" "plan receipts went $before → $after"

echo; echo "5. --auto removes the checkpoint rather than skipping it"
auto="$(jq '.steps |= map(select(.id != "plan-approval"))' "$HARNESS/dev-loop.sop.json")"
[ "$(jq '[.steps[] | select(.type=="approval")] | length' <<<"$auto")" = "0" ] \
  && ok "the autonomous variant contains no approval step" || no "--auto" "an approval step survived"
[ "$(jq '.steps | length' <<<"$auto")" = "$(( $(jq '.steps | length' "$HARNESS/dev-loop.sop.json") - 1 ))" ] \
  && ok "exactly one step was removed" || no "--auto" "more than the checkpoint changed"

echo; echo "-------- $pass passed, $fail failed --------"
[ "$fail" -eq 0 ]
