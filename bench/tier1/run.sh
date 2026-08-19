#!/usr/bin/env bash
# Tier 1 — execution harness. One run = one (flow, task) pair against a fresh clone of the
# pristine app. Captures a stream-json transcript, then hands everything to assert.py.
#
#   bench/tier1/run.sh v0.1 t01-projects-crud [run-index]
#
# Env:
#   BENCH_TIMEOUT   seconds before the run is killed (default 5400). Measured: a v0.2 run
#                   was still in Phase 6 at 35 min, so anything under ~1h truncates and the
#                   shipping assertions come back unknown rather than measured.
#   BENCH_MODEL     orchestrator model for both arms (default opus)
#   BENCH_STAMP     share one results dir across runs (default: new timestamp)
set -uo pipefail

FLOW="${1:?usage: run.sh <v0.1|v0.2> <task-id> [idx]}"
TASK="${2:?usage: run.sh <v0.1|v0.2> <task-id> [idx]}"
IDX="${3:-1}"

BENCH="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$BENCH/.work"
PRISTINE="$WORK/app-pristine"
FLOWDIR="$BENCH/flows/$FLOW"
TASKFILE="$BENCH/tier1/tasks/$TASK.md"
STAMP="${BENCH_STAMP:-$(date +%Y%m%d-%H%M%S)}"
RUNDIR="$BENCH/results/$STAMP/$FLOW/$TASK-$IDX"
TIMEOUT="${BENCH_TIMEOUT:-5400}"
MODEL="${BENCH_MODEL:-opus}"

[ -d "$PRISTINE" ] || { echo "no pristine app — run bench/tier1/setup-app.sh first"; exit 1; }
[ -d "$FLOWDIR" ]  || { echo "no such flow: $FLOW"; exit 1; }
[ -f "$TASKFILE" ] || { echo "no such task: $TASK"; exit 1; }

export GEM_HOME="$(ruby -e 'print Gem.user_dir')"
export PATH="$GEM_HOME/bin:$PATH"

# Never reuse a run directory. `git clone` into a non-empty dir fails, the script would
# carry on against the previous run's checkout, and a stale meta.json would sit beside a
# live transcript. Auto-increment instead of colliding.
while [ -e "$RUNDIR" ]; do
  IDX=$((IDX+1))
  RUNDIR="$BENCH/results/$STAMP/$FLOW/$TASK-$IDX"
done
mkdir -p "$RUNDIR"
APP="$RUNDIR/app"

# Fresh clone + its own bare origin, so pushes from parallel runs can't collide.
git clone -q --local "$PRISTINE" "$APP" || { echo "clone failed into $APP"; exit 1; }
git clone -q --bare "$PRISTINE" "$RUNDIR/origin.git"
git -C "$APP" remote remove origin 2>/dev/null
git -C "$APP" remote add origin "$RUNDIR/origin.git"
git -C "$APP" fetch -q origin
git -C "$APP" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# Simulate a developer's machine: the MAIN checkout has the gitignored secrets, a prepared
# DB and installed gems. A worktree the loop creates will have none of it — that is A3.
cp "$PRISTINE/config/master.key" "$APP/config/master.key"
( cd "$APP" && bin/rails db:prepare >/dev/null 2>&1 )

# --- pre-state -------------------------------------------------------------
{
  echo "flow=$FLOW task=$TASK idx=$IDX model=$MODEL"
  echo "base_sha=$(git -C "$APP" rev-parse HEAD)"
  echo "pre_status=$(git -C "$APP" status --porcelain | wc -l)"
  echo "pre_branch=$(git -C "$APP" symbolic-ref --short HEAD)"
} > "$RUNDIR/pre.txt"
( cd "$APP" && bin/rails test 2>&1 | tail -5 ) > "$RUNDIR/pre-suite.txt" 2>&1

# --- the run ---------------------------------------------------------------
# v0.2 defaults to stopping for plan approval, which cannot happen headless, so the
# autonomous flag is passed for comparability. Recorded in meta.json; see bench/README.md.
# Any v0.2+ arm defaults to stopping for plan approval, which cannot happen headless.
# Match the family, not the exact string: v0.2.1 needs --auto just as much as v0.2 does.
PROMPT="/dev-loop $(cat "$TASKFILE")"
case "$FLOW" in
  v0.2*) PROMPT="/dev-loop --auto $(cat "$TASKFILE")" ;;
esac

START=$(date +%s)
( cd "$APP" && timeout "$TIMEOUT" claude \
    --print \
    --model "$MODEL" \
    --plugin-dir "$FLOWDIR" \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    "$PROMPT" ) > "$RUNDIR/transcript.jsonl" 2> "$RUNDIR/stderr.txt"
RC=$?
END=$(date +%s)

python3 - "$RUNDIR" "$FLOW" "$TASK" "$IDX" "$MODEL" "$RC" "$((END-START))" <<'PY'
import json, sys
d, flow, task, idx, model, rc, secs = sys.argv[1:8]
json.dump({"flow": flow, "task": task, "idx": int(idx), "model": model,
           "exit_code": int(rc), "wall_seconds": int(secs),
           "autonomous_flag": flow.startswith("v0.2"),
           "note": "v0.2 run with --auto; its plan checkpoint cannot be exercised headless"},
          open(f"{d}/meta.json", "w"), indent=2)
PY

python3 "$BENCH/tier1/assert.py" "$RUNDIR"
echo "run dir: $RUNDIR"
