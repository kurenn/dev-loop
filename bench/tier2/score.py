#!/usr/bin/env python3
"""Score a Tier 2 replay.

Two rates, both of which matter:
  block rate on known-bad   — does the gate catch a defect the tests missed
  false-block rate on good  — a gate that blocks everything is worthless

Plus score dispersion: the same artifact rated N times, to show how much of a numeric
threshold's verdict is the artifact and how much is sampling noise.

Gate definitions, applied to each arm's own output:
  v0.1  pass iff overall >= 8.5 AND every axis >= 7      (the shipped 0.1.0 gate)
  v0.2  pass iff zero BLOCKING findings                   (the shipped 0.2.0 gate)
"""
import json, os, re, statistics, sys, collections

OUT = os.path.abspath(sys.argv[1])
CASEDIR = os.path.abspath(sys.argv[2])
TRUTH = {v["id"]: v for v in json.load(open(os.path.join(CASEDIR, "index.json")))["variants"]}

FENCE = re.compile(r"```json\s*(\{.*?\})\s*```", re.S)


def extract(path):
    if not os.path.exists(path):
        return None
    try:
        text = json.load(open(path)).get("result", "")
    except Exception:
        return None
    m = FENCE.findall(text or "")
    if not m:
        return None
    try:
        return json.loads(m[-1])
    except json.JSONDecodeError:
        return None


def gate_v01(v):
    axes = [x for x in (v.get("axes") or {}).values() if isinstance(x, (int, float))]
    overall = v.get("overall")
    if overall is None or not axes:
        return None
    return overall >= 8.5 and min(axes) >= 7


def gate_v02(v):
    findings = v.get("findings") or []
    return not any((f or {}).get("severity") == "BLOCKING" for f in findings)


GATES = {"v0.1": gate_v01, "v0.2": gate_v02}

rows = collections.defaultdict(list)
scores = collections.defaultdict(list)
unparsed = collections.Counter()

for vid in sorted(os.listdir(OUT)):
    vdir = os.path.join(OUT, vid)
    if not os.path.isdir(vdir):
        continue
    for arm in sorted(os.listdir(vdir)):
        for rep in sorted(os.listdir(os.path.join(vdir, arm))):
            v = extract(os.path.join(vdir, arm, rep, "response.json"))
            if v is None:
                unparsed[(vid, arm)] += 1
                continue
            passed = GATES[arm](v)
            if passed is None:
                unparsed[(vid, arm)] += 1
                continue
            rows[(vid, arm)].append(not passed)          # blocked?
            if v.get("overall") is not None:
                scores[(vid, arm)].append(v["overall"])
            axes = [x for x in (v.get("axes") or {}).values() if isinstance(x, (int, float))]
            if axes:
                scores[(vid, arm, "min_axis")].append(min(axes))

print(f"\ncase: {os.path.basename(CASEDIR)}\n")
hdr = f"{'variant':<32} {'truth':<6} {'v0.1 block':<12} {'v0.2 block':<12}"
print(hdr); print("-" * len(hdr))

agg = {"v0.1": {"bad_blocked": 0, "bad_total": 0, "good_blocked": 0, "good_total": 0},
       "v0.2": {"bad_blocked": 0, "bad_total": 0, "good_blocked": 0, "good_total": 0}}

for vid in sorted(TRUTH):
    t = TRUTH[vid]
    cells = []
    for arm in ("v0.1", "v0.2"):
        r = rows.get((vid, arm), [])
        if not r:
            cells.append("no data")
            continue
        blocked = sum(r)
        cells.append(f"{blocked}/{len(r)}")
        key = "bad" if t["should_block"] else "good"
        agg[arm][f"{key}_blocked"] += blocked
        agg[arm][f"{key}_total"] += len(r)
    print(f"{vid:<32} {'BAD' if t['should_block'] else 'GOOD':<6} {cells[0]:<12} {cells[1]:<12}")

print()
for arm in ("v0.1", "v0.2"):
    a = agg[arm]
    br = f"{a['bad_blocked']}/{a['bad_total']}" if a["bad_total"] else "n/a"
    fb = f"{a['good_blocked']}/{a['good_total']}" if a["good_total"] else "n/a"
    brp = f"{100*a['bad_blocked']/a['bad_total']:.0f}%" if a["bad_total"] else "-"
    fbp = f"{100*a['good_blocked']/a['good_total']:.0f}%" if a["good_total"] else "-"
    print(f"{arm}:  catch rate on seeded defects {br} ({brp})   false block on correct code {fb} ({fbp})")

print("\nscore dispersion on identical input (v0.1 overall, the number its gate reads):")
for (k, arm), vals in sorted(((k, v) for k, v in scores.items() if len(k) == 2 and k[1] == "v0.1")):
    if len(vals) > 1:
        print(f"  {k:<32} n={len(vals)} min={min(vals)} max={max(vals)} "
              f"mean={statistics.mean(vals):.2f} stdev={statistics.pstdev(vals):.2f}")

if unparsed:
    print("\nunparsed responses (counted as no data, never as a pass):")
    for (vid, arm), n in sorted(unparsed.items()):
        print(f"  {vid} {arm}: {n}")

json.dump({"aggregate": agg,
           "per_variant": {f"{k[0]}|{k[1]}": v for k, v in rows.items()},
           "scores": {"|".join(map(str, k)): v for k, v in scores.items()},
           "unparsed": {f"{k[0]}|{k[1]}": n for k, n in unparsed.items()}},
          open(os.path.join(OUT, "score.json"), "w"), indent=2)
print(f"\nwrote {os.path.join(OUT, 'score.json')}")
