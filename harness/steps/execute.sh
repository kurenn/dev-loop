#!/usr/bin/env bash
# Phase 4 — execute the waves. SKILL.md "Phase 4 — Execute".
#
# This is the step the local engine cannot express declaratively: it is a fan-out over a
# unit count nobody knows until the planner has run, and OpenSOP has no `fan_out:` (SPEC
# §9, roadmap phase 4) and no local `loop`. So the wave walk lives here, in bash.
#
# The consolation is real, though: ownership enforcement and handoff collection become
# mechanical instead of instructed. The skill says to check `git status --porcelain`
# against declared ownership after every wave, and the benchmark found it breached in
# every run before that check existed. Here it is code, and it lands in the receipt.
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"
DEVLOOP_STEP=execute

WT="$(ctx '.worktree.worktree')"
TEST_CMD="$(ctx '.profile.test')"
PLAN="$WT/PLAN.md"
[ -f "$PLAN" ] || fail "no PLAN.md in $WT"

# The abort branch of the checkpoint. The process file declares it as `exit_when` on the
# approval step, but the local engine ignores that, so the first step after the checkpoint
# is what actually honours the decision. Without this, "abort" would approve by inaction.
[ "$(ctx '.["plan-approval"].decision')" = "abort" ] && halt "aborted_at_plan" \
  "Aborted at the plan checkpoint. The worktree and branch are left in place: $WT"

# --- parse the plan -------------------------------------------------------
# A unit line: `- **1.2 name** · owns: `a`, `b` · does: ...`. The ownership clause runs to
# the `· does:` delimiter and often wraps, so parse the clause, not the line.
units_json="$(python3 - "$PLAN" <<'PY'
import json, re, sys
plan = open(sys.argv[1], errors="replace").read()
units = []
for m in re.finditer(r"^\s*[-*]\s*\*\*(\d+)\.(\d+)\s+(.*?)\*\*(.*?)(?=^\s*[-*]\s*\*\*\d+\.\d+|^\s*###|\Z)",
                     plan, re.M | re.S):
    wave, idx, name, body = m.group(1), m.group(2), m.group(3), m.group(4)
    owns = re.search(r"owns:(.*?)(?:·\s*does:|\Z)", body, re.S)
    paths = re.findall(r"`([\w./*-]+)`", owns.group(1)) if owns else []
    units.append({"wave": int(wave), "id": f"{wave}.{idx}", "name": name.strip(),
                  "owns": paths, "spec": re.sub(r"\s+", " ", (m.group(0) or "")).strip()})
json.dump(units, sys.stdout)
PY
)" || fail "could not parse units from PLAN.md"

n_units="$(jq 'length' <<<"$units_json")"
[ "$n_units" -gt 0 ] || fail "PLAN.md declared no units matching the wave format"
waves="$(jq -r '[.[].wave] | unique | .[]' <<<"$units_json")"

: > "$WT/HANDOFFS.md"
violations=0; redispatched=0; failed_units=""

