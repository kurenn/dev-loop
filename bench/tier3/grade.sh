#!/usr/bin/env bash
# Tier 3b — blind pairwise grading. The grader never learns which arm is which, and the
# A/B position alternates across reps so a position bias shows up as a split rather than a
# spurious winner. Loop artifacts (PLAN/RATING/REVIEW .md) are stripped: they identify the
# flow instantly and are not the work under judgement.
set -uo pipefail
BENCH="$(cd "$(dirname "$0")/.." && pwd)"
REPS="${BENCH_REPS:-4}"; MODEL="${BENCH_MODEL:-opus}"
ARM1="${1:-v0.1}"; ARM2="${2:-v0.2.2}"; TASKID="${3:-t04-api-v1}"; IDX="${4:-1}"
OUT="$BENCH/results/tier3/blind-$ARM1-vs-$ARM2-$IDX"; rm -rf "$OUT"; mkdir -p "$OUT"
# Regenerate diffs from the actual worktrees. Loop artifacts are excluded: a PLAN.md or
# RATING-round file identifies the flow on sight and is not the work being judged.
for ARM in "$ARM1" "$ARM2"; do
  W=$(ls -d "$BENCH/results/tier1/$ARM/$TASKID-$IDX/app/.worktrees/"*/ 2>/dev/null | head -1)
  [ -n "$W" ] || { echo "no worktree: $ARM $TASKID-$IDX"; exit 1; }
  git -C "$W" diff main...HEAD -- . ':(exclude)*.md' > "$BENCH/tier3/blind/$ARM.diff"
done
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
TASK=$(cat "$BENCH/tier1/tasks/$TASKID.md")

for REP in $(seq 1 "$REPS"); do
  if [ $((REP % 2)) -eq 1 ]; then A=$ARM1; B=$ARM2; else A=$ARM2; B=$ARM1; fi
  P="$SANDBOX/prompt-$REP.txt"
  {
    echo "You are grading two independent implementations of the same task. You do not know"
    echo "who wrote either, and they were produced by different processes. Judge the work."
    echo
    echo "=== THE TASK AS GIVEN ==="; echo "$TASK"
    echo
    echo "Grade each implementation 1-10 on:"
    echo "  fitness      - does it do what the task asked, including the edge cases that matter"
    echo "  test_quality - would these tests catch a real regression; is anything important untested"
    echo "  simplicity   - is the solution proportionate to the task. MORE CODE IS NOT BETTER."
    echo "                 Penalise speculative generality, defensive scaffolding for problems"
    echo "                 the task does not have, and commentary that restates the code."
    echo "  clarity      - could a new maintainer follow it"
    echo
    echo "Both implementations already pass an identical hidden acceptance suite, so do not"
    echo "reward basic correctness twice - discriminate on the qualities above."
    echo
    echo "=== IMPLEMENTATION A ==="; echo '```diff'; cat "$BENCH/tier3/blind/$A.diff"; echo '```'
    echo "=== IMPLEMENTATION B ==="; echo '```diff'; cat "$BENCH/tier3/blind/$B.diff"; echo '```'
    echo
    echo "After your reasoning, emit one fenced json block and nothing after it:"
    echo '```json'
    echo '{"A":{"fitness":n,"test_quality":n,"simplicity":n,"clarity":n},'
    echo ' "B":{"fitness":n,"test_quality":n,"simplicity":n,"clarity":n},'
    echo ' "overall_preference":"A"|"B"|"tie","one_line_reason":"..."}'
    echo '```'
  } > "$P"
  ( cd "$SANDBOX" && claude --print --model "$MODEL" --dangerously-skip-permissions \
      --output-format json "$(cat "$P")" ) > "$OUT/rep-$REP.json" 2>/dev/null
  echo "{\"rep\":$REP,\"A\":\"$A\",\"B\":\"$B\"}" > "$OUT/rep-$REP.map.json"
  printf '.'
done
echo
python3 "$BENCH/tier3/score-blind.py" "$OUT"
