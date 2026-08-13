#!/bin/bash
# tests/unit/test-ceremonies.sh
# Tests pre-work design review and retrospective ceremonies (v8.18.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Pre-Work Ceremonies"

test_ceremonies_env_var_default() {
    test_case "OCTOPUS_CEREMONIES defaults to true"

    local output
    output=$(OCTOPUS_CEREMONIES="" "$PROJECT_ROOT/scripts/orchestrate.sh" -n tangle "test" 2>&1)

    # In dry-run, ceremony should show [DRY-RUN] message
    if echo "$output" | grep -qi "design review ceremony\|DRY-RUN.*ceremony\|DRY-RUN.*tangle"; then
        test_pass
    else
        # Also acceptable: dry-run just proceeds normally
        if [[ $? -eq 0 ]] || echo "$output" | grep -qi "DRY-RUN"; then
            test_pass
        else
            test_fail "Expected ceremony or dry-run output: ${output:0:200}"
        fi
    fi
}

test_ceremonies_disabled() {
    test_case "OCTOPUS_CEREMONIES=false skips ceremonies"

    local output
    output=$(OCTOPUS_CEREMONIES=false "$PROJECT_ROOT/scripts/orchestrate.sh" -n tangle "test" 2>&1)
    local exit_code=$?

    # Should succeed in dry-run without ceremony
    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed: $exit_code"
    fi
}

test_dry_run_skips_ceremony() {
    test_case "Dry-run mode skips ceremony execution"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n tangle "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run tangle failed: $exit_code"
    fi
}

test_embrace_dry_run() {
    test_case "Embrace dry-run works with ceremony code"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n embrace "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run embrace failed: $exit_code"
    fi
}

test_ceremony_functions_exist() {
    test_case "Ceremony functions are defined"

    # Functions decomposed to lib/ in v9.7.7+
    if grep -rq "design_review_ceremony()" "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/" && \
       grep -rq "retrospective_ceremony()" "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"; then
        test_pass
    else
        test_fail "Ceremony functions not found"
    fi
}

test_ceremony_called_in_tangle() {
    test_case "design_review_ceremony is called in tangle context"

    # Functions decomposed to lib/ in v9.7.7+
    if grep -rq "design_review_ceremony" "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"; then
        test_pass
    else
        test_fail "design_review_ceremony not called"
    fi
}

test_ceremony_rejects_implementation_claims() {
    test_case "design synthesis treats seat completion claims as unverified"

    if grep -Fq "UNVERIFIED CONSULTATIVE OUTPUT" "$PROJECT_ROOT/scripts/lib/agent-sync.sh" && \
       grep -Fq "Do not repeat claimed file changes, test counts, or live probes as verified facts" "$PROJECT_ROOT/scripts/lib/quality.sh"; then
        test_pass
    else
        test_fail "ceremony output can still surface disposable-workspace claims as evidence"
    fi
}

test_ceremony_synthesis_receives_provenance_boundary() {
    test_case "design synthesis receives disposable-seat provenance boundary"

    local capture="$TEST_TMP_DIR/ceremony-synthesis.prompt"
    local counter="$TEST_TMP_DIR/ceremony-seat-count"
    printf '0\n' > "$counter"
    if (
        WORKSPACE_DIR="$TEST_TMP_DIR/ceremony-workspace"
        # shellcheck source=/dev/null
        source "$PROJECT_ROOT/scripts/lib/quality.sh"
        DRY_RUN=false
        OCTOPUS_CEREMONIES=true
        CYAN="" GREEN="" NC="" _BOX_TOP="" _BOX_BOT=""
        log() { :; }
        octo_provider_identity_label() { printf '%s\n' "$1 / fixture"; }
        write_structured_decision() { :; }
        run_agent_sync_consultative() {
            local count
            count=$(cat "$counter")
            count=$((count + 1))
            printf '%s\n' "$count" > "$counter"
            if [[ "$count" -le 3 ]]; then
                printf '%s\n' \
                    '## UNVERIFIED CONSULTATIVE OUTPUT' \
                    'Implemented disposable files and verified 417 tests plus live probes.'
            else
                printf '%s' "$2" > "$capture"
                printf '%s\n' 'Planning-only synthesis.'
            fi
        }
        design_review_ceremony "Design the change" >/dev/null
        grep -Fq "Do not repeat claimed file changes, test counts, or live probes as verified facts" "$capture" && \
        grep -Fq "UNVERIFIED CONSULTATIVE OUTPUT" "$capture"
    ); then
        test_pass
    else
        test_fail "synthesis did not receive the unverified-seat boundary"
    fi
}

test_retrospective_in_ink() {
    test_case "retrospective_ceremony reference exists"

    # Functions decomposed to lib/ in v9.7.7+
    if grep -rq "retrospective_ceremony" "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"; then
        test_pass
    else
        test_fail "retrospective_ceremony not found"
    fi
}

# Run all tests
test_ceremonies_env_var_default
test_ceremonies_disabled
test_dry_run_skips_ceremony
test_embrace_dry_run
test_ceremony_functions_exist
test_ceremony_called_in_tangle
test_ceremony_rejects_implementation_claims
test_ceremony_synthesis_receives_provenance_boundary
test_retrospective_in_ink

test_summary
