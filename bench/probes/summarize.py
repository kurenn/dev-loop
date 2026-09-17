#!/usr/bin/env python3
"""Aggregate shipped-defect probes across a results tree.

The number that matters is not "how many runs carried a defect" but **how many shipped one**.
A run that carried a defect and blocked at the gate is the loop working; a run that carried
one and pushed is the loop failing at the only job it has. Those are the same row in every
other view in this harness, which is why the defect went unnoticed for so long.

Usage: python3 bench/probes/summarize.py <results-tree>
"""
import json, os, re, sys, collections

ROOT = os.path.abspath(sys.argv[1])
PROBE_RE = re.compile(r"DEFECT\s+(D\d+)")
TESTNAME_RE = re.compile(r"#test_(D\d+)_")

runs = []
for dp, _, files in os.walk(ROOT):
    if "meta.json" not in files or "probe.txt" not in files:
        continue
    meta = json.load(open(os.path.join(dp, "meta.json")))
    out = open(os.path.join(dp, "probe.txt"), errors="replace").read()

    present = set(PROBE_RE.findall(out))
    # An errored probe never prints its message, so pick those up from the test name.
    for block in re.split(r"\n(?=(?:Failure|Error):)", out):
        if block.startswith("Error:"):
            m = TESTNAME_RE.search(block)
            if m:
                present.add(m.group(1))
    skipped = set()
    for block in re.split(r"\n(?=Skipped:)", out):
        if block.startswith("Skipped:"):
            m = TESTNAME_RE.search(block)
            if m:
                skipped.add(m.group(1))

    gate = "unscored"
    incomplete = False
    rp = os.path.join(dp, "results.json")
    if os.path.exists(rp):
        try:
            res = json.load(open(rp))
            gate = (res.get("gate") or {}).get("disposition", "unscored")
            # A loop that reached no gate verdict and committed nothing did not finish, and a
            # run that did not finish is evidence about the environment, not about the skill.
            # Measured: an API rate limit killed a run at Phase 2 and it was scored as an arm
            # that carried a defect and declined to ship, which flatters the arm twice over.
            committed = (res.get("assertions", {}).get("A4_work_committed") or {}).get("pass")
            incomplete = gate in ("unknown", "unscored") and committed is False
        except Exception:
            pass
    ran = re.search(r"(\d+) runs, (\d+) assertions", out)
    runs.append(dict(flow=meta["flow"], task=meta["task"], idx=meta["idx"],
                     present=present, skipped=skipped, gate=gate,
                     incomplete=incomplete, exit_code=meta.get("exit_code"),
                     ok=bool(ran)))

if not runs:
    sys.exit(f"no probed runs under {ROOT} — run bench/probes/run-probes.sh first")

broken = [r for r in runs if not r["ok"]]
aborted = [r for r in runs if r["incomplete"]]
runs = [r for r in runs if not r["incomplete"]]
if not runs:
    sys.exit("every probed run was incomplete — nothing to compare")

ids = sorted({d for r in runs for d in r["present"] | r["skipped"]},
             key=lambda s: int(s[1:]))

print(f"probed runs: {len(runs)}" + (f"   ({len(broken)} produced no test output)" if broken else ""))
if aborted:
    print("excluded as incomplete — no gate verdict and nothing committed, so the run says")
    print("nothing about the skill: " +
          ", ".join(f"{r['flow']}/{r['task']}-{r['idx']} (exit {r['exit_code']})" for r in aborted))
print("\na defect that SHIPPED is one present in a run whose gate came back met\n")

groups = collections.defaultdict(list)
for r in runs:
    groups[(r["flow"], r["task"])].append(r)

w = max(len(f"{f} {t}") for f, t in groups) + 2
print(f"{'arm / task':<{w}}{'n':<4}{'carried':<10}{'SHIPPED':<10}{'blocked':<10}")
print("-" * (w + 34))
for (flow, task), rs in sorted(groups.items()):
    carried = [r for r in rs if r["present"]]
    shipped = [r for r in carried if r["gate"] == "met"]
    blocked = [r for r in carried if r["gate"] == "blocked"]
    print(f"{flow + ' ' + task:<{w}}{len(rs):<4}"
          f"{len(carried)}/{len(rs):<8}{len(shipped)}/{len(rs):<8}{len(blocked)}/{len(rs):<8}")

if ids:
    print("\nper defect class — runs carrying it / runs that shipped it")
    print(f"{'id':<5}{'':<2}" + "".join(f"{f + ' ' + t:<24}" for f, t in sorted(groups)))
    for d in ids:
        cells = []
        for k in sorted(groups):
            rs = groups[k]
            carried = [r for r in rs if d in r["present"]]
            shipped = [r for r in carried if r["gate"] == "met"]
            skips = [r for r in rs if d in r["skipped"]]
            cell = f"{len(carried)}/{len(rs)} carried, {len(shipped)} shipped"
            if skips:
                cell += f" ({len(skips)} n/a)"
            cells.append(cell)
        print(f"{d:<5}{'':<2}" + "".join(f"{c:<24}" for c in cells))

print("\nSeverity is declared in the probe file, not here. D1, D3 and D5 are minor by the")
print("probes' own labelling; treating a minor defect as a headline is the error this")
print("harness already made once.")
if broken:
    print("\nruns with no parseable probe output:",
          ", ".join(f"{r['flow']}/{r['task']}-{r['idx']}" for r in broken))
