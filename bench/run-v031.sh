#!/usr/bin/env bash
# Three end-to-end runs of the v0.3.1 arm on t04, into the existing v03 results tree so the
# probes and the Tier 1 summariser compare all three arms in one view.
#
# Sequential on purpose. v0.2.6 and v0.3 ran sequentially, and wall-clock is one of the
# metrics under test; three parallel opus runs would contend and make this arm look slower
# for a reason that has nothing to do with the skill.
set -uo pipefail
BENCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BENCH_STAMP=v03

for i in 1 2 3; do
  echo "=============== v0.3.1 / t04-api-v1 #$i ==============="
  bash "$BENCH/tier1/run.sh" v0.3.1 t04-api-v1 "$i"
  echo
done

echo "=============== probes ==============="
bash "$BENCH/probes/run-probes.sh" "$BENCH/results/v03"
python3 "$BENCH/probes/summarize.py" "$BENCH/results/v03"
