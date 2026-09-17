#!/usr/bin/env bash
# Step 0 — resolve environment and config. SKILL.md "Step 0".
set -uo pipefail
. "$(dirname "$0")/../lib/phase.sh"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository"
MAIN="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
if [ -z "$MAIN" ]; then
  if git rev-parse --verify -q main >/dev/null; then MAIN=main; else MAIN=master; fi
fi
CODEX_DIR="$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1)"
gh repo view >/dev/null 2>&1 && GH=ok || GH=unavailable

# The project profile lives in CLAUDE.md. Absence is not an error — the skill says to
# detect what it can and report that /dev-loop-setup would make future runs cheaper.
PROFILE=""
[ -f "$ROOT/CLAUDE.md" ] && grep -q '^## Dev-loop config' "$ROOT/CLAUDE.md" && PROFILE="$ROOT/CLAUDE.md"

emit --arg root "$ROOT" --arg main "$MAIN" --arg gh "$GH" \
     --arg codex "${CODEX_DIR:-}" --arg profile "$PROFILE" \
     '{root:$root, main:$main, gh:$gh, codex_dir:$codex, profile:$profile,
       profiled: ($profile != "")}'
