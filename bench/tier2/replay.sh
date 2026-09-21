#!/usr/bin/env bash
# Tier 2 — gate isolation. Replays a frozen corpus through both rater designs without
# running the loop at all, so the only variable is the rater prompt.
#
#   bench/tier2/replay.sh [case-id]
#
# Env:
#   BENCH_REPS    repetitions per (variant, rater) pair (default 5)
#   BENCH_MODEL   rater model for both arms (default opus)
#   BENCH_STAMP   share one results dir across invocations
set -uo pipefail

BENCH="$(cd "$(dirname "$0")/.." && pwd)"
CASE="${1:-c01-api-pagination}"
CASEDIR="$BENCH/tier2/corpus/$CASE"
REPS="${BENCH_REPS:-5}"
MODEL="${BENCH_MODEL:-opus}"
STAMP="${BENCH_STAMP:-$(date +%Y%m%d-%H%M%S)}"
OUT="$BENCH/results/$STAMP/tier2/$CASE"

[ -d "$CASEDIR" ] || { echo "no such case: $CASE"; exit 1; }
mkdir -p "$OUT"
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT

PLAN="$(cat "$CASEDIR/plan.md")"
REVIEW="$(cat "$CASEDIR/review.md")"
TESTS="$(cat "$CASEDIR/tests.txt")"
EXTRACT="$(cat "$BENCH/tier2/raters/_extraction.md")"

# Arms are discovered, not listed. A rater prompt added to raters/ and then left out of a
# hardcoded loop is the quietest way to report that an arm "was not measured".
ARMS="${BENCH_ARMS:-$(find "$BENCH/tier2/raters" -maxdepth 1 -name '*.md' ! -name '_*' \
  -printf '%f\n' | sed 's/\.md$//' | sort -V | tr '\n' ' ')}"
echo "arms: $ARMS"

total=0
for VARIANT in "$CASEDIR"/variants/*/; do
  VID="$(basename "$VARIANT")"
  # BENCH_VARIANT filters to a single variant, for iterating on the corpus cheaply.
  if [ -n "${BENCH_VARIANT:-}" ] && [ "$VID" != "$BENCH_VARIANT" ]; then continue; fi
  DIFF="$(cat "$VARIANT/diff.patch")"
  for ARM in $ARMS; do
    RATER="$(sed '1,/^---$/d' "$BENCH/tier2/raters/$ARM.md")"
    for REP in $(seq 1 "$REPS"); do
      DEST="$OUT/$VID/$ARM/rep-$REP"
      mkdir -p "$DEST"
      {
        printf '%s\n' "$RATER"
        printf '\n=== PLAN.md ===\n%s\n' "$PLAN"
        printf '\n=== DIFF ===\n```diff\n%s\n```\n' "$DIFF"
        printf '\n=== MECHANICAL CHECKS / TEST RESULTS ===\n%s\n' "$TESTS"
        printf '\n=== ADVERSARIAL REVIEW FINDINGS ===\n%s\n' "$REVIEW"
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
done
echo
echo "$total rater calls -> $OUT"
python3 "$BENCH/tier2/score.py" "$OUT" "$CASEDIR"