brief() { # brief <unit-json>
  local u="$1" owns; owns="$(jq -r '.owns | join(", ")' <<<"$u")"
  cat <<EOF
Work exclusively inside $WT. Begin every Bash call by cd-ing there, and treat every file
path as relative to it. Never read or edit anything outside that worktree — it is a
separate checkout of the same repo.

Files you own (create/edit only these): $owns
If your work requires touching a file you do not own, stop and report it instead of
editing it.

Your unit: $(jq -r '.spec' <<<"$u")
Done when: the acceptance criteria that unit names in PLAN.md are met.
Before returning, run: ${TEST_CMD:-the project's test command}, scoped to your files.

$(skill_section "Phase 4 — Execute" | sed -n '/Return a handoff/,/^\`\`\`$/p')
Return a handoff with exactly these four headings and nothing else:
CHANGED — each file you touched and what the change does.
NOT DONE — anything in your unit you could not complete, and why.
DEVIATIONS — where you departed from the unit as written, and why.
CONCERNS — problems you noticed outside your unit. Report them; do not fix them.
EOF
}

dispatch() { # dispatch <unit-json> <outfile>
  local u="$1" out="$2"
  agent "$(ctx '.models.execute' sonnet)" "$WT" "$(brief "$u")" > "$out" 2>/dev/null || echo "__AGENT_FAILED__" > "$out"
}

for w in $waves; do
  wave_units="$(jq -c --argjson w "$w" '[.[] | select(.wave == $w)]' <<<"$units_json")"
  tmp="$(mktemp -d)"

  # Fan out. The engine is single-threaded by design ("no daemons, no background
  # processes"), so the concurrency is this script's, not OpenSOP's.
  i=0
  while read -r u; do
    dispatch "$u" "$tmp/$i.out" &
    i=$((i+1))
  done < <(jq -c '.[]' <<<"$wave_units")
  wait

  # Collect handoffs verbatim. Phase 4 requires them appended, not summarised.
  i=0
  while read -r u; do
    {
      echo "## Unit $(jq -r .id <<<"$u") — $(jq -r .name <<<"$u")"
      cat "$tmp/$i.out"
      echo
    } >> "$WT/HANDOFFS.md"
    i=$((i+1))
  done < <(jq -c '.[]' <<<"$wave_units")

  # A failed unit is re-dispatched once, then the loop stops. SKILL.md Phase 4.
  i=0
  while read -r u; do
    if grep -q '__AGENT_FAILED__' "$tmp/$i.out"; then
      redispatched=$((redispatched+1))
      dispatch "$u" "$tmp/$i.retry"; wait
      if grep -q '__AGENT_FAILED__' "$tmp/$i.retry"; then
        failed_units="$failed_units $(jq -r .id <<<"$u")"
      else
        { echo "## Unit $(jq -r .id <<<"$u") — re-dispatch"; cat "$tmp/$i.retry"; echo; } >> "$WT/HANDOFFS.md"
      fi
    fi
    i=$((i+1))
  done < <(jq -c '.[]' <<<"$wave_units")
  rm -rf "$tmp"

  [ -n "$failed_units" ] && break

  # Ownership, checked rather than trusted.
  declared="$(jq -r '[.[].owns[]] | unique | .[]' <<<"$wave_units")"
  while read -r f; do
    [ -n "$f" ] || continue
    case "$(basename "$f")" in
      PLAN.md|PLAN-CRITIQUE.md|LOOP_STATE.md|HANDOFFS.md) continue ;;
      REVIEW-round-*|RATING-round-*) continue ;;
    esac
    covered=false
    for d in $declared; do
      case "$d" in
        */|*\*) [ "${f##"${d%\*}"}" != "$f" ] && covered=true ;;
        *) [ "$f" = "$d" ] && covered=true ;;
      esac
      # A generated migration carries a timestamp the plan cannot know in advance.
      [ "$covered" = false ] && [ "$(dirname "$f")/" = "$(dirname "$d")/" ] && \
        [ "${d%/*}" != "$d" ] && covered=true
    done
    [ "$covered" = false ] && { violations=$((violations+1)); echo "$f" >> "$WT/.ownership-violations"; }
  done < <(git -C "$WT" status --porcelain | awk '{print $NF}')

  # A broken wave makes every downstream wave garbage.
  if [ -n "$TEST_CMD" ] && ! ( cd "$WT" && eval "$TEST_CMD" ) >/dev/null 2>&1; then
    failed_units="$failed_units wave-$w-red"
    break
  fi
done

[ -n "$failed_units" ] && halt "unit_failed" \
  "Stopped before the dependent wave rather than improvising. Failed:$failed_units"

emit --argjson units "$n_units" --argjson waves "$(jq -r '[.[].wave] | unique | length' <<<"$units_json")" \
     --argjson violations "$violations" --argjson redispatched "$redispatched" \
     --arg failed "$(echo "$failed_units" | tr -s ' ' | sed 's/^ //')" \
     '{units:$units, waves:$waves, ownership_violations:$violations,
       redispatched:$redispatched, failed_units:$failed,
       executed_clean: ($failed == "")}'
