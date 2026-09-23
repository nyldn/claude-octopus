#!/usr/bin/env bash
# Tests for session handoff — write-handoff.sh and integration with hooks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "session handoff — write-handoff.sh and integration with hooks"

HANDOFF="$PROJECT_ROOT/scripts/write-handoff.sh"
PRE_COMPACT="$PROJECT_ROOT/hooks/pre-compact.sh"
SESSION_END="$PROJECT_ROOT/hooks/session-end.sh"
RESUME_SKILL="$(resolve_claude_skill_path "skill-resume")"
GENERATED_RESUME_SKILL="$PROJECT_ROOT/skills/skill-resume/SKILL.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

run_as_hook() {
    local project="$1" home="$2" plugin_data="$3"
    shift 3
    (cd "$project" && env -u CLAUDE_OCTOPUS_WORKSPACE -u OCTOPUS_WORKFLOW_STATE_DIR \
        -u OCTOPUS_STATE_PROJECT_ROOT \
        "HOME=$home" "CLAUDE_PLUGIN_ROOT=$PROJECT_ROOT" "CLAUDE_PLUGIN_DATA=$plugin_data" \
        "CLAUDE_PROJECT_DIR=$project" "CLAUDE_SESSION_ID=test-session" \
        "$@" </dev/null)
}

run_as_session_shell() {
    local project="$1" home="$2"
    shift 2
    (cd "$project" && env -u CLAUDE_PLUGIN_DATA -u CLAUDE_OCTOPUS_WORKSPACE \
        -u OCTOPUS_WORKFLOW_STATE_DIR -u OCTOPUS_STATE_PROJECT_ROOT \
        "HOME=$home" "PATH=$PROJECT_ROOT/bin:$PATH" \
        "$@" </dev/null)
}

resume_handoff_path() {
    local state_file
    state_file="$(run_as_session_shell "$1" "$2" octopus state-path)"
    printf '%s/continue.md\n' "$(dirname "$state_file")"
}

extract_first_bash_block() {
    awk '
        /^```bash$/ && !found { found = 1; capture = 1; next }
        capture && /^```$/ { exit }
        capture { print }
    ' "$1"
}

# ── write-handoff.sh exists and is executable ────────────────────────

if [[ -f "$HANDOFF" ]]; then
    pass "write-handoff.sh exists"
else
    fail "write-handoff.sh exists" "file not found"
fi

if [[ -x "$HANDOFF" ]]; then
    pass "write-handoff.sh is executable"
else
    fail "write-handoff.sh is executable" "not executable"
fi

# ── Reads session.json ──────────────────────────────────────────────

if grep -q 'session.json' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh reads session.json"
else
    fail "write-handoff.sh reads session.json" "missing session.json reference"
fi

# ── Reads STATE.md ──────────────────────────────────────────────────

if grep -q 'STATE.md' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh reads STATE.md"
else
    fail "write-handoff.sh reads STATE.md" "missing STATE.md reference"
fi

# ── Has octopus branding ────────────────────────────────────────────

if grep -q '🐙' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh uses 🐙 branding"
else
    fail "write-handoff.sh uses 🐙 branding" "missing octopus emoji"
fi

# ── Includes resume instructions ────────────────────────────────────

if grep -q '/octo:resume' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh includes /octo:resume instructions"
else
    fail "write-handoff.sh includes /octo:resume instructions" "missing resume"
fi

# ── Pre-compact calls write-handoff.sh ──────────────────────────────

if grep -q 'write-handoff.sh' "$PRE_COMPACT" 2>/dev/null; then
    pass "pre-compact.sh calls write-handoff.sh"
else
    fail "pre-compact.sh calls write-handoff.sh" "not wired in pre-compact"
fi

# ── Session-end calls write-handoff.sh ──────────────────────────────

if grep -q 'write-handoff.sh' "$SESSION_END" 2>/dev/null; then
    pass "session-end.sh calls write-handoff.sh"
else
    fail "session-end.sh calls write-handoff.sh" "not wired in session-end"
fi

# ── Extracts decisions and blockers ─────────────────────────────────

if grep -q 'decisions' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh extracts decisions"
else
    fail "write-handoff.sh extracts decisions" "missing decisions extraction"
fi

if grep -q 'blockers' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh extracts blockers"
else
    fail "write-handoff.sh extracts blockers" "missing blockers extraction"
fi

# ── Reads the canonical progress.json array shape ───────────────────

