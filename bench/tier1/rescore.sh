#!/usr/bin/env bash
# Re-run assert.py over every completed run directory in a results tree.
#
# Why this exists: assert.py is edited while a matrix is in flight — the gate-disposition
# rescoring and the A9 glob fix both landed mid-run — which would otherwise leave early
# runs scored by one version and later runs by another. That is not a comparison. Running
# this once at the end puts every run through the identical final version.
#
# assert.py is deterministic and re-entrant: it reads the preserved run directory
# (transcript.jsonl, the worktree, origin.git) and derives everything from scratch. The
# one side effect is A3, which re-runs the project's test suite inside the worktree.
#
# The first score each run received is preserved as results-asrun.json and never
# overwritten, so the effect of a scoring change stays auditable after the fact.
#
# Usage: bench/tier1/rescore.sh [results-tree]     default: bench/results/$BENCH_STAMP
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-bench/results/${BENCH_STAMP:-v03}}"

if [ ! -d "$ROOT" ]; then
  echo "no such results tree: $ROOT" >&2
  exit 1
fi

# Refuse to rescore while the matrix is still running: a run directory captured mid-flight
# would be scored as a finished one and silently counted as a failure.
if pgrep -f 'bench/tier1/run(-all)?\.sh' >/dev/null 2>&1; then
  echo "a bench run is still in flight — rescoring now would score partial runs." >&2
  echo "wait for it to finish, or pass --force if you know the tree is complete." >&2
  [ "${2:-}" = "--force" ] || exit 1
fi

ok=0; failed=0; skipped=0
while IFS= read -r meta; do
  d="$(dirname "$meta")"
  if [ ! -f "$d/results.json" ]; then
    echo "  skip $d (never scored; run may have been interrupted)"
    skipped=$((skipped + 1))
    continue
  fi
  # Preserve the original score exactly once.
  [ -f "$d/results-asrun.json" ] || cp "$d/results.json" "$d/results-asrun.json"
  if python3 "$HERE/assert.py" "$d" >/dev/null 2>"$d/rescore.err"; then
    ok=$((ok + 1))
    rm -f "$d/rescore.err"
  else
    echo "  FAILED to rescore $d — see $d/rescore.err" >&2
    failed=$((failed + 1))
  fi
done < <(find "$ROOT" -name meta.json | sort)

echo "rescored $ok, failed $failed, skipped $skipped"

# Show what the rescoring actually changed, per assertion. A scoring change that moves
# nothing is worth knowing about too.
python3 - "$ROOT" <<'EOF'
import json, os, sys, collections
root = sys.argv[1]
delta = collections.Counter()
for dp, _, fs in os.walk(root):
    if "results.json" not in fs or "results-asrun.json" not in fs:
        continue
    new = json.load(open(os.path.join(dp, "results.json")))
    old = json.load(open(os.path.join(dp, "results-asrun.json")))
    for k, v in new["assertions"].items():
        if not isinstance(v, dict) or "pass" not in v:
            continue
        before = (old["assertions"].get(k) or {}).get("pass", "absent")
        if before != v["pass"]:
            delta[f"{k}: {before} -> {v['pass']}"] += 1
print("\nchanges vs the as-run scores:" if delta else "\nno assertion changed vs as-run.")
for k, n in sorted(delta.items()):
    print(f"  {n:3}x  {k}")
EOF
