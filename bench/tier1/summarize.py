#!/usr/bin/env python3
"""Aggregate a Tier 1 matrix across repeated runs.

Single runs are fine for the binary assertions, which are near-deterministic. They are
NOT fine for cost and wall clock: two byte-identical arms differed by 37% in wall clock
and 23% in cost, so anything under n=3 is reading noise. Cost/time are therefore reported
as mean +/- sample stdev with n, and never as a single figure.
"""
import json, os, statistics, sys, collections

ROOT = os.path.abspath(sys.argv[1])
IDS = ["A1_main_checkout_clean", "A2_worktree_created", "A3_worktree_bootable",
       "A4_work_committed", "A5_pushed_to_origin", "A6_ship_handled",
       "A7_no_review_on_red", "A9_ownership_conformance",
       "A10_handoffs_collected", "A11_handoffs_answered", "A12_loop_state_rewritten",
       "A14_gate_honoured"]
SHORT = ["A1 main", "A2 wt", "A3 boot", "A4 commit", "A5 push", "A6 ship", "A7 order",
         "A9 own", "A10 hand", "A11 ans", "A12 state", "A14 gate"]

runs = []
for dirpath, _, files in os.walk(ROOT):
    if "results.json" in files:
        try:
            runs.append(json.load(open(os.path.join(dirpath, "results.json"))))
        except Exception:
            pass
if not runs:
    print("no results.json under", ROOT); sys.exit(0)

groups = collections.defaultdict(list)
for r in runs:
    groups[(r["meta"]["flow"], r["meta"]["task"])].append(r)

w = max(len(f"{f} {t}") for f, t in groups) + 2
print(f"{'arm / task':<{w}}{'n':<4}" + "".join(f"{s:<11}" for s in SHORT))
print("-" * (w + 4 + 11 * len(SHORT)))

for (flow, task), rs in sorted(groups.items()):
    cells = []
    for i in IDS:
        vals = [(r["assertions"].get(i) or {}).get("pass") for r in rs]
        known = [v for v in vals if v is not None]
        if not known:
            cells.append("-")
        elif all(known):
            cells.append(f"PASS {len(known)}/{len(known)}")
        elif not any(known):
            cells.append(f"FAIL 0/{len(known)}")
        else:
            cells.append(f"{sum(known)}/{len(known)}")
    inc = sum(1 for r in rs if r.get("truncated"))
    tag = f" ({inc} incomplete)" if inc else ""
    print(f"{flow + ' ' + task:<{w}}{len(rs):<4}" + "".join(f"{c:<11}" for c in cells) + tag)


# A4-A6 read as n/a on a run whose gate blocked, because not shipping was correct there.
# That quietly shrinks their denominator, so report the disposition split alongside it —
# otherwise an arm that blocks more looks identical to one that never had to decide.
print("\ngate disposition — A4-A6 are withheld, not failed, on a blocked run")
for (flow, task), rs in sorted(groups.items()):
    c = collections.Counter((r.get("gate") or {}).get("disposition", "unscored") for r in rs)
    flag = sum(1 for r in rs if (r.get("gate") or {}).get("needs_human_review"))
    line = "  ".join(f"{k}={v}" for k, v in sorted(c.items()))
    print(f"  {flow} {task}:  {line}" + (f"   [{flag} need human review]" if flag else ""))


def stat(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return "n/a"
    if len(vals) == 1:
        return f"{vals[0]:.2f} (n=1, no variance estimate)"
    return f"{statistics.mean(vals):.2f} +/- {statistics.stdev(vals):.2f} (n={len(vals)})"


def aborted(r):
    """A run that reached no gate verdict and committed nothing did not finish.

    `truncated` only catches the timeout. A run killed by an API rate limit at Phase 2 is
    not truncated, so it was averaged in as a cheap, fast run — which understated a real
    cost regression and roughly tripled the reported variance, the two things that would
    have decided the question. Cost from a run that stopped early is not cost.
    """
    verdict = (r.get("gate") or {}).get("disposition")
    committed = (r.get("assertions", {}).get("A4_work_committed") or {}).get("pass")
    return verdict in ("unknown", "unscored", None) and committed is False


print("\ncost and wall clock — complete runs only")
for (flow, task), rs in sorted(groups.items()):
    ok = [r for r in rs if not r.get("truncated") and not aborted(r)]
    dropped = len(rs) - len(ok)
    if not ok:
        print(f"  {flow} {task}: no complete runs")
        continue
    note = f"   [{dropped} incomplete, excluded]" if dropped else ""
    print(f"  {flow} {task}:  ${stat([r['metrics'].get('cost_usd') for r in ok])}"
          f"   {stat([r['metrics'].get('wall_seconds') for r in ok])} s{note}")