test_case "write-handoff reads active agent from canonical progress.json"
TEST_ROOT="$TEST_TMP_DIR/handoff-fixture"
PLUGIN_DATA="$TEST_ROOT/plugin-data"
mkdir -p "$TEST_ROOT/home/.claude-octopus" "$PLUGIN_DATA" "$TEST_ROOT/work/.octo"
cat > "$TEST_ROOT/home/.claude-octopus/session.json" <<'EOF'
{"current_phase":"develop","workflow":"embrace","status":"running"}
EOF
cat > "$PLUGIN_DATA/progress.json" <<'EOF'
{"agents":[{"name":"codex","task_id":"task-1","status":"running"}]}
EOF
if run_as_hook "$TEST_ROOT/work" "$TEST_ROOT/home" "$PLUGIN_DATA" "$HANDOFF" && \
   grep -q '\*\*Active Agent:\*\* codex' "$(resume_handoff_path "$TEST_ROOT/work" "$TEST_ROOT/home")"; then
    test_pass
else
    test_fail "handoff did not read the active agent from progress.json's agents array"
fi

test_case "session hooks leave the project checkout clean"
HOOK_ROOT="$TEST_TMP_DIR/hook-fixture"
mkdir -p "$HOOK_ROOT/home/.claude-octopus" "$HOOK_ROOT/plugin-data" "$HOOK_ROOT/project"
git -C "$HOOK_ROOT/project" init -q
cat > "$HOOK_ROOT/home/.claude-octopus/session.json" <<'EOF'
{"current_phase":"init","workflow":"embrace","status":"running"}
EOF
run_as_hook "$HOOK_ROOT/project" "$HOOK_ROOT/home" "$HOOK_ROOT/plugin-data" \
    bash "$PRE_COMPACT" >/dev/null 2>&1 || true
run_as_hook "$HOOK_ROOT/project" "$HOOK_ROOT/home" "$HOOK_ROOT/plugin-data" \
    bash "$SESSION_END" >/dev/null 2>&1 || true
project_status="$(git -C "$HOOK_ROOT/project" status --porcelain --untracked-files=all)"
if [[ -z "$project_status" ]]; then
    test_pass
else
    test_fail "hooks dirtied the project checkout: $project_status"
fi

test_case "handoff lands beside the workflow state path that resume resolves"
hook_handoff="$(resume_handoff_path "$HOOK_ROOT/project" "$HOOK_ROOT/home")"
if grep -q 'Octopus Session Handoff' "$hook_handoff" 2>/dev/null; then
    test_pass
else
    test_fail "no handoff at $hook_handoff"
fi

for skill_file in "$RESUME_SKILL" "$GENERATED_RESUME_SKILL"; do
    label="${skill_file#"$PROJECT_ROOT"/}"
    handoff_step="$(extract_first_bash_block "$skill_file")"

    test_case "$label shows the relocated handoff ahead of a legacy project copy"
    printf '%s\n' 'legacy handoff from an older release' > "$HOOK_ROOT/project/.octo-continue.md"
    resume_output="$(run_as_session_shell "$HOOK_ROOT/project" "$HOOK_ROOT/home" \
        bash -c "$handoff_step" 2>&1 || true)"
    rm -f "$HOOK_ROOT/project/.octo-continue.md"
    if [[ "$resume_output" == *"Octopus Session Handoff"* && "$resume_output" != *"legacy handoff"* ]]; then
        test_pass
    else
        test_fail "resume handoff step printed: $resume_output"
    fi

    test_case "$label reads a legacy project handoff without changing the project"
    legacy_root="$TEST_TMP_DIR/legacy-${label//\//-}"
    mkdir -p "$legacy_root/home" "$legacy_root/project"
    printf '%s\n' 'legacy handoff from an older release' > "$legacy_root/project/.octo-continue.md"
    legacy_checksum="$(cksum < "$legacy_root/project/.octo-continue.md")"
    resume_output="$(run_as_session_shell "$legacy_root/project" "$legacy_root/home" \
        bash -c "$handoff_step" 2>&1 || true)"
    if [[ "$resume_output" == *"legacy handoff from an older release"* ]] &&
       [[ "$(cksum < "$legacy_root/project/.octo-continue.md")" == "$legacy_checksum" ]] &&
       [[ "$(ls -A "$legacy_root/project")" == ".octo-continue.md" ]]; then
        test_pass
    else
        test_fail "legacy fallback printed: $resume_output"
    fi
done
test_summary
