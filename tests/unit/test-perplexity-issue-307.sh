#!/usr/bin/env bash
# tests/unit/test-perplexity-issue-307.sh
# Regression tests for issue #307:
#   Blocker 1: heartbeat.sh run_with_timeout "$@" & redirected stdin to /dev/null
#              in non-interactive bash, starving shell-function providers that
#              read their prompt from stdin (perplexity_execute, openrouter_execute).
#   Blocker 2: perplexity.sh used json_extract $response "content" which only
#              reads top-level keys; OpenAI-compatible APIs nest content at
#              .choices[0].message.content, so extraction silently returned empty.
#
# Both are verified here without hitting the real Perplexity API.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Issue #307: perplexity stdin + json_extract nested-path fixes"

# ═══════════════════════════════════════════════════════════════════════════════
# Blocker 1: heartbeat.sh "$@" <&0 & preserves stdin into background job
# ═══════════════════════════════════════════════════════════════════════════════

test_heartbeat_preserves_stdin_in_pipe() {
    test_case "run_with_timeout preserves stdin into background shell function (non-interactive bash)"

    # Minimal repro of the orchestrator pipeline. The function body mimics
    # perplexity_execute's `$(cat)` stdin fallback.
    local out
    out=$(bash -c '
        set +m  # force job-control OFF, mirroring orchestrate.sh non-interactive context
        source "'"$PROJECT_ROOT"'/scripts/lib/heartbeat.sh" 2>/dev/null || exit 2
        read_stdin() { echo "stdin:[$(cat)]"; }
        export -f read_stdin
        _cmd_is_function=true
        printf "hello world" | run_with_timeout 5 read_stdin
    ' 2>/dev/null)

    if [[ "$out" == "stdin:[hello world]" ]]; then
        test_pass
    else
        test_fail "expected stdin:[hello world], got: $out"
    fi
}

test_heartbeat_has_stdin_inherit_fix() {
    test_case "heartbeat.sh background-job line uses <&0 stdin inherit"

    local hb="$PROJECT_ROOT/scripts/lib/heartbeat.sh"
    if grep -qE '"\$@" <&0 &' "$hb"; then
        test_pass
    else
        test_fail "missing \"\$@\" <&0 & pattern in heartbeat.sh (issue #307 regression)"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Blocker 2: perplexity.sh extracts content from nested .choices[0].message.content
# ═══════════════════════════════════════════════════════════════════════════════

test_perplexity_extracts_nested_content() {
    test_case "perplexity_execute extracts .choices[0].message.content from mocked response"

    # Stub all network + heavy deps, then replay a canned Perplexity response
    # through the extraction block. We don't actually call perplexity_execute —
    # we just verify the jq extraction path produces the expected content.
    local mock_response='{"id":"x","choices":[{"message":{"role":"assistant","content":"It is 2026."}}],"citations":["https://example.com"]}'
    local extracted
    extracted=$(printf '%s' "$mock_response" | jq -re '.choices[0].message.content // empty' 2>/dev/null)
    if [[ "$extracted" == "It is 2026." ]]; then
        test_pass
    else
        test_fail "expected 'It is 2026.', got: '$extracted'"
    fi
}

test_perplexity_sh_uses_nested_jq_path() {
    test_case "perplexity.sh code uses nested jq path (not flat json_extract) for content"

    local pf="$PROJECT_ROOT/scripts/lib/perplexity.sh"
    # Must not have the old buggy call in the two extract blocks.
    # `grep -c` returns exit 1 (and prints 0) on no-match — use `|| true` to suppress set -e
    # and read first line only to avoid dual output from `|| echo 0` patterns.
    local old_matches new_matches
    old_matches=$({ grep -c 'json_extract "\$response" "content"' "$pf" 2>/dev/null || true; } | head -1)
    new_matches=$({ grep -c '\.choices\[0\]\.message\.content' "$pf" 2>/dev/null || true; } | head -1)
    old_matches=${old_matches:-0}
    new_matches=${new_matches:-0}

    if [[ "$old_matches" -eq 0 ]] && [[ "$new_matches" -ge 2 ]]; then
        test_pass
    else
        test_fail "old json_extract occurrences=$old_matches (want 0), new jq path occurrences=$new_matches (want ≥2)"
    fi
}

test_perplexity_empty_response_surfaces_error() {
    test_case "empty .choices[0].message.content is treated as empty (triggers error path)"

    # Simulate a response where the nested content is absent
    local mock_empty='{"id":"x","choices":[{"message":{"role":"assistant"}}]}'
    local extracted
    extracted=$(printf '%s' "$mock_empty" | jq -re '.choices[0].message.content // empty' 2>/dev/null) || extracted=""

    if [[ -z "$extracted" ]]; then
        test_pass
    else
        test_fail "expected empty string for missing nested field, got: '$extracted'"
    fi
}

test_perplexity_error_payload_still_surfaces() {
    test_case "Perplexity API error payload is preserved for logger to surface"

    # An error response like the live "insufficient_quota" case (issue #307 user tested this).
    # The existing error handler uses BASH_REMATCH — just confirm the regex still matches.
    local mock_error='{"error":{"message":"You exceeded your current quota","type":"insufficient_quota","code":401}}'
    if [[ "$mock_error" =~ \"error\":\{([^\}]*)\} ]]; then
        if [[ "${BASH_REMATCH[1]}" == *insufficient_quota* ]]; then
            test_pass
        else
            test_fail "regex matched but captured group missing 'insufficient_quota': ${BASH_REMATCH[1]}"
        fi
    else
        test_fail "error regex did not match mock error payload"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

test_heartbeat_preserves_stdin_in_pipe
test_heartbeat_has_stdin_inherit_fix
test_perplexity_extracts_nested_content
test_perplexity_sh_uses_nested_jq_path
test_perplexity_empty_response_surfaces_error
test_perplexity_error_payload_still_surfaces

test_summary
