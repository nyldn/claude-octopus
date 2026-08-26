#!/usr/bin/env bash
# Regression checks for probe result classification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Probe result classification"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/progressive.sh"

RESULT_DIR="$(mktemp -d)"
trap 'rm -rf "$RESULT_DIR"' EXIT
export WORKSPACE_DIR="$RESULT_DIR/workspace"
export OCTOPUS_RUN_ID="probe-classification-contract"
mkdir -p "$WORKSPACE_DIR"

header_only="$RESULT_DIR/codex-probe-123-0.md"
cat > "$header_only" <<'EOF'
# Agent: codex
# Task ID: probe-123-0
# Role: researcher
# Phase: probe
# Prompt: Validate Writer claims.
# Started: Tue Jun  2 00:44:17 BST 2026

## Output
```
EOF

partial_body="$RESULT_DIR/gemini-probe-123-1.md"
cat > "$partial_body" <<'EOF'
# Agent: gemini
# Task ID: probe-123-1

## Output
```
Writer AI Studio appears to provide tool calling and deployment, but this answer was interrupted before a status marker was written.
EOF

success_body="$RESULT_DIR/claude-sonnet-probe-123-2.md"
cat > "$success_body" <<'EOF'
# Agent: claude-sonnet
# Task ID: probe-123-2

## Output
```
The hybrid threshold remains valid.
```

## Status: SUCCESS
EOF

test_case "header-only result is failed, not partial"
classification="$(probe_result_file_status "$header_only")"
if [[ "$classification" == "failed:empty-output" ]]; then
    test_pass
else
    test_fail "expected failed:empty-output for header-only file, got: ${classification:-<empty>}"
fi

test_case "body without status marker is degraded"
classification="$(probe_result_file_status "$partial_body")"
if [[ "$classification" == "degraded:missing-status" ]]; then
    test_pass
else
    test_fail "expected degraded:missing-status for answer body without marker, got: ${classification:-<empty>}"
fi

test_case "success marker remains success"
classification="$(probe_result_file_status "$success_body")"
if [[ "$classification" == "success:" ]]; then
    test_pass
else
    test_fail "expected success for status marker, got: ${classification:-<empty>}"
fi

typed_timeout="$RESULT_DIR/codex-probe-typed-timeout.md"
cp "$success_body" "$typed_timeout"
run_contract_transition typed-timeout planned >/dev/null
run_contract_transition typed-timeout starting >/dev/null
run_contract_transition typed-timeout authenticated >/dev/null
run_contract_transition typed-timeout running >/dev/null
run_contract_transition typed-timeout timeout output_file="$typed_timeout" \
    reason="Timed out before completion" >/dev/null
test_case "typed timeout cannot enter synthesis despite a legacy success marker"
classification="$(probe_result_file_status "$typed_timeout")"
if [[ "$classification" == "failed:contract-ineligible" ]] && \
   ! probe_result_file_is_usable "$typed_timeout"; then
    test_pass
else
    test_fail "typed timeout remained synthesis eligible: $classification"
fi

typed_success="$RESULT_DIR/codex-probe-typed-success.md"
cp "$success_body" "$typed_success"
run_contract_transition typed-success planned >/dev/null
run_contract_transition typed-success starting >/dev/null
run_contract_transition typed-success authenticated >/dev/null
run_contract_transition typed-success running >/dev/null
run_contract_transition typed-success output_received output_file="$typed_success" >/dev/null
run_contract_transition typed-success validated contribution=eligible >/dev/null
run_contract_transition typed-success contributed contribution=eligible >/dev/null
test_case "typed contribution remains synthesis eligible"
if [[ "$(probe_result_file_status "$typed_success")" == "success:" ]] && \
   probe_result_file_is_usable "$typed_success"; then
    test_pass
else
    test_fail "typed contributed artifact was rejected"
fi

test_case "partial synthesis skips header-only artifacts"
RESULTS_DIR="$RESULT_DIR/progressive"
mkdir -p "$RESULTS_DIR"
cp "$header_only" "$RESULTS_DIR/codex-probe-999-0.md"
cp "$success_body" "$RESULTS_DIR/gemini-probe-999-1.md"
partial="$(synthesize_probe_results_partial 999 "prompt" 1)"
if [[ "$partial" == *"Partial Synthesis (1/1 results)"* && \
      "$partial" == *"The hybrid threshold remains valid."* && \
      "$partial" != *"Validate Writer claims"* ]]; then
    test_pass
else
    test_fail "expected partial synthesis to include only usable output, got: ${partial:-<empty>}"
fi

test_case "contract evaluation errors are distinct and fail closed"
ledger="$(octo_run_contract_ledger_path)"
cp "$ledger" "$ledger.before-malformed"
printf '{malformed\n' > "$ledger"
classification="$(probe_result_file_status "$typed_success")"
evaluation_usable=true
probe_result_file_is_usable "$typed_success" || evaluation_usable=false
mv "$ledger.before-malformed" "$ledger"
if [[ "$classification" == "failed:contract-evaluation-error" ]] &&
   [[ "$evaluation_usable" == false ]]; then
    test_pass
else
    test_fail "expected distinct fail-closed evaluation error, got ${classification:-empty}"
fi

test_summary
