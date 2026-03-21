#!/usr/bin/env bash
# Tests for Persistent Run Store (CONSOLIDATED-03)
# Validates: run-store.sh library, /octo:history command, plugin registration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUN_STORE_LIB="$PROJECT_ROOT/scripts/lib/run-store.sh"
HISTORY_CMD="$PROJECT_ROOT/.claude/commands/history.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── run-store.sh existence and syntax ─────────────────────────────────────────

if [[ -f "$RUN_STORE_LIB" ]]; then
    pass "run-store.sh exists"
else
    fail "run-store.sh exists" "not found at $RUN_STORE_LIB"
fi

if bash -n "$RUN_STORE_LIB" 2>/dev/null; then
    pass "run-store.sh has valid bash syntax"
else
    fail "run-store.sh has valid bash syntax" "syntax error"
fi

# ── Core functions exist ──────────────────────────────────────────────────────

if grep -q 'record_run()' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "record_run() function exists"
else
    fail "record_run() function exists" "missing"
fi

if grep -q 'record_experiment()' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "record_experiment() function exists"
else
    fail "record_experiment() function exists" "missing"
fi

if grep -q 'query_runs()' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "query_runs() function exists"
else
    fail "query_runs() function exists" "missing"
fi

if grep -q 'get_run_store_stats()' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "get_run_store_stats() function exists"
else
    fail "get_run_store_stats() function exists" "missing"
fi

# ── Schema fields ─────────────────────────────────────────────────────────────

for field in date workflow providers timestamp findings_count status duration_ms metadata; do
    if grep -q "$field" "$RUN_STORE_LIB" 2>/dev/null; then
        pass "Schema includes $field"
    else
        fail "Schema includes $field" "missing field"
    fi
done

# ── Storage location ─────────────────────────────────────────────────────────

if grep -q 'claude-octopus/runs' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "Uses ~/.claude-octopus/runs/ storage location"
else
    fail "Uses ~/.claude-octopus/runs/ storage location" "wrong location"
fi

if grep -q 'run-log.jsonl' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "Uses run-log.jsonl filename"
else
    fail "Uses run-log.jsonl filename" "wrong filename"
fi

# ── Cap enforcement ───────────────────────────────────────────────────────────

if grep -q '1000' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "Max entries cap is 1000"
else
    fail "Max entries cap is 1000" "missing cap"
fi

# ── Experiment logging ────────────────────────────────────────────────────────

if grep -q 'experiments/' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "Experiment logs stored in experiments/ subdirectory"
else
    fail "Experiment logs stored in experiments/ subdirectory" "missing"
fi

for field in iteration metric status description commit; do
    if grep -q "$field" "$RUN_STORE_LIB" 2>/dev/null; then
        pass "Experiment schema includes $field"
    else
        fail "Experiment schema includes $field" "missing"
    fi
done

# ── Kill switch ───────────────────────────────────────────────────────────────

if grep -q 'OCTO_RUN_STORE' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "Has OCTO_RUN_STORE kill switch"
else
    fail "Has OCTO_RUN_STORE kill switch" "missing"
fi

# ── Query filtering ──────────────────────────────────────────────────────────

if grep -q 'workflow_filter' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "query_runs supports workflow filtering"
else
    fail "query_runs supports workflow filtering" "missing"
fi

if grep -q 'date_filter' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "query_runs supports date filtering"
else
    fail "query_runs supports date filtering" "missing"
fi

# ── /octo:history command ─────────────────────────────────────────────────────

if [[ -f "$HISTORY_CMD" ]]; then
    pass "history.md command file exists"
else
    fail "history.md command file exists" "not found"
fi

if grep -q '^command: history' "$HISTORY_CMD" 2>/dev/null; then
    pass "history.md has command: history frontmatter"
else
    fail "history.md has command: history frontmatter" "missing"
fi

if grep -c 'commands/history.md' "$PLUGIN_JSON" >/dev/null 2>&1; then
    pass "history.md registered in plugin.json"
