#!/usr/bin/env bash
# Monolith guard — prevents orchestrate.sh from growing past its extraction target
# Added in Wave 1 of the decomposition plan (v9.3.0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Monolith guard — prevents orchestrate.sh from growing past its extraction target"

ORCH="$SCRIPT_DIR/../../scripts/orchestrate.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── 1. Line count threshold ────────────────────────────────────────
MAX_LINES=22600
line_count=$(wc -l < "$ORCH" | tr -d ' ')

if [[ "$line_count" -le "$MAX_LINES" ]]; then
    pass "orchestrate.sh line count ($line_count <= $MAX_LINES)"
else
    fail "orchestrate.sh exceeds line limit" "$line_count lines (max $MAX_LINES)"
fi

# ── 2. Wave 1 lib files exist and are sourced ──────────────────────
for lib in utils.sh similarity.sh models.sh; do
    lib_path="$SCRIPT_DIR/../../scripts/lib/$lib"
    if [[ -f "$lib_path" ]]; then
        pass "lib/$lib exists"
    else
        fail "lib/$lib exists" "file not found"
    fi

    if grep -c "source.*lib/$lib" "$ORCH" >/dev/null 2>&1; then
        pass "lib/$lib sourced by orchestrate.sh"
    else
        fail "lib/$lib sourced by orchestrate.sh" "no source line found"
    fi
done

# ── 3. Extracted functions NOT duplicated in orchestrate.sh ─────────
for func in json_extract json_escape sanitize_external_content jaccard_similarity get_model_catalog; do
    count="$(grep -c "^${func}()" "$ORCH" 2>/dev/null)" || count=0
    if [[ "$count" -eq 0 ]]; then
        pass "$func not duplicated in orchestrate.sh"
    else
        fail "$func not duplicated" "found $count definition(s) still in orchestrate.sh"
    fi
done

# ── 4. Source guards present in lib files ───────────────────────────
for lib in utils.sh similarity.sh models.sh; do
    lib_path="$SCRIPT_DIR/../../scripts/lib/$lib"
    if grep -c '_LOADED.*return 0' "$lib_path" >/dev/null 2>&1; then
        pass "lib/$lib has source guard"
    else
        fail "lib/$lib has source guard" "no _LOADED guard found"
    fi
done
test_summary
