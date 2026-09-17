#!/usr/bin/env bash
# Shipped-defect probes — run adversarial checks against every finished branch in a results
# tree and record which defect classes are present.
#
#   bench/probes/run-probes.sh [results-tree]     default: bench/results/$BENCH_STAMP
#
# Why this exists: across ten runs every Tier 1 assertion passed on both arms, and the
# hidden acceptance suite passed 8/8 on branches that carried a real defect — because it
# grades the task text, and the task text says nothing about hostile input. The defect was
# found by reading controllers by hand. Nothing in the harness could see it. This closes
# that: the outcome the gate exists to produce is "defects do not reach main", and until now
# there was no instrument that measured it.
#
# The worktree is copied to scratch first, so a branch is never dirtied by being probed.
set -uo pipefail

BENCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${1:-$BENCH/results/${BENCH_STAMP:-v03}}"
[ -d "$ROOT" ] || { echo "no such results tree: $ROOT" >&2; exit 1; }

export GEM_HOME="$(ruby -e 'print Gem.user_dir' 2>/dev/null)"
export PATH="$GEM_HOME/bin:$PATH"

n=0
while IFS= read -r meta; do
  RUN="$(dirname "$meta")"
  TASK="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['task'])" "$meta" 2>/dev/null)"
  PROBE="$BENCH/probes/${TASK%%-*}_defect_probe.rb"
  if [ ! -f "$PROBE" ]; then continue; fi
  # A probe that does not parse reports every defect as present, because each test errors.
  # That reads as a catastrophic result rather than as a broken file, so check it once here.
  ruby -c "$PROBE" >/dev/null || { echo "probe does not parse: $PROBE" >&2; exit 1; }

  SRC="$(find "$RUN/app/.worktrees" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
  [ -n "$SRC" ] || { echo "  skip $RUN (no worktree)"; continue; }

  DEST="$BENCH/.work/probe-$(basename "$(dirname "$RUN")")-$(basename "$RUN")"
  rm -rf "$DEST"; cp -r "$SRC" "$DEST"
  mkdir -p "$DEST/test/integration"
  cp "$PROBE" "$DEST/test/integration/zz_defect_probe.rb"

  ( cd "$DEST" && bin/rails db:prepare >/dev/null 2>&1
    bin/rails test test/integration/zz_defect_probe.rb 2>&1 ) > "$RUN/probe.txt"
  n=$((n + 1))
  printf '.'
done < <(find "$ROOT" -name meta.json | sort)

echo
echo "probed $n runs"
echo "summarize with: python3 $BENCH/probes/summarize.py $ROOT"
