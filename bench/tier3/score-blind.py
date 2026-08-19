#!/usr/bin/env python3
"""Score blind pairwise grading, mapping A/B labels back to arms after the fact."""
import json, os, re, statistics, sys, collections
OUT = os.path.abspath(sys.argv[1])
FENCE = re.compile(r"```json\s*(\{.*?\})\s*```", re.S)
scores = collections.defaultdict(lambda: collections.defaultdict(list))
prefs = collections.Counter(); reasons = []; unparsed = 0
for f in sorted(os.listdir(OUT)):
    if not f.endswith(".json") or f.endswith(".map.json"): continue
    rep = f.split("-")[1].split(".")[0]
    mapping = json.load(open(os.path.join(OUT, f"rep-{rep}.map.json")))
    try:
        text = json.load(open(os.path.join(OUT, f))).get("result", "")
        v = json.loads(FENCE.findall(text)[-1])
    except Exception:
        unparsed += 1; continue
    for slot in ("A", "B"):
        arm = mapping[slot]
        for k, val in (v.get(slot) or {}).items():
            if isinstance(val, (int, float)): scores[arm][k].append(val)
    p = v.get("overall_preference")
    prefs[mapping.get(p, "tie") if p in ("A", "B") else "tie"] += 1
    if v.get("one_line_reason"): reasons.append((mapping.get(p, "tie"), v["one_line_reason"]))

dims = ["fitness", "test_quality", "simplicity", "clarity"]
print(f"\n{'arm':<10}" + "".join(f"{d:<16}" for d in dims))
print("-" * (10 + 16 * len(dims)))
for arm in sorted(scores):
    row = ""
    for d in dims:
        v = scores[arm][d]
        row += f"{statistics.mean(v):.2f}+/-{statistics.pstdev(v):.2f}".ljust(16) if v else "n/a".ljust(16)
    print(f"{arm:<10}{row}")
print("\noverall preference:", dict(prefs), f"(unparsed: {unparsed})" if unparsed else "")
for arm, r in reasons: print(f"  [{arm}] {r[:150]}")
