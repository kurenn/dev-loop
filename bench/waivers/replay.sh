#!/usr/bin/env bash
# Waiver replay — C4 isolation. Replays one frozen plan/diff/rating triple through both
# Phase 8 gate designs without running the loop, so the only variable is the waiver rule.
#
#   bench/waivers/replay.sh [case-id]
#
# Why this exists: C4 cannot be measured from a loop matrix. Waivers need MAJOR findings,
# and across ten runs of bench/tier1 the raters produced almost none — v0.2.6's gate never
# faced a waiver decision at all. Freezing a rating that does contain MAJORs is the only way
# to put both gates in front of the same decision.
#
# Env:
#   BENCH_REPS    repetitions per gate (default 5)
#   BENCH_MODEL   orchestrator model for both arms (default opus)
#   BENCH_STAMP   share one results dir across invocations
set -uo pipefail

BENCH="$(cd "$(dirname "$0")/.." && pwd)"
CASE="${1:-w01-api-v1-pagination}"
CASEDIR="$BENCH/waivers/corpus/$CASE"
REPS="${BENCH_REPS:-5}"
MODEL="${BENCH_MODEL:-opus}"
STAMP="${BENCH_STAMP:-$(date +%Y%m%d-%H%M%S)}"
OUT="$BENCH/results/$STAMP/waivers/$CASE"

[ -d "$CASEDIR" ] || { echo "no such case: $CASE"; exit 1; }
command -v claude >/dev/null || { echo "claude not on PATH"; exit 1; }
mkdir -p "$OUT"
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT

PLAN="$(cat "$CASEDIR/plan.md")"
DIFF="$(cat "$CASEDIR/diff.patch")"
RATING="$(cat "$CASEDIR/rating.md")"
EXTRACT="$(cat "$BENCH/waivers/_extraction.md")"

total=0
# Arms are discovered from gates/, so adding a gate design needs no edit here. BENCH_ARM
# restricts the run to one, for scoring a new gate against results already on disk.
for GATEFILE in "$BENCH"/waivers/gates/*.md; do
  ARM="$(basename "$GATEFILE" .md)"
  if [ -n "${BENCH_ARM:-}" ] && [ "$ARM" != "${BENCH_ARM}" ]; then continue; fi
  # Everything before the first --- is commentary about the arm, not part of the prompt.
  GATE="$(sed '1,/^---$/d' "$GATEFILE")"
  for REP in $(seq 1 "$REPS"); do
    DEST="$OUT/$ARM/rep-$REP"
    mkdir -p "$DEST"
    {
      printf '%s\n' "$GATE"
      printf '\n=== PLAN.md ===\n%s\n' "$PLAN"
      printf '\n=== DIFF ===\n```diff\n%s\n```\n' "$DIFF"
      printf '\n=== RATING-round-1.md ===\n%s\n' "$RATING"
      printf '%s\n' "$EXTRACT"
    } > "$DEST/prompt.txt"

    ( cd "$SANDBOX" && claude --print --model "$MODEL" \
        --output-format json \
        --dangerously-skip-permissions \
        "$(cat "$DEST/prompt.txt")" ) > "$DEST/response.json" 2> "$DEST/stderr.txt"
    total=$((total+1))
    printf '.'
  done
done
echo
echo "$total gate calls -> $OUT"
echo "score with: python3 $BENCH/waivers/score.py $OUT"
