#!/usr/bin/env bash
# Regression checks for compact probe synthesis fallback.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HEURISTICS="$PROJECT_ROOT/scripts/lib/heuristics.sh"
RESEARCH_EVIDENCE="$PROJECT_ROOT/scripts/lib/research-evidence.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "probe compact synthesis fallback"

test_case "heuristics.sh has valid bash syntax"
if bash -n "$HEURISTICS" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in heuristics.sh"
fi

# shellcheck source=/dev/null
source "$HEURISTICS"
# shellcheck source=/dev/null
source "$RESEARCH_EVIDENCE"

TEST_ROOT="$(mktemp -d)"
HOME="$TEST_ROOT/home"
RESULTS_DIR="$TEST_ROOT/results"
LOGS_DIR="$TEST_ROOT/logs"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$HOME" "$RESULTS_DIR" "$LOGS_DIR"

log() { :; }
enhanced_error() { return 1; }
get_cache_key() { echo "cache-key"; }
save_to_cache() { :; }
guard_output() { :; }
run_agent_sync() { return 1; }

make_payload() {
    local token="$1"
    local count="$2"
    local i
    for i in $(seq 1 "$count"); do
        printf '%s line %04d: detailed probe finding with src/app/page.tsx and concrete notes\n' "$token" "$i"
    done
}

task_group="compact"
success_a="$RESULTS_DIR/codex-probe-${task_group}-0.md"
success_b="$RESULTS_DIR/claude-sonnet-probe-${task_group}-1.md"
failed="$RESULTS_DIR/gemini-probe-${task_group}-2.md"

{
    echo "# Agent: codex"
    echo "# Phase: probe"
    echo ""
    echo "## Output"
    make_payload "CODEX_RAW" 180
    echo "RAW_TAIL_SHOULD_NOT_APPEAR"
    echo ""
    echo "## Status: SUCCESS"
} > "$success_a"

{
    echo "# Agent: claude-sonnet"
    echo "# Phase: probe"
    echo ""
    echo "## Output"
    echo "[Auto-synthesis failed - raw findings below]"
    make_payload "SONNET_RAW" 60
    echo ""
    echo "## Status: SUCCESS"
} > "$success_b"

{
    echo "# Agent: gemini"
    echo "# Phase: probe"
    echo "## Status: FAILED (exit code: 1)"
} > "$failed"

OCTOPUS_PROBE_SYNTHESIS_FILE_CHARS=900
OCTOPUS_PROBE_SYNTHESIS_CONTEXT_CHARS=4200

test_case "compact probe context is bounded and sanitizes failed synthesis markers"
context="$(build_probe_synthesis_context "$task_group")"
if [[ ${#context} -le 5200 ]] && \
   [[ "$context" == *"## Source: codex-probe-${task_group}-0.md"* ]] && \
   [[ "$context" == *"## Source: claude-sonnet-probe-${task_group}-1.md"* ]] && \
   [[ "$context" == *"truncated by probe synthesis context"* ]] && \
   [[ "$context" == *"Prior auto-synthesis failed; raw fallback omitted"* ]] && \
   [[ "$context" != *"[Auto-synthesis failed - raw findings below]"* ]] && \
   [[ "$context" != *"RAW_TAIL_SHOULD_NOT_APPEAR"* ]] && \
   [[ "$context" != *"gemini-probe-${task_group}-2.md"* ]]; then
    test_pass
else
    test_fail "compact probe context did not stay bounded/sanitized"
fi

test_case "synthesis provider failure writes compact fallback, not raw dump"
if synthesize_probe_results "$task_group" "Audit local templates" 2 >/dev/null 2>&1; then
    synthesis_file="$RESULTS_DIR/probe-synthesis-${task_group}.md"
    synthesis_content="$(cat "$synthesis_file")"
    if [[ "$synthesis_content" == *"Automated probe synthesis unavailable."* ]] && \
       [[ "$synthesis_content" == *"Raw provider artifacts remain available"* ]] && \
       [[ "$synthesis_content" != *"[Auto-synthesis failed - raw findings below]"* ]] && \
       [[ "$synthesis_content" != *"CODEX_RAW"* ]] && \
       [[ "$synthesis_content" != *"RAW_TAIL_SHOULD_NOT_APPEAR"* ]]; then
        test_pass
    else
        test_fail "probe fallback propagated raw artifacts"
    fi
else
    test_fail "synthesize_probe_results returned non-zero in compact fallback scenario"
fi

test_case "durable fallback passes verification without embedding source excerpts"
OCTOPUS_RESEARCH_EVIDENCE=true
OCTOPUS_RESEARCH_RUN_ID="compact-fallback"
OCTOPUS_RESEARCH_RESUME=false
research_run_begin "$task_group" $'Audit 64 templates\nand quote "example text"' "quick"
research_collect_sources "$task_group"
if synthesize_probe_results "$task_group" $'Audit 64 templates\nand quote "example text"' 2 >/dev/null 2>&1; then
    durable_synthesis="$RESULTS_DIR/probe-synthesis-${task_group}.md"
    durable_content=$(<"$durable_synthesis")
    if [[ "$durable_content" == *"Automated probe synthesis unavailable."* ]] \
       && [[ "$durable_content" == *"Raw provider artifacts remain available"* ]] \
       && [[ "$durable_content" != *"CODEX_RAW"* ]] \
       && jq -e '.status == "passed" and .failures == 0' \
            "$RESEARCH_RUN_DIR/verification.json" >/dev/null; then
        test_pass
    else
        test_fail "durable compact fallback did not pass mechanical verification"
    fi
else
    test_fail "durable compact fallback rejected its own generated metadata"
fi
unset OCTOPUS_RESEARCH_EVIDENCE OCTOPUS_RESEARCH_RUN_ID OCTOPUS_RESEARCH_RESUME
unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY
unset RESEARCH_PROVIDER_RESULTS_DIR

test_case "resumed synthesis reads the recorded provider results directory"
recorded_results="$TEST_ROOT/recorded-results"
resumed_results="$TEST_ROOT/resumed-results"
mkdir -p "$recorded_results" "$resumed_results"
cp "$success_a" "$recorded_results/codex-probe-resumed-0.md"
cp "$success_b" "$recorded_results/claude-sonnet-probe-resumed-1.md"
RESULTS_DIR="$resumed_results"
RESEARCH_PROVIDER_RESULTS_DIR="$recorded_results"
if synthesize_probe_results "resumed" "Resume the prior research" 2 >/dev/null 2>&1; then
    resumed_synthesis="$RESULTS_DIR/probe-synthesis-resumed.md"
    resumed_content=$(<"$resumed_synthesis")
    if [[ "$resumed_content" == *"Usable research threads included: 2"* ]] \
       && [[ "$resumed_content" != *"Usable research threads included: 0"* ]]; then
        test_pass
    else
        test_fail "resumed synthesis omitted artifacts from the recorded provider directory"
    fi
else
    test_fail "resumed synthesis did not find the recorded provider artifacts"
fi
unset RESEARCH_PROVIDER_RESULTS_DIR

test_summary
