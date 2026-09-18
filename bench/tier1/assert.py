#!/usr/bin/env python3
"""Tier 1 assertions. Reads a run directory produced by run.sh and emits results.json.

Every assertion here is binary and mechanically checkable. Anything that needed a
judgement call was pushed to Tier 2 instead. Two assertions are explicitly best-effort
and labelled as such in the output: A7 (ordering) and A9 (ownership conformance) are
reconstructed from the transcript and from PLAN.md prose, so treat them as signal, not
proof. See bench/README.md.
"""
import fnmatch, json, os, re, subprocess, sys

RUN = os.path.abspath(sys.argv[1])
APP = os.path.join(RUN, "app")
ORIGIN = os.path.join(RUN, "origin.git")


def sh(*args, cwd=None):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def git(*args, cwd=APP):
    return sh("git", *args, cwd=cwd)


def load_transcript():
    events = []
    path = os.path.join(RUN, "transcript.jsonl")
    if not os.path.exists(path):
        return events
    for line in open(path, errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return events


def tool_uses(events):
    """Flatten every tool_use block in assistant messages, in order."""
    out = []
    for e in events:
        msg = e.get("message") or {}
        for block in msg.get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                out.append({"name": block.get("name"), "input": block.get("input") or {}})
    return out


def worktrees():
    rc, out, _ = git("worktree", "list", "--porcelain")
    if rc != 0:
        return []
    trees, cur = [], {}
    for line in out.splitlines():
        if line.startswith("worktree "):
            if cur:
                trees.append(cur)
            cur = {"path": line.split(" ", 1)[1]}
        elif line.startswith("branch "):
            cur["branch"] = line.split(" ", 1)[1].replace("refs/heads/", "")
    if cur:
        trees.append(cur)
    return trees


events = load_transcript()
tools = tool_uses(events)
meta = json.load(open(os.path.join(RUN, "meta.json")))
trees = worktrees()
loop_trees = [t for t in trees if os.path.abspath(t["path"]) != os.path.abspath(APP)]
wt = loop_trees[0]["path"] if loop_trees else None

R = {}

# --- A1: the main checkout is untouched ------------------------------------
rc, branch, _ = git("symbolic-ref", "--short", "HEAD")
rc2, porcelain, _ = git("status", "--porcelain")
dirty = [l for l in porcelain.splitlines() if ".worktrees/" not in l]
R["A1_main_checkout_clean"] = {
    "pass": branch == "main" and not dirty,
    "branch": branch,
    "dirty_entries": dirty[:20],
    "why": "v0.1 gives subagents no worktree path, so they edit this checkout instead",
}

# --- A2: a worktree was created --------------------------------------------
R["A2_worktree_created"] = {"pass": wt is not None, "worktrees": [t.get("path") for t in loop_trees]}

# --- A3: that worktree can actually boot and run the suite ------------------
a3 = {"pass": False, "master_key": False, "suite_rc": None, "best_effort": False}
if wt:
    a3["master_key"] = os.path.exists(os.path.join(wt, "config", "master.key"))
    env = dict(os.environ)
    rc, out, err = sh("bin/rails", "test", cwd=wt)
    a3["suite_rc"] = rc
    a3["suite_tail"] = (out or err).splitlines()[-6:]
    a3["pass"] = a3["master_key"] and rc == 0
R["A3_worktree_bootable"] = a3
R["A3_worktree_bootable"]["why"] = "git worktree add checks out tracked files only; master.key is gitignored"

# --- A4: work was committed on the worktree branch --------------------------
a4 = {"pass": False, "ahead": 0}
if wt:
    rc, out, _ = git("rev-list", "--count", "main..HEAD", cwd=wt)
    a4["ahead"] = int(out) if rc == 0 and out.isdigit() else 0
    a4["pass"] = a4["ahead"] > 0
R["A4_work_committed"] = a4

# --- A5: the branch was pushed to origin ------------------------------------
rc, out, _ = sh("git", "for-each-ref", "--format=%(refname:short)", "refs/heads", cwd=ORIGIN)
pushed = [b for b in out.splitlines() if b != "main"]
# A pushed ref proves nothing on its own: a branch created off main and pushed before any
# commit lands here looking like success. Require it to actually carry commits.
with_commits = []
for b in pushed:
    rc2, cnt, _ = sh("git", "rev-list", "--count", f"main..{b}", cwd=ORIGIN)
    if rc2 == 0 and cnt.isdigit() and int(cnt) > 0:
        with_commits.append(f"{b} (+{cnt})")
R["A5_pushed_to_origin"] = {"pass": bool(with_commits), "branches": pushed,
                            "branches_with_commits": with_commits,
                            "why": "v0.1 called gh pr create without ever committing or pushing"}

# --- A6: shipping was handled, not silently failed --------------------------
# The bench origin is a bare local repo, so a real PR is impossible by construction.
# Passing means: the branch got pushed AND the run ended by telling the user what is left.
final = ""
for e in reversed(events):
    if e.get("type") == "result":
        final = e.get("result") or ""
        break
mentions_next_step = bool(re.search(r"\b(pr|pull request|push|branch)\b", final, re.I))
R["A6_ship_handled"] = {"pass": bool(pushed) and mentions_next_step,
                        "final_mentions_next_step": mentions_next_step,
                        "final_tail": final[-400:]}

# --- A7: no paid review ran while the suite was red (best effort) -----------
review_at = None
for i, t in enumerate(tools):
    blob = json.dumps(t["input"])
    if "codex-companion" in blob or "adversarial-review" in blob.lower():
        review_at = i
        break
    if t["name"] in ("Task", "Agent") and re.search(r"advers|rate|rating|review", blob, re.I):
        review_at = i
        break
red_before = None
if review_at is not None:
    for t in tools[:review_at][::-1]:
        cmd = str(t["input"].get("command", ""))
        if re.search(r"\b(rails test|rspec|npm test|go test|pytest)\b", cmd):
            red_before = cmd
            break
R["A7_no_review_on_red"] = {"pass": review_at is None or red_before is not None,
                            "best_effort": True,
                            "review_tool_index": review_at,
                            "last_test_before_review": red_before,
                            "note": "ordering reconstructed from the parent transcript; subagent-internal calls are not visible"}

# --- A8: which phase artifacts were produced --------------------------------
arts = {}
if wt:
    for name in ("PLAN.md", "PLAN-CRITIQUE.md", "LOOP_STATE.md"):
        arts[name] = os.path.exists(os.path.join(wt, name))
    listing = os.listdir(wt)
    arts["REVIEW-round-*"] = [f for f in listing if f.startswith("REVIEW-round")]
    arts["RATING-round-*"] = [f for f in listing if f.startswith("RATING-round")]
R["A8_artifacts"] = arts

# --- A9: did the diff stay inside the plan's declared ownership? ------------
a9 = {"pass": None, "best_effort": True, "declared": [], "outside": []}
plan_path = os.path.join(wt, "PLAN.md") if wt else None
plan = open(plan_path, errors="replace").read() if plan_path and os.path.exists(plan_path) else ""
# Only meaningful for a flow whose plan actually declares per-unit file ownership. v0.1 has
# no ownership model at all, so scoring it here would be marking it down for not doing
# something it never claimed to do.
declares_ownership = bool(re.search(r"^\s*[-*].*\bowns:", plan, re.M))
if not declares_ownership:
    a9["note"] = "plan declares no per-unit file ownership; assertion not applicable to this flow"
elif wt:
    # Parse ownership from the `owns:` lines only. Regexing every backticked token out of
    # the whole plan swept up prose (`Project.count`, `CLAUDE.md`) and missed nothing,
    # which made the assertion measure the regex rather than the loop.
    # An ownership clause runs from `owns:` to the `· does:` delimiter and often wraps
    # across lines, so parse the clause, not the line.
    declared = set()
    for clause in re.findall(r"\bowns:(.*?)(?:·\s*does:|\n\s*\n|\Z)", plan, re.S):
        declared |= set(re.findall(r"`([\w./*-]+)`", clause))

    # Artifacts the loop authors by design are never "outside ownership".
    LOOP_ARTIFACTS = ("PLAN.md", "PLAN-CRITIQUE.md", "LOOP_STATE.md", "RED-PROOF.md",
                      "HANDOFFS.md")
    def is_loop_artifact(f):
        base = os.path.basename(f)
        return (base in LOOP_ARTIFACTS or base.startswith(("REVIEW-round", "RATING-round"))
                or "dev-loop-learnings" in f)

    # A generated migration carries a timestamp the plan cannot know in advance, and
    # schema.rb is a mechanical by-product of running one. Compare on the stable part.
    def norm(f):
        d, b = os.path.split(f)
        return os.path.join(d, re.sub(r"^\d{10,}_", "", b))
    norm_declared = {norm(x) for x in declared}
    dirs_declared = {os.path.dirname(x) for x in declared if os.path.dirname(x)}

    def covered(f):
        if norm(f) in norm_declared or f in declared:
            return True
        if os.path.basename(f) == "schema.rb" and "db/migrate" in " ".join(dirs_declared):
            return True
        for x in declared:
            # A trailing / or * declares a directory or prefix.
            if x.endswith(("/", "*")) and f.startswith(x.rstrip("*")):
                return True
            # A glob anywhere else in the clause, e.g. `test/**/*_test.rb`. Matching only
            # trailing globs scored `test/controllers/api/v1/*_test.rb` as a violation of
            # the very path it declares, which measured the regex rather than the loop.
            if any(c in x for c in "*?[") and (fnmatch.fnmatch(f, x)
                                               or fnmatch.fnmatch(norm(f), x)):
                return True
        return False

    rc, out, _ = git("diff", "--name-only", "main...HEAD", cwd=wt)
    changed = [f for f in out.splitlines() if f and not is_loop_artifact(f)]
    outside = [f for f in changed if not covered(f)]
    a9.update(declared=sorted(declared)[:40], changed=changed, outside=outside,
              **{"pass": len(outside) == 0 if declared else None})
R["A9_ownership_conformance"] = a9

# --- A10-A12: the v0.3 information-flow assertions --------------------------
# Applicability is read from the arm's own skill body, not from its version string, so an
# arm is never marked down for omitting something it never claimed. Same principle as A9.
skill = ""
flow_dir = meta.get("flow_dir")
if flow_dir:
    p = os.path.join(flow_dir, "skills", "dev-loop", "SKILL.md")
    if os.path.exists(p):
        skill = open(p, errors="replace").read()
claims_handoffs = "HANDOFFS.md" in skill
claims_state_schema = bool(re.search(r"LOOP_STATE\.md\b.*\brewritten\b", skill))
NA = "arm's skill body does not claim this; assertion not applicable to this flow"

# A10: one four-field handoff per plan unit was collected.
a10 = {"pass": None, "note": NA}
if claims_handoffs:
    a10 = {"pass": False, "exists": False, "units": 0, "entries": 0}
    hpath = os.path.join(wt, "HANDOFFS.md") if wt else None
    if hpath and os.path.exists(hpath):
        h = open(hpath, errors="replace").read()
        a10["exists"] = True
        # A unit line in the plan looks like `- **1.2 name** · owns: ...`.
        a10["units"] = len(re.findall(r"^\s*[-*]\s*\*\*\d+\.\d+\s", plan, re.M))
        # An entry is identified by its CHANGED heading; the other three must appear too.
        a10["entries"] = len(re.findall(r"^\s*#*\s*\**CHANGED\b", h, re.M))
        a10["all_four_fields"] = all(
            len(re.findall(rf"^\s*#*\s*\**{f}\b", h, re.M)) >= a10["entries"] > 0
            for f in ("CHANGED", "NOT DONE", "DEVIATIONS", "CONCERNS"))
        a10["pass"] = (a10["entries"] >= a10["units"] > 0) and a10["all_four_fields"]
    a10["why"] = "the brief asks for a handoff; this checks it was collected, not discarded"
R["A10_handoffs_collected"] = a10

# A11: every deviation/concern raised got a disposition (best effort).
# Mechanically we can only check that dispositions were recorded at all when something was
# raised. Whether each one is answered *well* is a judgement call and belongs in Tier 2.
a11 = {"pass": None, "note": NA}
if claims_handoffs:
    a11 = {"pass": None, "best_effort": True, "raised": 0, "dispositions": 0}
    hpath = os.path.join(wt, "HANDOFFS.md") if wt else None
    spath = os.path.join(wt, "LOOP_STATE.md") if wt else None
    if hpath and os.path.exists(hpath):
        h = open(hpath, errors="replace").read()
        # Content under a DEVIATIONS/CONCERNS heading, up to the next heading.
        bodies = re.findall(r"^\s*#*\s*\**(?:DEVIATIONS|CONCERNS)\**:?\s*(.*?)(?=^\s*#*\s*\**(?:CHANGED|NOT DONE|DEVIATIONS|CONCERNS)\b|\Z)",
                            h, re.M | re.S)
        # "none", "n/a", "-" and empty bodies are not things that need answering.
        a11["raised"] = sum(1 for b in bodies
                            if len(re.sub(r"[\s*_.\-]|none|n/?a|nothing", "", b, flags=re.I)) > 12)
        state = open(spath, errors="replace").read() if spath and os.path.exists(spath) else ""
        section = re.search(r"^Amendments & rebuttals:(.*?)(?=^\w[\w ]*:|\Z)", state, re.M | re.S)
        body = section.group(1) if section else ""
        a11["dispositions"] = len([l for l in body.splitlines()
                                   if len(re.sub(r"[\s*_.\-]|none", "", l, flags=re.I)) > 8])
        a11["pass"] = (a11["dispositions"] > 0) if a11["raised"] > 0 else None
        if a11["raised"] == 0:
            a11["note"] = "no deviations or concerns were raised; nothing to answer"
    a11["why"] = "handoff information that is collected and never answered is information thrown away"
R["A11_handoffs_answered"] = a11

# A12: LOOP_STATE.md is a rewritten state file, not an appended log.
# The proxy for "rewritten" is that exactly one phase marker survives in the final file.
# An appended log accumulates one per phase boundary, which is the failure this checks.
a12 = {"pass": None, "note": NA}
if claims_state_schema:
    a12 = {"pass": False, "exists": False, "lines": 0, "phase_markers": 0, "missing_keys": []}
    spath = os.path.join(wt, "LOOP_STATE.md") if wt else None
    if spath and os.path.exists(spath):
        state = open(spath, errors="replace").read()
        a12["exists"] = True
        a12["lines"] = len(state.splitlines())
        a12["phase_markers"] = len(re.findall(r"^\s*\**Phase\**\s*:", state, re.M))
        keys = ["Task", "Tier", "Worktree", "Branch", "Baseline", "Phase", "Degraded", "Trace", "Gate"]
        a12["missing_keys"] = [k for k in keys if not re.search(rf"\**{k}\**\s*:", state)]
        a12["pass"] = (a12["phase_markers"] == 1 and a12["lines"] <= 60
                       and not a12["missing_keys"])
    a12["why"] = "a state file buries the resume path once it becomes a diary; bound is ~40 lines, 60 allowed"
R["A12_loop_state_rewritten"] = a12

# --- gate disposition, and shipping that was withheld on purpose ------------
# A4-A6 ask whether the work shipped. A loop that stopped at a blocked gate did not ship
# *by design*: the skill tells it to record the failure and report rather than ship past a
# finding it could not clear. Scoring that identically to a loop that simply never
# committed inverts what the gate is for, and penalises the arm hardest whose gate is
# strictest. This is the truncation guard's principle applied to a deliberate stop rather
# than an interrupted one - a phase the loop chose not to reach is not a phase it failed.
#
# v0.3 writes a fixed `Gate:` line so detection there is exact. v0.2.6 has no schema for
# it and has to be matched on prose; anything that does not match cleanly is reported
# `unknown` and flagged for a human rather than guessed into a number.
BLOCKED_RE = r"blocked|not met|unmet|failed|stopped|\bred\b"
MET_RE = r"green\b|(?<!not )met\b|passed\b"

state_text = ""
_spath = os.path.join(wt, "LOOP_STATE.md") if wt else None
if _spath and os.path.exists(_spath):
    state_text = open(_spath, errors="replace").read()


def gate_disposition(state, final):
    """-> (disposition, evidence, source). Blocked is preferred on a tie: 'not met'
    contains 'met', and a run that ends ambiguous should not be read as shipping-clean."""
    m = re.search(r"^\s*\**Gate\**\s*:\s*(.+)$", state, re.M)
    if m:
        v = m.group(1).strip()
        if re.search(rf"(?i)^\W*({BLOCKED_RE})", v):
            return "blocked", v[:200], "Gate: line"
        if re.search(r"(?i)^\W*pending", v):
            return "unknown", v[:200], "Gate: line still pending"
        if re.search(rf"(?i)^\W*({MET_RE})", v):
            return "met", v[:200], "Gate: line"
    for src, label in ((state, "LOOP_STATE prose"), (final, "final message")):
        if not src:
            continue
        hits = [(m.start(), "blocked", m.group(0)) for m in
                re.finditer(rf"(?i)\bgate\b[^.\n]{{0,60}}?({BLOCKED_RE})", src)]
        hits += [(m.start(), "met", m.group(0)) for m in
                 re.finditer(rf"(?i)\bgate\b[^.\n]{{0,60}}?({MET_RE})", src)]
        if not hits:
            continue
        # Take the *last* verdict in the file, not the first. A run clears the Phase 5
        # mechanical gate long before Phase 8 decides anything, and both are called "gate"
        # in free-form prose, so the first match is usually Phase 5 and says nothing about
        # whether the run shipped. Ties go to blocked, since "not met" contains "met".
        hits.sort(key=lambda h: (h[0], h[1] == "blocked"))
        _, verdict, ev = hits[-1]
        note = label + (" (several verdicts; last one taken)" if len(hits) > 1 else "")
        return verdict, ev[:200], note
    return "unknown", "", "no gate verdict found"


disp, evidence, source = gate_disposition(state_text, final)
G = {"disposition": disp, "evidence": evidence, "source": source}

if disp == "blocked":
    for aid in ("A4_work_committed", "A5_pushed_to_origin", "A6_ship_handled"):
        if R[aid]["pass"] is False:
            R[aid]["pass"] = None
            R[aid]["withheld"] = True
            R[aid]["why_withheld"] = ("the gate was blocked, so the loop was supposed to "
                                      "stop here; not shipping is the correct outcome")
elif R["A4_work_committed"]["pass"] is False:
    # Did not ship, and the gate does not say it was supposed to stop. Either the prose
    # match landed on the wrong gate - v0.2.6 has no schema and calls Phase 5 a "gate"
    # too - or the loop cleared Phase 8 and then failed to ship, which is a real defect.
    # The two are indistinguishable mechanically and neither is safe to score, so flag it
    # rather than let a wrong reading become a number.
    G["needs_human_review"] = True
    G["contradiction"] = f"gate reads '{disp}' but nothing was committed"
    for aid in ("A4_work_committed", "A5_pushed_to_origin", "A6_ship_handled"):
        R[aid]["needs_human_review"] = True

# A14: the gate was honoured. A13 is reserved for the C2 fault-injection check in
# bench/PLAN-v0.3.md, which is a capability probe and does not run on a normal run.
# This is the inverse of A4-A6 and the one that actually matters: pushing work to origin
# after the gate came back blocked is shipping through the gate, which is the single
# failure this whole loop exists to prevent.
R["A14_gate_honoured"] = {
    "pass": None if disp == "unknown" else not (disp == "blocked" and bool(with_commits)),
    "disposition": disp,
    "pushed_with_commits": with_commits,
    "why": "a blocked gate that pushes anyway has defeated the only mechanism that matters",
}

# --- metrics ---------------------------------------------------------------
result_ev = next((e for e in reversed(events) if e.get("type") == "result"), {})
usage = result_ev.get("usage") or {}
spawns = [t for t in tools if t["name"] in ("Task", "Agent")]
models = {}
for t in spawns:
    models[t["input"].get("model", "inherit")] = models.get(t["input"].get("model", "inherit"), 0) + 1
hist = {}
for t in tools:
    hist[t["name"]] = hist.get(t["name"], 0) + 1
changed_n = 0
if wt:
    rc, out, _ = git("diff", "--shortstat", "main...HEAD", cwd=wt)
    changed_n = out

M = {
    "wall_seconds": meta.get("wall_seconds"),
    "exit_code": meta.get("exit_code"),
    "cost_usd": result_ev.get("total_cost_usd"),
    "input_tokens": usage.get("input_tokens"),
    "output_tokens": usage.get("output_tokens"),
    "num_turns": result_ev.get("num_turns"),
    "agent_spawns": len(spawns),
    "spawn_models": models,
    "tool_histogram": hist,
    "diff_shortstat": changed_n,
}

# --- truncation guard ------------------------------------------------------
# exit 124 is `timeout` killing the run. Anything the loop had not reached yet is
# unknown, not failed. Blanking these is the difference between a measurement and a
# fabricated finding.
result_seen = any(e.get("type") == "result" for e in events)
truncated = meta.get("exit_code") == 124 or not result_seen
if truncated:
    for aid in ("A4_work_committed", "A5_pushed_to_origin", "A6_ship_handled"):
        R[aid]["pass"] = None
        R[aid]["truncated"] = True
        R[aid]["why_unknown"] = ("run did not complete (timeout, or the transcript has no "
                                 "result event); unreached phases are unknown, not failed")

out = {"meta": meta, "truncated": truncated, "gate": G, "assertions": R, "metrics": M}
json.dump(out, open(os.path.join(RUN, "results.json"), "w"), indent=2)

banner = ""
if truncated:
    why = "BENCH_TIMEOUT" if meta.get("exit_code") == 124 else "no result event - run ended early"
    banner = f"  [INCOMPLETE: {why} - unreached assertions unknown]"
print(f"\n{meta['flow']}  {meta['task']}  #{meta['idx']}{banner}")
for k, v in R.items():
    if isinstance(v, dict) and "pass" in v:
        p = v["pass"]
        mark = "PASS" if p is True else ("FAIL" if p is False else "n/a ")
        flag = " (best-effort)" if v.get("best_effort") else ""
        if v.get("withheld"):
            flag += " (withheld: gate blocked)"
        print(f"  [{mark}] {k}{flag}")
print(f"  gate={G['disposition']}"
      + (f"  [NEEDS HUMAN REVIEW: {G.get('contradiction', '')}]"
         if G.get("needs_human_review") else ""))
print(f"  cost=${M['cost_usd']} tokens_out={M['output_tokens']} agents={M['agent_spawns']} wall={M['wall_seconds']}s")
