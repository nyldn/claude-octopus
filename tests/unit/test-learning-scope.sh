#!/usr/bin/env bash
# Learned state never crosses projects or worktrees (sail-cruisey #3244: a
# codex prompt for one worktree carried another worktree's review-prompt path
# through the global heuristic pattern store).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Learning scope"

export HOME="$TEST_TMP_DIR/home"
export WORKSPACE_DIR="$HOME/.claude-octopus"
export PLUGIN_DIR="$REPO_ROOT"
mkdir -p "$WORKSPACE_DIR"
log() { :; }
source "$REPO_ROOT/scripts/lib/intelligence.sh"
source "$REPO_ROOT/scripts/lib/provider-lockout.sh"
PATTERNS="$HOME/.claude-octopus/.octo/patterns.jsonl"

# Two worktrees with the same layout; only B's run mentions its review prompt.
make_tree() {
    local dir="$1"
    mkdir -p "$dir/skills/blocks" "$dir/notes"
    printf 'skill\n' > "$dir/skills/blocks/simplify.md"
    printf 'prompt\n' > "$dir/notes/review-prompt.md"
    git -C "$dir" init -q
}
A="$TEST_TMP_DIR/worktree-a"; B="$TEST_TMP_DIR/worktree-b"
make_tree "$A"; make_tree "$B"
B_REAL="$(cd "$B" && pwd -P)"

RESULT="$TEST_TMP_DIR/result.md"
printf 'Read skills/blocks/simplify.md and notes/review-prompt.md.\nAlso %s/notes/review-prompt.md and ../outside/secret.md.\n' "$B_REAL" > "$RESULT"
for _ in 1 2; do PROJECT_ROOT="$B" record_run_pattern codex "review" "$RESULT"; done

test_case "a recorded pattern carries its scope root and only relative in-tree paths"
if jq -e --arg root "$B_REAL" -s 'length == 2 and all(.[]; .root == $root and .files == "notes/review-prompt.md,skills/blocks/simplify.md")' "$PATTERNS" >/dev/null; then test_pass
else test_fail "patterns: $(cat "$PATTERNS")"; fi

test_case "the same worktree still gets its learned hint"
hint="$(PROJECT_ROOT="$B" build_heuristic_context "Edit skills/blocks/simplify.md")"
if [[ "$hint" == *"notes/review-prompt.md"* ]]; then test_pass; else test_fail "hint: '$hint'"; fi

test_case "another worktree with the same files gets nothing from B"
hint="$(PROJECT_ROOT="$A" build_heuristic_context "Edit skills/blocks/simplify.md")"
if [[ -z "$hint" ]]; then test_pass; else test_fail "leaked hint: '$hint'"; fi

test_case "legacy patterns with no scope root are ignored"
for _ in 1 2; do printf '%s\n' '{"ts":"2026-10-09T00:00:00Z","agent":"codex","prompt_sig":"x","files":"skills/blocks/simplify.md,notes/review-prompt.md"}' >> "$PATTERNS"; done
printf '%s\n' 'not json {' >> "$PATTERNS"
hint="$(PROJECT_ROOT="$A" build_heuristic_context "Edit skills/blocks/simplify.md")"
if [[ -z "$hint" ]]; then test_pass; else test_fail "legacy hint: '$hint'"; fi

test_case "a malformed line does not hide later in-scope patterns"
# Malformed line first, then the only valid records, so a parser that stops
# at the bad line returns nothing.
saved_patterns="$TEST_TMP_DIR/patterns.saved"
cp "$PATTERNS" "$saved_patterns"
{ printf '%s\n' 'not json {'; grep -F "\"root\":\"$B_REAL\"" "$saved_patterns"; } > "$PATTERNS"
first_line="$(head -1 "$PATTERNS")"
hint="$(PROJECT_ROOT="$B" build_heuristic_context "Edit skills/blocks/simplify.md")"
cp "$saved_patterns" "$PATTERNS"
if [[ "$first_line" == "not json {" && "$hint" == *"notes/review-prompt.md"* ]]; then test_pass; else test_fail "hint: '$hint'"; fi

test_case "a symlink that leaves the worktree is not an in-scope path"
OUTSIDE="$TEST_TMP_DIR/outside"; mkdir -p "$OUTSIDE/dir"
printf 'secret\n' > "$OUTSIDE/secret.md"; printf 'x\n' > "$OUTSIDE/dir/inner.md"
ln -s "$OUTSIDE/secret.md" "$B/notes/linked.md"
ln -s "$OUTSIDE/dir" "$B/linkdir"
if ! octo_project_scope_has_path "$B_REAL" notes/linked.md &&
   ! octo_project_scope_has_path "$B_REAL" linkdir/inner.md &&
   octo_project_scope_has_path "$B_REAL" notes/review-prompt.md; then test_pass
else test_fail "a symlinked path outside the worktree was accepted"; fi

test_case "provider history from one worktree is not read in another"
PROJECT_ROOT="$B" append_provider_history codex tangle "task" "worktree B learning"
ctx_b="$(PROJECT_ROOT="$B" build_provider_context codex)"
ctx_a="$(PROJECT_ROOT="$A" build_provider_context codex)"
if [[ "$ctx_b" == *"worktree B learning"* && -z "$ctx_a" ]]; then test_pass
else test_fail "B: '${ctx_b:0:80}' A: '${ctx_a:0:80}'"; fi

test_summary