else
    fail "history.md registered in plugin.json" "not registered"
fi

if grep -q 'run-log.jsonl' "$HISTORY_CMD" 2>/dev/null; then
    pass "history.md references run-log.jsonl"
else
    fail "history.md references run-log.jsonl" "wrong file reference"
fi

if grep -qi 'stats\|statistics' "$HISTORY_CMD" 2>/dev/null; then
    pass "history.md supports stats mode"
else
    fail "history.md supports stats mode" "missing"
fi

if grep -qi 'experiment' "$HISTORY_CMD" 2>/dev/null; then
    pass "history.md supports experiment logs"
else
    fail "history.md supports experiment logs" "missing"
fi

# ── jq fallback ───────────────────────────────────────────────────────────────

if grep -q 'command -v jq' "$RUN_STORE_LIB" 2>/dev/null || grep -q 'jq.*2>/dev/null' "$RUN_STORE_LIB" 2>/dev/null; then
    pass "run-store.sh has jq fallback path"
else
    fail "run-store.sh has jq fallback path" "no fallback"
fi

# ── No attribution ────────────────────────────────────────────────────────────

for f in "$RUN_STORE_LIB" "$HISTORY_CMD"; do
    fname=$(basename "$f")
    if grep -qi 'autoresearch\|strategic-audit\|pi-autoresearch' "$f" 2>/dev/null; then
        fail "$fname has no attribution" "found prohibited reference"
    else
        pass "$fname has no attribution"
    fi
done

# ── Functional test: record and query ─────────────────────────────────────────

# ── Functional tests (via temp script to avoid quoting issues) ────────────────

TMPDIR_F=$(mktemp -d)
FUNC_SCRIPT="${TMPDIR_F}/func-test.sh"
cat > "$FUNC_SCRIPT" << FUNC_EOF
#!/usr/bin/env bash
export HOME="$TMPDIR_F"
log() { true; }
source "$RUN_STORE_LIB"
record_run "discover" "codex,gemini" "success" "5" "30000" '{"topic":"test"}'
record_run "review" "codex,claude" "success" "3" "45000" '{}'
STORE="\$HOME/.claude-octopus/runs/run-log.jsonl"
[[ -f "\$STORE" ]] && echo "PASS_FILE" || echo "FAIL_FILE"
echo "LINES=\$(wc -l < "\$STORE" 2>/dev/null | tr -d ' ')"
query_runs 10 "discover" 2>/dev/null | grep -q "discover" && echo "PASS_QUERY" || echo "FAIL_QUERY"
get_run_store_stats 2>/dev/null | grep -q "Total runs: 2" && echo "PASS_STATS" || echo "FAIL_STATS"
FUNC_EOF
chmod +x "$FUNC_SCRIPT"
FUNC_RESULT=$(bash "$FUNC_SCRIPT" 2>/dev/null) || true
rm -rf "$TMPDIR_F"

if echo "$FUNC_RESULT" | grep -q "PASS_FILE"; then
    pass "Functional: run-log.jsonl created on record"
else
    fail "Functional: run-log.jsonl created on record" "file not created"
fi

FUNC_LINES=$(echo "$FUNC_RESULT" | grep "LINES=" | sed 's/LINES=//')
if [[ "$FUNC_LINES" == "2" ]]; then
    pass "Functional: 2 entries recorded"
else
    fail "Functional: 2 entries recorded" "found ${FUNC_LINES:-0} lines"
fi

if echo "$FUNC_RESULT" | grep -q "PASS_QUERY"; then
    pass "Functional: query_runs filters by workflow"
else
    fail "Functional: query_runs filters by workflow" "filter failed"
fi

if echo "$FUNC_RESULT" | grep -q "PASS_STATS"; then
    pass "Functional: get_run_store_stats reports correct total"
else
    fail "Functional: get_run_store_stats reports correct total" "wrong total"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════"
echo "run-store: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
