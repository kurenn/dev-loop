#!/usr/bin/env python3
"""Tier 1 assertions. Reads a run directory produced by run.sh and emits results.json.

Every assertion here is binary and mechanically checkable. Anything that needed a
judgement call was pushed to Tier 2 instead. Two assertions are explicitly best-effort
and labelled as such in the output: A7 (ordering) and A9 (ownership conformance) are
reconstructed from the transcript and from PLAN.md prose, so treat them as signal, not
proof. See bench/README.md.
"""
import json, os, re, subprocess, sys

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
R["A5_pushed_to_origin"] = {"pass": bool(pushed), "branches": pushed,
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
if wt and os.path.exists(os.path.join(wt, "PLAN.md")):
    plan = open(os.path.join(wt, "PLAN.md"), errors="replace").read()
    declared = set(re.findall(r"`([\w./-]+\.[a-z]{1,5})`", plan))
    rc, out, _ = git("diff", "--name-only", "main...HEAD", cwd=wt)
    changed = [f for f in out.splitlines() if f and not f.startswith(("PLAN", "REVIEW", "RATING", "LOOP_STATE"))]
    outside = [f for f in changed if f not in declared]
    a9.update(declared=sorted(declared)[:40], changed=changed, outside=outside,
              **{"pass": len(outside) == 0 if declared else None})
R["A9_ownership_conformance"] = a9

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
truncated = meta.get("exit_code") == 124
if truncated:
    for aid in ("A4_work_committed", "A5_pushed_to_origin", "A6_ship_handled"):
        R[aid]["pass"] = None
        R[aid]["truncated"] = True
        R[aid]["why_unknown"] = "run killed by BENCH_TIMEOUT before Phase 9; not a failure"

out = {"meta": meta, "truncated": truncated, "assertions": R, "metrics": M}
json.dump(out, open(os.path.join(RUN, "results.json"), "w"), indent=2)

banner = "  [TRUNCATED at BENCH_TIMEOUT - post-Phase-6 assertions unknown]" if truncated else ""
print(f"\n{meta['flow']}  {meta['task']}  #{meta['idx']}{banner}")
for k, v in R.items():
    if isinstance(v, dict) and "pass" in v:
        p = v["pass"]
        mark = "PASS" if p is True else ("FAIL" if p is False else "n/a ")
        flag = " (best-effort)" if v.get("best_effort") else ""
        print(f"  [{mark}] {k}{flag}")
print(f"  cost=${M['cost_usd']} tokens_out={M['output_tokens']} agents={M['agent_spawns']} wall={M['wall_seconds']}s")
