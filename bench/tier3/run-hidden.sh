#!/usr/bin/env bash
# Tier 3a — run hidden acceptance tests against each arm's finished branch.
# Copies the worktree to scratch so the branch is never dirtied, drops the hidden test in,
# and runs only that file.
set -uo pipefail
BENCH="$(cd "$(dirname "$0")/.." && pwd)"
TASK="${1:-t04-api-v1}"
TEST="$BENCH/tier3/hidden/${TASK%%-*}_acceptance_test.rb"
[ -f "$TEST" ] || TEST="$BENCH/tier3/hidden/t04_acceptance_test.rb"
export GEM_HOME="$(ruby -e 'print Gem.user_dir')"; export PATH="$GEM_HOME/bin:$PATH"
OUT="$BENCH/results/tier3"; mkdir -p "$OUT"

for ARM in "${@:2}"; do
  SRC=$(ls -d "$BENCH/results/tier1/$ARM/$TASK-1/app/.worktrees/"*/ 2>/dev/null | head -1)
  if [ -z "$SRC" ]; then echo "$ARM: no worktree for $TASK"; continue; fi
  DEST="$BENCH/.work/tier3-$ARM-$TASK"
  rm -rf "$DEST"; cp -r "$SRC" "$DEST"
  cp "$TEST" "$DEST/test/integration/zz_hidden_acceptance_test.rb"
  ( cd "$DEST" && bin/rails db:prepare >/dev/null 2>&1
    bin/rails test test/integration/zz_hidden_acceptance_test.rb 2>&1 ) > "$OUT/$ARM-$TASK.txt"
  echo "=== $ARM ==="
  grep -E "^(A[0-9]|Failure|Error|[0-9]+ runs)" "$OUT/$ARM-$TASK.txt" | tail -6
  tail -3 "$OUT/$ARM-$TASK.txt" | head -2
done
