#!/usr/bin/env python3
"""Score a waiver replay against the corpus ground truth.

Three rates, and the third is the one that matters for deciding whether C4's grounds are
too narrow:

  waiver rate       how often the gate waived rather than fixed. Descriptive, not a score.
  wrong-waiver rate waived a finding the truth marks not-waivable. The cost of a loose gate:
                    a real defect ships with a reason attached.
  over-fixing rate  fixed a finding the truth marks legitimately waivable. The cost of a
                    strict gate: fix rounds spent on things a human would have let through,
                    which is what bench/PLAN-v0.3.md pre-registered as C4's failure mode.

For the v0.3 arm only, waivers also carry a named ground, so ground accuracy is reported:
naming a ground the truth does not support is how an enumeration gets talked around.

Usage: python3 bench/waivers/score.py <results-dir> [--case <case-id>]
"""
import json, os, re, sys, statistics, collections

OUT = os.path.abspath(sys.argv[1])
BENCH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
case = sys.argv[sys.argv.index("--case") + 1] if "--case" in sys.argv else os.path.basename(OUT)
TRUTH = os.path.join(BENCH, "waivers", "corpus", case, "truth.json")
if not os.path.exists(TRUTH):
    sys.exit(f"no truth.json for case {case!r} at {TRUTH}")

truth = json.load(open(TRUTH))
T = {f["id"]: f for f in truth["findings"]}


def extract(path):
    """Pull the last fenced json block out of a claude --print --output-format json reply."""
    try:
        raw = json.load(open(path))
    except Exception:
        return None
    text = raw.get("result") if isinstance(raw, dict) else None
    if not isinstance(text, str):
        return None
    blocks = re.findall(r"```json\s*(.*?)```", text, re.S)
    for b in reversed(blocks):
        try:
            return json.loads(b)
        except json.JSONDecodeError:
            continue
    return None


reps = collections.defaultdict(list)
unparsed = collections.Counter()
for arm in sorted(os.listdir(OUT)):
    armdir = os.path.join(OUT, arm)
    if not os.path.isdir(armdir):
        continue
    for rep in sorted(os.listdir(armdir)):
        p = os.path.join(armdir, rep, "response.json")
        if not os.path.exists(p):
            continue
        got = extract(p)
        if got is None or "decisions" not in got:
            unparsed[arm] += 1
            continue
        reps[arm].append(got["decisions"])

if not reps:
    sys.exit(f"no parseable responses under {OUT}")

print(f"case: {case}   findings: {truth['expected']['total_findings']} "
      f"({truth['expected']['waivable_count']} waivable, "
      f"{truth['expected']['not_waivable_count']} not)\n")

per_finding = collections.defaultdict(lambda: collections.defaultdict(list))
summary = {}
for arm, runs in sorted(reps.items()):
    waived = wrong = overfix = rebutted = named_ground = 0
    tot_w = tot_nw = tot = 0
    bad_ground = 0
    for decisions in runs:
        seen = {d.get("id"): d for d in decisions if isinstance(d, dict)}
        for fid, t in T.items():
            d = seen.get(fid)
            if d is None:
                continue          # gate did not rule on it; counted only in coverage below
            act = str(d.get("action", "")).lower()
            is_waive = act.startswith("waive")
            is_rebut = act.startswith("rebut")
            tot += 1
            per_finding[fid][arm].append("waive" if is_waive
                                         else "rebut" if is_rebut else "fix")
            if t["waivable"]:
                tot_w += 1
                # A rebuttal is not a fix: the finding ships either way, so it is not the
                # cost C4's over-fixing rate is meant to capture. Whether the rebuttal was
                # *correct* is a separate question truth.json deliberately does not answer.
                if not is_waive and not is_rebut:
                    overfix += 1
            else:
                tot_nw += 1
                if is_waive:
                    wrong += 1
            if is_rebut:
                rebutted += 1
            if is_waive:
                waived += 1
                g = d.get("ground")
                g = None if g in (None, "null", "") else str(g)
                if g is not None:
                    named_ground += 1
                    if not t["waivable"] or g != t["ground"]:
                        bad_ground += 1
    n = len(runs)
    summary[arm] = dict(n=n, tot=tot, waived=waived, wrong=wrong, tot_nw=tot_nw,
                        overfix=overfix, tot_w=tot_w, bad_ground=bad_ground,
                        rebutted=rebutted, named_ground=named_ground)


def pct(a, b):
    return f"{100.0 * a / b:5.1f}%  ({a}/{b})" if b else "    n/a"


print(f"{'gate':9}{'reps':>5}  {'waiver rate':>18}{'wrong-waiver':>20}{'over-fixing':>20}")
print("-" * 74)
for arm, s in sorted(summary.items()):
    print(f"{arm:9}{s['n']:>5}  {pct(s['waived'], s['tot']):>18}"
          f"{pct(s['wrong'], s['tot_nw']):>20}{pct(s['overfix'], s['tot_w']):>20}")

if any(s["rebutted"] for s in summary.values()):
    print("\nrebuttals — a third disposition, offered only by gates that define one. truth.json")
    print("labels waivability, NOT whether a finding is factually sound, so these are counted")
    print("and not scored: judging them needs the same outside review as the labels.")
    for arm, s in sorted(summary.items()):
        print(f"  {arm}: {pct(s['rebutted'], s['tot'])} of decisions were rebuttals")

print("\nground naming (only gates that ask for one can miss; a ground the truth does not")
print("support is an enumeration being talked around rather than applied)")
for arm, s in sorted(summary.items()):
    if not s["waived"]:
        continue
    if s["named_ground"] == 0:
        print(f"  {arm}: names no grounds (its gate does not ask) — not comparable")
    else:
        print(f"  {arm}: {s['bad_ground']} of {s['named_ground']} named grounds unsupported")

print("\nper finding — dispositions as waive/rebut/fix out of n reps")
SHORT = {"out_of_scope": "out-of-scope", "pre_existing": "pre-existing",
         "approved_assumption": "assumption"}
arms = sorted(reps)
print(f"{'id':<4}{'truth':<26}" + "".join(f"{a:<12}" for a in arms))
for fid, t in T.items():
    label = f"waivable ({SHORT[t['ground']]})" if t["waivable"] else "NOT waivable"
    cells = []
    for a in arms:
        v = per_finding[fid][a]
        cells.append(f"{v.count('waive')}/{v.count('rebut')}/{v.count('fix')}" if v else "-")
    print(f"{fid:<4}{label:<26}" + "".join(f"{c:<12}" for c in cells))

if unparsed:
    print("\nunparseable responses (excluded):", dict(unparsed))

print(f"\n{truth['authorship_warning']}")
