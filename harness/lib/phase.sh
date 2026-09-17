#!/usr/bin/env bash
# Shared helpers for the OpenSOP step scripts.
#
# The rule this file exists to enforce: the harness sequences phases, SKILL.md defines
# them. No step script restates what a phase does. Each one lifts its phase verbatim out
# of SKILL.md and hands it to an agent. If the two ever disagree about what Phase 5 means,
# a benchmark comparing them is measuring nothing.
set -uo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="${DEVLOOP_SKILL:-$HARNESS_DIR/../skills/dev-loop/SKILL.md}"

# ctx <jq-filter> [default] — read a value out of the accumulated run context.
# OpenSOP puts it on stdin *and* in $OSL_CONTEXT. Only the env var is used: reading stdin
# would block forever whenever a script is run outside the engine, and a helper that can
# hang is worse than one that returns a default.
_CTX=""
ctx() {
  [ -n "$_CTX" ] || _CTX="${OSL_CONTEXT:-\{\}}"
  local v; v="$(jq -r "${1} // empty" <<<"$_CTX" 2>/dev/null)"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "${2:-}"
}

# fail <message> — emit a JSON error and exit non-zero so OpenSOP records a failure
# receipt rather than a step that quietly returned nothing.
fail() { jq -nc --arg e "$1" '{error:$e}' >&2; exit 1; }

# halt <outcome> <reason> — a deliberate, non-error stop.
#
# The process file declares these as `exit_when`/`exit_outputs`, which is what SPEC §3.15
# is for and what the server honours. The local engine implements neither `exit_when` nor
# `condition` (see the CLI's own note: "no ConditionEvaluator here"), so it would run every
# remaining step regardless. Until it does, the stop is enforced here by exiting non-zero:
# the run shows as `failed` rather than `completed-early`, which is the wrong word for an
# aborted plan or a trivial task, but it is the right behaviour — a loop that stopped
# should look stopped, and the alternative is shipping a task the loop decided not to run.
halt() {
  jq -nc --arg o "$1" --arg r "$2" '{halted:true, outcome:$o, reason:$r}' >&2
  exit 1
}

# emit — pass a jq program and args; writes the step's JSON output to stdout.
emit() { jq -nc "$@"; }

# skill_section <heading regex> — print one section of SKILL.md, heading included, up to
# the next heading at the same level. This is the single source of truth for phase text.
skill_section() {
  [ -f "$SKILL" ] || fail "SKILL.md not found at $SKILL"
  awk -v pat="$1" '
    /^## / { if (inside) exit; if ($0 ~ pat) inside = 1 }
    inside { print }
  ' "$SKILL"
}

# agent <model> <cwd> <prompt> — run one Claude agent and print its raw stdout.
#
# DEVLOOP_STUB is a test seam, mirroring the CLI's own OSL_LLM_STUB: when set to a
# directory, each call returns the contents of <dir>/<DEVLOOP_STEP>.json instead of
# spending money. It is what makes the skeleton testable end to end. Never set it for a
# real run.
agent() {
  local model="$1" dir="$2" prompt="$3"
  if [ -n "${DEVLOOP_STUB:-}" ]; then
    local f="$DEVLOOP_STUB/${DEVLOOP_STEP:-unknown}.json"
    [ -f "$f" ] || fail "stub mode: no fixture at $f"
    # A fixture may ship a .files/ directory, copied into the working directory so the
    # stub writes the artifacts a real agent would (PLAN.md, RATING-round-N.md, …) and
    # the steps' file assertions stay under test rather than being skipped.
    [ -d "$DEVLOOP_STUB/${DEVLOOP_STEP}.files" ] && cp -r "$DEVLOOP_STUB/${DEVLOOP_STEP}.files/." "$dir/"
    cat "$f"; return 0
  fi
  command -v claude >/dev/null 2>&1 || fail "claude CLI not on PATH"
  ( cd "$dir" && claude --print --model "$model" \
      --dangerously-skip-permissions "$prompt" ) \
    || fail "agent failed in $dir (model $model)"
}

# json_out <raw> — pull the last fenced JSON block out of an agent's prose reply.
# Agents narrate; the contract is that the machine-readable part comes last.
json_out() {
  local block
  block="$(awk '/^```json/{f=1;buf="";next} /^```/{if(f){last=buf;f=0}next} f{buf=buf $0 "\n"} END{printf "%s", last}' <<<"$1")"
  [ -n "$block" ] || fail "agent returned no fenced json block"
  jq -e . <<<"$block" >/dev/null 2>&1 || fail "agent's json block did not parse"
  printf '%s' "$block"
}

# require_json <json> <key>... — fail unless every key is present.
require_json() {
  local j="$1"; shift
  for k in "$@"; do
    jq -e "has(\"$k\")" <<<"$j" >/dev/null 2>&1 || fail "agent json missing required key: $k"
  done
}
