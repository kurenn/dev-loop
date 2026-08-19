#!/usr/bin/env bash
# Drive the full Tier 1 matrix sequentially. Full loops spawn many agents each, so these
# are deliberately not parallelised — wall clock is not the scarce resource here.
#   BENCH_STAMP=tier1 bench/tier1/run-all.sh [pair ...]
# A pair is "<flow>:<task>". With no args, runs the whole matrix.
set -uo pipefail
BENCH="$(cd "$(dirname "$0")/.." && pwd)"
export BENCH_STAMP="${BENCH_STAMP:-$(date +%Y%m%d-%H%M%S)}"
export BENCH_TIMEOUT="${BENCH_TIMEOUT:-5400}"

PAIRS=("$@")
if [ ${#PAIRS[@]} -eq 0 ]; then
  PAIRS=()
  for flow in v0.1 v0.2; do
    for t in t01-projects-write t02-tagging t03-archived-nil-bug t04-api-v1; do
      PAIRS+=("$flow:$t")
    done
  done
fi

for pair in "${PAIRS[@]}"; do
  flow="${pair%%:*}"; task="${pair##*:}"
  echo "=============== $flow / $task ==============="
  "$BENCH/tier1/run.sh" "$flow" "$task" 2>&1 | tail -18
done

echo
echo "=============== matrix summary ==============="
python3 "$BENCH/tier1/summarize.py" "$BENCH/results/$BENCH_STAMP"
