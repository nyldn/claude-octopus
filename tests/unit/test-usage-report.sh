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
{"provider":"codex","model":"gpt-5.6-sol","skill":"flow-discover","est_tokens_in":10000,"est_tokens_out":2000,"quality":80}
{"provider":"codex","model":"gpt-5.6-terra","skill":"flow-develop","est_tokens_in":5000,"est_tokens_out":1000,"quality":70}
{"provider":"claude","model":"claude-sonnet-5","skill":"flow-discover","mcp_server":"perplexity-mcp","est_tokens_in":20000,"est_tokens_out":4000,"quality":90}
{"provider":"agy","skill":"flow-discover","est_tokens_in":8000,"est_tokens_out":3000,"quality":60}
{"provider":"cursor-agent","model":"composer-2.5","skill":"flow-review","est_tokens_in":1000000,"est_tokens_out":0,"quality":75}
{"provider":"cursor-agent-preview","model":"gpt-5.4","skill":"flow-review","est_tokens_in":1000000,"est_tokens_out":0,"quality":75}
{"provider":"grok","model":"default","skill":"flow-review","est_tokens_in":1000000,"est_tokens_out":0,"quality":75}
{"provider":"copilot","model":"gpt-5.4","skill":"flow-review","est_tokens_in":1000000,"est_tokens_out":0,"quality":75}
{"provider":"codex-astra","model":"gpt-6-astra","skill":"frontier-eval","est_tokens_in":300000,"est_tokens_out":100000,"quality":95}
EOF

cat > "$TMP_DIR/results/run1/summary.json" <<'EOF'
{"workflow":"council","roster":[{"provider":"codex","model":"gpt-5.5"},{"provider":"agy","model":"gemini-3-pro"}]}
EOF

report() {
    bash "$HELPER" --format json --usage-dir "$TMP_DIR/usage" --results-dir "$TMP_DIR/results"
}

cost_report() {
    bash "$HELPER" --view costs --format json --usage-dir "$TMP_DIR/usage" --results-dir "$TMP_DIR/results"
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
assert prov['codex']['est_cost_usd'] == 0.102, prov['codex']
assert prov['claude']['est_cost_usd'] == 0.08, prov['claude']
assert prov['agy']['est_cost_usd'] == 0
" "$out" 2>/dev/null; then
    test_pass
else
    test_fail "cost computation wrong: $out"
fi

test_case "distinguishes subscription Cursor Grok from standalone metered Grok"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
prov = {p['name']: p for p in d['byProvider']}
assert prov['cursor-agent']['est_cost_usd'] == 0, prov['cursor-agent']
assert prov['cursor-agent-preview']['est_cost_usd'] == 0, prov['cursor-agent-preview']
assert prov['grok']['est_cost_usd'] == 3.0, prov['grok']
assert prov['copilot']['est_cost_usd'] == 0, prov['copilot']
" "$out" 2>/dev/null; then
    test_pass
else
    test_fail "provider-aware Grok pricing wrong: $out"
fi

test_case "applies Astra long-context pricing to the complete request"
if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
prov = {p['name']: p for p in d['byProvider']}
assert prov['codex-astra']['est_cost_usd'] == 13.5, prov['codex-astra']
" "$out" 2>/dev/null; then
    test_pass
else
    test_fail "Astra long-context usage cost is wrong: $out"
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

test_case "costs view uses the same deterministic totals"
cost_out="$(cost_report)"
if python3 -c "
import json, sys
usage = json.loads(sys.argv[1])
costs = json.loads(sys.argv[2])
assert costs['view'] == 'costs'
assert usage['totals'] == costs['totals']
assert usage['byProvider'] == costs['byProvider']
" "$out" "$cost_out" 2>/dev/null; then
    test_pass
else
    test_fail "costs view diverged from usage calculator: $cost_out"
fi

test_case "table format prints provider rows"
table_out="$(bash "$HELPER" --format table --usage-dir "$TMP_DIR/usage" --results-dir "$TMP_DIR/results")"
if [[ "$table_out" == *"Provider Usage Breakdown"* && "$table_out" == *"codex"* && "$table_out" == *"TOTAL:"* ]]; then
    test_pass
else
    test_fail "table output missing expected rows: $table_out"
fi

test_case "costs table uses cost-focused headings"
cost_table_out="$(bash "$HELPER" --view costs --format table --usage-dir "$TMP_DIR/usage" --results-dir "$TMP_DIR/results")"
if [[ "$cost_table_out" == *"Provider Cost Breakdown"* && "$cost_table_out" == *"Workflow Cost Breakdown"* ]]; then
    test_pass
else
    test_fail "costs view headings are missing: $cost_table_out"
fi

test_case "csv export comes from the shared report"
csv_out="$(bash "$HELPER" --view costs --format csv --usage-dir "$TMP_DIR/usage" --results-dir "$TMP_DIR/results")"
if [[ "$csv_out" == group,name,queries,tokens_in,tokens_out,est_cost_usd$'\n'* ]] &&
   [[ "$csv_out" == *$'\ntotal,'* ]]; then
    test_pass
else
    test_fail "csv output is missing its shared schema or total row: $csv_out"
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

test_case "rejects unknown view"
if bash "$HELPER" --view forecast --usage-dir "$TMP_DIR/usage" 2>/dev/null; then
    test_fail "expected nonzero exit for --view forecast"
else
    test_pass
fi

test_case "shell cost help routes to the deterministic helper"
if grep -Fq 'usage-report.sh' "$PROJECT_ROOT/scripts/lib/usage-help.sh" &&
   grep -Fq -- '--view costs' "$PROJECT_ROOT/scripts/lib/usage-help.sh"; then
    test_pass
else
    test_fail "shell cost reporting must delegate to usage-report.sh --view costs"
fi

test_summary
