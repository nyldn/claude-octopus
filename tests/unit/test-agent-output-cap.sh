#!/usr/bin/env bash
# Static assertions for the run_agent_sync output cap + partial-writes probe.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_SYNC="$PROJECT_ROOT/scripts/lib/agent-sync.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Agent Output Cap & Partial-Writes Diagnostics"

test_output_cap_default() {
    test_case "output cap defaults to 256 KiB (OCTOPUS_AGENT_MAX_OUTPUT_BYTES)"
    if grep -q 'OCTOPUS_AGENT_MAX_OUTPUT_BYTES:-262144' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "OCTOPUS_AGENT_MAX_OUTPUT_BYTES:-262144 not found"
    fi
}

test_output_cap_disable_sentinel() {
    test_case "cap honours 0 as disable sentinel"
    if grep -q '_max_bytes -gt 0' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "missing '\$_max_bytes -gt 0' guard"
    fi
}

test_output_cap_bash3_compat() {
    test_case "substring extraction uses bash-3.x-compatible positive offset"
    if grep -qE 'output:\$_tail_start:\$_tail_bytes' "$AGENT_SYNC" \
       && ! grep -qE 'output: -' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "must use positive-offset \${output:start:len}, not negative \${output: -n}"
    fi
}

test_output_cap_tail_bias() {
    test_case "truncation preserves tail (deliverable summary)"
    if grep -qE '_tail_start=\$\(\( _orig_bytes - _tail_bytes \)\)' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "tail-bias start calculation not found"
    fi
}

test_output_cap_banner_measured() {
    test_case "banner byte-length is measured (not assumed) to bound final output"
    if grep -q '_banner_bytes=\${#_banner}' "$AGENT_SYNC" \
       && grep -q '_budget=\$((_max_bytes - _banner_bytes))' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "cap math must use measured banner length, not hardcoded reserve"
    fi
}

test_output_cap_banner() {
    test_case "truncation banner is emitted"
    if grep -q 'OUTPUT TRUNCATED' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "OUTPUT TRUNCATED marker missing"
    fi
}

test_partial_writes_exit_gate() {
    test_case "partial-writes probe gated on 124/143 (timeout exit codes)"
    if grep -qE 'exit_code -eq 124 \|\| \$exit_code -eq 143|exit_code -eq 124 \|\| exit_code -eq 143' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "timeout exit-code guard missing"
    fi
}

test_partial_writes_scope() {
    test_case "partial-writes probe scoped to dispatch CWD + start time"
    if grep -q 'find "\$_dispatch_cwd" -maxdepth' "$AGENT_SYNC" \
       && grep -q '\-newermt "@\${_dispatch_start}"' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "find with -maxdepth + -newermt@dispatch_start not found"
    fi
}

test_partial_writes_depth_bounded() {
    test_case "partial-writes probe bounds traversal (OCTOPUS_PARTIAL_WRITES_DEPTH)"
    if grep -q 'OCTOPUS_PARTIAL_WRITES_DEPTH:-4' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "maxdepth default not configurable via OCTOPUS_PARTIAL_WRITES_DEPTH"
    fi
}

test_partial_writes_noise_exclusions() {
    test_case "partial-writes probe excludes .git and node_modules"
    if grep -q "not -path '\*/\.git/\*'" "$AGENT_SYNC" \
       && grep -q "not -path '\*/node_modules/\*'" "$AGENT_SYNC"; then
        test_pass
    else
        test_fail ".git / node_modules -not -path filters missing"
    fi
}

test_partial_writes_bsd_skip() {
    test_case "probe feature-detects -newermt so BSD find silently skips"
    if grep -q 'find /dev/null -newermt "@0"' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "-newermt feature-detect gate missing"
    fi
}

test_partial_writes_single_pass_scan() {
    test_case "probe uses while-read loop (no find|head SIGPIPE under pipefail)"
    if grep -q 'while IFS= read -r _line' "$AGENT_SYNC" \
       && ! grep -qE 'find .* -newermt .* \| head' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "find|head pipeline still present or while-read loop missing"
    fi
}

test_partial_writes_uses_log_helper() {
    test_case "probe routes diagnostics through log helper (no raw echo to stderr)"
    if grep -q 'log INFO "Partial writes detected' "$AGENT_SYNC" \
       && ! grep -q 'echo "ℹ️  Partial writes detected' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "raw echo still used for partial-writes diagnostic"
    fi
}

test_partial_writes_date_bsd_fallback() {
    test_case "timestamp formatting falls back to BSD date -r"
    if grep -q 'date -r "\${_dispatch_start}"' "$AGENT_SYNC"; then
        test_pass
    else
        test_fail "BSD date -r fallback missing"
    fi
}

test_output_cap_default
test_output_cap_disable_sentinel
test_output_cap_bash3_compat
test_output_cap_tail_bias
test_output_cap_banner_measured
test_output_cap_banner
test_partial_writes_exit_gate
test_partial_writes_scope
test_partial_writes_depth_bounded
test_partial_writes_noise_exclusions
test_partial_writes_bsd_skip
test_partial_writes_single_pass_scan
test_partial_writes_uses_log_helper
test_partial_writes_date_bsd_fallback

test_summary
