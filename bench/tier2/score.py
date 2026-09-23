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


# Narrow on purpose, and only ever consulted when there is no answer to parse. A first cut
# matched "rate limit" and "HTTP 4xx" anywhere in the text and threw away 32 of 60 valid
# ratings on this corpus — which is an API pagination case, so raters write those words in
# their findings. An error detector that eats good data is worse than none.
API_ERROR = re.compile(r"session limit|error type rate_limit|Claude Code is unavailable", re.I)


def extract(path):
    """Return (finding-json | None, api_errored).

    A response the API refused and one the rater malformed both arrive as "no fenced json",
    and treating them alike is how a whole run of nothing gets reported as ninety bad
    answers. They mean opposite things: one is retry later, the other is fix the prompt.
    """
    if not os.path.exists(path):
        return None, False
    try:
        raw = json.load(open(path))
    except Exception:
        return None, False
    text = raw.get("result", "") or ""
    if raw.get("is_error"):
        return None, True
    m = FENCE.findall(text)
    if m:
        try:
            return json.loads(m[-1]), False
        except json.JSONDecodeError:
            return None, False
    # No answer to parse: only now is the text worth sniffing for a refusal.
    return None, bool(API_ERROR.search(text))


def gate_v01(v):
    axes = [x for x in (v.get("axes") or {}).values() if isinstance(x, (int, float))]
    overall = v.get("overall")
    if overall is None or not axes:
        return None
    return overall >= 8.5 and min(axes) >= 7


def gate_v02(v):
    findings = v.get("findings") or []
    return not any((f or {}).get("severity") == "BLOCKING" for f in findings)


# v0.1's numeric threshold is the outlier; every arm since gates mechanically on BLOCKING.
# A new rater arm therefore needs no entry here, and defaulting is safer than a KeyError
# that would drop the arm's data silently.
GATES = collections.defaultdict(lambda: gate_v02, {"v0.1": gate_v01, "v0.2": gate_v02})

SEV_RANK = {"MINOR": 1, "MAJOR": 2, "BLOCKING": 3}


def top_severity(v):
    """The highest severity in a response — the only part of it the gate can act on."""
    sevs = [(f or {}).get("severity") for f in (v.get("findings") or [])]
    sevs = [s for s in sevs if s in SEV_RANK]
    return max(sevs, key=lambda s: SEV_RANK[s]) if sevs else "NONE"

rows = collections.defaultdict(list)
scores = collections.defaultdict(list)
severities = collections.defaultdict(list)
counts = collections.defaultdict(list)
unparsed = collections.Counter()
api_errors = collections.Counter()

for vid in sorted(os.listdir(OUT)):
    vdir = os.path.join(OUT, vid)
    if not os.path.isdir(vdir):
        continue
    for arm in sorted(os.listdir(vdir)):
        for rep in sorted(os.listdir(os.path.join(vdir, arm))):
            v, errored = extract(os.path.join(vdir, arm, rep, "response.json"))
            if errored:
                api_errors[(vid, arm)] += 1
                continue
            if v is None:
                unparsed[(vid, arm)] += 1
                continue
            passed = GATES[arm](v)
            if passed is None:
                unparsed[(vid, arm)] += 1
                continue
            rows[(vid, arm)].append(not passed)          # blocked?
            severities[(vid, arm)].append(top_severity(v))
            counts[(vid, arm)].append(len(v.get("findings") or []))
            if v.get("overall") is not None:
                scores[(vid, arm)].append(v["overall"])
            axes = [x for x in (v.get("axes") or {}).values() if isinstance(x, (int, float))]
            if axes:
                scores[(vid, arm, "min_axis")].append(min(axes))

ARMS = sorted({k[1] for k in rows} | {k[1] for k in unparsed} | {k[1] for k in api_errors})

