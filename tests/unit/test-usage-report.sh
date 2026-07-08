#!/usr/bin/env bash
# Tests for the usage-report helper (/octo:usage backend).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Usage report"

HELPER="$PROJECT_ROOT/scripts/helpers/usage-report.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/usage" "$TMP_DIR/results/run1"

cat > "$TMP_DIR/usage/subagent-usage.jsonl" <<'EOF'
{"provider":"codex","skill":"flow-discover","est_tokens_in":10000,"est_tokens_out":2000,"quality":80}
{"provider":"codex","skill":"flow-develop","est_tokens_in":5000,"est_tokens_out":1000,"quality":70}
{"provider":"claude","skill":"flow-discover","mcp_server":"perplexity-mcp","est_tokens_in":20000,"est_tokens_out":4000,"quality":90}
{"provider":"agy","skill":"flow-discover","est_tokens_in":8000,"est_tokens_out":3000,"quality":60}
EOF

cat > "$TMP_DIR/results/run1/summary.json" <<'EOF'
{"workflow":"council","roster":[{"provider":"codex","model":"gpt-5.5"},{"provider":"agy","model":"gemini-3-pro"}]}
EOF

report() {
    bash "$HELPER" --format json --usage-dir "$TMP_DIR/usage" --results-dir "$TMP_DIR/results"
}

test_case "json output matches claude-code/usage-v1 schema shape"
out="$(report)"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['schema'] == 'claude-code/usage-v1'
assert set(['totals','byProvider','bySkill','byMcpServer']) <= set(d)
" "$out" 2>/dev/null; then
    test_pass
else
    test_fail "schema shape mismatch: $out"
fi

test_case "aggregates per provider including results-dir roster queries"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
prov = {p['name']: p for p in d['byProvider']}
assert prov['codex']['queries'] == 3, prov['codex']       # 2 jsonl + 1 roster
assert prov['codex']['tokens_in'] == 15000
assert prov['codex']['tokens_out'] == 3000
assert prov['agy']['queries'] == 2                        # 1 jsonl + 1 roster
" "$out" 2>/dev/null; then
    test_pass
else
    test_fail "per-provider aggregation wrong: $out"
fi

test_case "computes nonzero cost for billed providers and zero for included"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
prov = {p['name']: p for p in d['byProvider']}
assert prov['codex']['est_cost_usd'] > 0
assert prov['agy']['est_cost_usd'] == 0
" "$out" 2>/dev/null; then
    test_pass
else
    test_fail "cost computation wrong: $out"
fi

test_case "groups by skill and by mcp server"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
skills = {s['name'] for s in d['bySkill']}
assert 'flow-discover' in skills and 'flow-develop' in skills
mcps = {m['name']: m for m in d['byMcpServer']}
assert mcps['perplexity-mcp']['queries'] == 1
" "$out" 2>/dev/null; then
    test_pass
else
    test_fail "skill/mcp grouping wrong: $out"
fi

test_case "table format prints provider rows"
table_out="$(bash "$HELPER" --format table --usage-dir "$TMP_DIR/usage" --results-dir "$TMP_DIR/results")"
if [[ "$table_out" == *"Provider Usage Breakdown"* && "$table_out" == *"codex"* && "$table_out" == *"TOTAL:"* ]]; then
    test_pass
else
    test_fail "table output missing expected rows: $table_out"
fi

test_case "empty usage dir reports no records instead of fabricating"
empty_dir="$TMP_DIR/empty"
mkdir -p "$empty_dir/usage" "$empty_dir/results"
out2="$(bash "$HELPER" --format table --usage-dir "$empty_dir/usage" --results-dir "$empty_dir/results")"
if [[ "$out2" == *"No usage records found"* ]]; then
    test_pass
else
    test_fail "expected empty-data notice, got: $out2"
fi

test_case "rejects unknown format"
if bash "$HELPER" --format xml --usage-dir "$TMP_DIR/usage" 2>/dev/null; then
    test_fail "expected nonzero exit for --format xml"
else
    test_pass
fi

test_summary
