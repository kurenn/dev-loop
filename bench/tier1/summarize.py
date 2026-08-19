#!/usr/bin/env python3
"""Collapse a Tier 1 matrix into one table: assertions per (flow, task), plus cost."""
import json, os, sys, collections

ROOT = os.path.abspath(sys.argv[1])
IDS = ["A1_main_checkout_clean", "A2_worktree_created", "A3_worktree_bootable",
       "A4_work_committed", "A5_pushed_to_origin", "A6_ship_handled",
       "A7_no_review_on_red", "A9_ownership_conformance"]
SHORT = ["A1 main", "A2 wt", "A3 boot", "A4 commit", "A5 push", "A6 ship", "A7 order", "A9 own"]

runs = []
for dirpath, _, files in os.walk(ROOT):
    if "results.json" in files:
        try:
            runs.append(json.load(open(os.path.join(dirpath, "results.json"))))
        except Exception:
            pass
if not runs:
    print("no results.json found under", ROOT); sys.exit(0)

runs.sort(key=lambda r: (r["meta"]["flow"], r["meta"]["task"]))
w = max(len(f"{r['meta']['flow']} {r['meta']['task']}") for r in runs) + 2
print(f"{'run':<{w}}" + "".join(f"{s:<11}" for s in SHORT) + "cost      artifacts")
print("-" * (w + 11 * len(SHORT) + 22))

tally = collections.defaultdict(lambda: collections.Counter())
for r in runs:
    m, A = r["meta"], r["assertions"]
    cells = []
    for i in IDS:
        p = (A.get(i) or {}).get("pass")
        cells.append("PASS" if p is True else ("FAIL" if p is False else "-"))
        if p is True:
            tally[m["flow"]][i] += 1
    arts = A.get("A8_artifacts") or {}
    have = [k.replace(".md", "").replace("-round-*", "") for k, v in arts.items() if v]
    cost = r["metrics"].get("cost_usd")
    if r.get("truncated"):
        have.append("TRUNCATED")
    print(f"{m['flow'] + ' ' + m['task']:<{w}}" + "".join(f"{c:<11}" for c in cells)
          + f"${cost if cost is None else round(cost, 2):<9}" + ",".join(have))

print()
for flow in sorted(tally):
    n = sum(1 for r in runs if r["meta"]["flow"] == flow)
    passed = sum(tally[flow].values())
    print(f"{flow}: {passed}/{n * len(IDS)} assertions passed across {n} runs   "
          f"total cost ${sum((r['metrics'].get('cost_usd') or 0) for r in runs if r['meta']['flow'] == flow):.2f}")