n_err = sum(api_errors.values())
n_ok = sum(len(v) for v in rows.values())
if n_err and n_err >= n_ok:
    print(f"\n*** RUN VOID — {n_err} of {n_err + n_ok} calls were refused by the API ***")
    print("Not a result. Nothing below is a measurement of any rater; re-run when the")
    print("limit clears. Reported separately from unparsed answers on purpose: this is")
    print("'retry later', not 'the rater returned nonsense'.\n")

print(f"\ncase: {os.path.basename(CASEDIR)}\n")
hdr = f"{'variant':<32} {'truth':<6} " + "".join(f"{a + ' block':<12}" for a in ARMS)
print(hdr); print("-" * len(hdr))

agg = {a: {"bad_blocked": 0, "bad_total": 0, "good_blocked": 0, "good_total": 0}
       for a in ARMS}

for vid in sorted(TRUTH):
    t = TRUTH[vid]
    cells = []
    for arm in ARMS:
        r = rows.get((vid, arm), [])
        if not r:
            cells.append("no data")
            continue
        blocked = sum(r)
        cells.append(f"{blocked}/{len(r)}")
        key = "bad" if t["should_block"] else "good"
        agg[arm][f"{key}_blocked"] += blocked
        agg[arm][f"{key}_total"] += len(r)
    print(f"{vid:<32} {'BAD' if t['should_block'] else 'GOOD':<6} "
          + "".join(f"{c:<12}" for c in cells))

print()
for arm in ARMS:
    a = agg[arm]
    br = f"{a['bad_blocked']}/{a['bad_total']}" if a["bad_total"] else "n/a"
    fb = f"{a['good_blocked']}/{a['good_total']}" if a["good_total"] else "n/a"
    brp = f"{100*a['bad_blocked']/a['bad_total']:.0f}%" if a["bad_total"] else "-"
    fbp = f"{100*a['good_blocked']/a['good_total']:.0f}%" if a["good_total"] else "-"
    print(f"{arm}:  catch rate on seeded defects {br} ({brp})   false block on correct code {fb} ({fbp})")

print("\nseverity agreement on identical input — the top severity each rep assigned.")
print("The gate acts only on this, so a variant that is not unanimous is a coin flip")
print("upstream of every waiver rule: same code, same brief, different ship decision.\n")
print(f"{'variant':<32} {'arm':<7} {'n':<4} {'top severity across reps':<34} unanimous")
print("-" * 96)
for vid in sorted(TRUTH):
    for arm in ARMS:
        sev = severities.get((vid, arm), [])
        if not sev:
            continue
        tally = collections.Counter(sev)
        spread = "  ".join(f"{s}x{n}" for s, n in
                           sorted(tally.items(), key=lambda kv: -SEV_RANK.get(kv[0], 0)))
        ok = "yes" if len(tally) == 1 else "NO"
        print(f"{vid:<32} {arm:<7} {len(sev):<4} {spread:<34} {ok}")

split = [(vid, arm) for vid in TRUTH for arm in ARMS
         if len(set(severities.get((vid, arm), []))) > 1]
print(f"\n{len(split)} of {sum(1 for vid in TRUTH for a in ARMS if severities.get((vid, a)))}"
      " (variant, arm) pairs disagreed with themselves on identical input.")

print("\nfindings raised per rep — dispersion in how much the rater sees at all:")
for vid in sorted(TRUTH):
    for arm in ARMS:
        c = counts.get((vid, arm), [])
        if len(c) > 1 and min(c) != max(c):
            print(f"  {vid:<32} {arm:<7} n={len(c)} min={min(c)} max={max(c)} "
                  f"mean={statistics.mean(c):.1f}")

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
           "severities": {f"{k[0]}|{k[1]}": v for k, v in severities.items()},
           "finding_counts": {f"{k[0]}|{k[1]}": v for k, v in counts.items()},
           "unparsed": {f"{k[0]}|{k[1]}": n for k, n in unparsed.items()}},
          open(os.path.join(OUT, "score.json"), "w"), indent=2)
print(f"\nwrote {os.path.join(OUT, 'score.json')}")
