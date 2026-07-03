#!/usr/bin/env bash
# ralph — drive a spec/plan markdown to completion in an isolated worktree, one
# task per iteration. Fresh `claude -p` context each pass; durable state lives
# only in the spec + git. Runs in auto-accept-edits mode (no dangerous skips);
# Bash is scoped to an allowlist (override with RALPH_ALLOWED_TOOLS).
#   usage: ralph <spec.md> [max-iterations]
set -uo pipefail

spec_arg="${1:?usage: ralph <spec.md> [max-iterations]}"
max="${2:-30}"
allowed="${RALPH_ALLOWED_TOOLS:-Bash(git:*),Bash(go:*),Bash(make:*),Bash(npm:*),Bash(pnpm:*),Bash(yarn:*),Bash(pytest:*),Bash(python:*),Bash(python3:*),Bash(cargo:*),Bash(node:*)}"

repo=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "[ralph] not inside a git repo" >&2; exit 1; }
spec_abs=$(cd "$(dirname "$spec_arg")" 2>/dev/null && pwd)/$(basename "$spec_arg")
[[ -f "$spec_abs" ]] || { echo "[ralph] spec not found: $spec_arg" >&2; exit 1; }
[[ "$spec_abs" == "$repo/"* ]] || { echo "[ralph] spec must live inside the repo" >&2; exit 1; }
rel="${spec_abs#"$repo"/}"

# isolated worktree so an autonomous loop never touches your working tree
branch="ralph/$(basename "${rel%.*}")"
wt="$repo/.worktrees/$(printf '%s' "$branch" | tr / -)"
grep -qxF '.worktrees/' "$repo/.git/info/exclude" 2>/dev/null \
    || echo '.worktrees/' >> "$repo/.git/info/exclude"
[[ -d "$wt" ]] || git -C "$repo" worktree add -b "$branch" "$wt" HEAD

# make sure the spec exists in the worktree (it won't if it's still uncommitted)
if [[ ! -f "$wt/$rel" ]]; then
    mkdir -p "$wt/$(dirname "$rel")"
    cp "$spec_abs" "$wt/$rel"
fi
cd "$wt"

read -r -d '' prompt <<EOF || true
Read $rel. Find the FIRST unchecked task — a line matching "- [ ]".
Implement ONLY that one task, then run the project's build/tests to verify.

On success: change that line's "- [ ]" to "- [x]", then commit ALL changes with
a concise message naming the task.

If you cannot complete it: change its "- [ ]" to "- [!]", append an indented
"> blocked: <one-line reason>" beneath it, and commit only that spec edit.

Do exactly one task. Never touch other checkboxes. Never amend past commits.
EOF

# signature of every checkbox line — changes iff a box flips state
sig() { grep -nE '^[[:space:]]*- \[.\]' "$rel" 2>/dev/null | sha1sum; }

echo "[ralph] branch $branch | worktree $wt | max $max"
for ((i = 1; i <= max; i++)); do
    if ! grep -qE '^[[:space:]]*- \[ \]' "$rel"; then
        echo "[ralph] ✓ done — no unchecked tasks left after $((i - 1)) iteration(s)."
        break
    fi
    echo "── [ralph] iteration $i/$max ──────────────────────────"
    before=$(sig)
    if ! claude -p --permission-mode acceptEdits --allowedTools "$allowed" "$prompt"; then
        echo "[ralph] ✗ claude exited non-zero — stopping." >&2; exit 1
    fi
    if [[ "$(sig)" == "$before" ]]; then
        echo "[ralph] ✗ no checkbox changed state (stuck, or a needed tool was denied) — stopping." >&2
        exit 2
    fi
done

blocked=$(grep -cE '^[[:space:]]*- \[!\]' "$rel" 2>/dev/null || echo 0)
[[ "$blocked" -gt 0 ]] && echo "[ralph] ⚠ $blocked blocked task(s) — see '- [!]' lines in $rel."
echo "[ralph] review: git -C $repo log $branch    merge: git -C $repo merge $branch"
