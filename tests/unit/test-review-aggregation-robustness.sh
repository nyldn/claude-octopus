#!/usr/bin/env bash
# Tests for robust review findings extraction / aggregation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "review aggregation robustness"

REVIEW_SH="$PROJECT_ROOT/scripts/lib/review.sh"
TMP_MD="$(mktemp "${TMPDIR:-/tmp}/octo-review-md.XXXXXX")"
trap 'rm -f "$TMP_MD"' EXIT

cat > "$TMP_MD" <<'EOF'
# Agent: claude-sonnet
## Output
```
The provider echoed prompt text first.
Example: {"findings": []}
Now the actual answer:
{"findings":[{"file":"api/terminal.js","line":12,"severity":"normal","category":"security","title":"Broken regex","detail":"The regex is wrong","confidence":0.9}]}
```

## Status: SUCCESS
EOF

test_case "extractor helper is present"
if grep -q "review_extract_findings_array" "$REVIEW_SH"; then test_pass; else test_fail "missing helper"; fi

test_case "round1 snapshot is written"
if grep -q "review-round1-findings" "$REVIEW_SH"; then test_pass; else test_fail "missing round1 snapshot"; fi

test_case "extractor recovers last JSON findings object"
source "$REVIEW_SH" >/dev/null 2>&1 || true
if out=$(review_extract_findings_array "$TMP_MD" 2>/dev/null); then
    if count=$(printf '%s' "$out" | jq 'length' 2>/dev/null) && title=$(printf '%s' "$out" | jq -r '.[0].title' 2>/dev/null); then
        if [[ "$count" == "1" && "$title" == "Broken regex" ]]; then
            test_pass
        else
            test_fail "unexpected extraction output: $out"
        fi
    else
        test_fail "extractor returned invalid JSON: $out"
    fi
else
    test_fail "extractor failed to recover findings"
fi

test_case "review agents run without absolute timeout"
if grep -q "export TIMEOUT=0" "$REVIEW_SH" && grep -q "review_run_agent_sync_progress" "$REVIEW_SH"; then
    test_pass
else
    test_fail "review no-wall-timeout wiring missing"
fi

test_case "old review timeout envs are removed"
if grep -q "OCTOPUS_REVIEW_VERIFIER_TIMEOUT\|OCTOPUS_REVIEW_SYNTHESIS_TIMEOUT\|OCTOPUS_REVIEW_TIMEOUT" "$REVIEW_SH"; then
    test_fail "old review timeout env still present"
else
    test_pass
fi

test_case "review uses stall watchdog"
if grep -q "OCTOPUS_REVIEW_STALL_WINDOW" "$REVIEW_SH"; then test_pass; else test_fail "missing review stall window"; fi

test_case "invalid synthesis has local fallback"
if grep -q "synthesis returned invalid findings JSON" "$REVIEW_SH"; then test_pass; else test_fail "missing local fallback"; fi

test_summary
