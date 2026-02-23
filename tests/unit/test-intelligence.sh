#!/bin/bash
# tests/unit/test-intelligence.sh
# Tests for scripts/lib/intelligence.sh + scripts/lib/personas.sh
# Covers: JSON wrappers, Provider Intelligence, Cost Routing,
#         Capability Matching, Quorum Consensus, File Path Validation,
#         Baseline Telemetry (v8.20.1), Anti-Drift Checkpoints (v8.21.0),
#         Persona Packs (v8.21.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

# Set up environment for intelligence.sh
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
export PLUGIN_DIR="$PROJECT_ROOT"

# Source the library under test
source "$PROJECT_ROOT/scripts/lib/intelligence.sh"

test_suite "Intelligence Library (v8.20.0 — v8.21.0)"

# ═══════════════════════════════════════════════════════════════════════════════
# JSON Wrapper Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_db_set_get() {
    test_case "octo_db_set and octo_db_get round-trip"

    local test_file="$TEST_TMP_DIR/test-db.json"
    rm -f "$test_file"

    octo_db_set "$test_file" "key1" "value1"
    local result
    result=$(octo_db_get "$test_file" "key1" "default")

    if assert_equals "value1" "$result" "Should read back written value"; then
        test_pass
    fi
}

test_db_get_default() {
    test_case "octo_db_get returns default for missing key"

    local test_file="$TEST_TMP_DIR/nonexistent.json"
    rm -f "$test_file"

    local result
    result=$(octo_db_get "$test_file" "missing_key" "fallback")

    if assert_equals "fallback" "$result" "Should return default value"; then
        test_pass
    fi
}

test_db_append_cap() {
    test_case "octo_db_append enforces max entries cap"

    local test_file="$TEST_TMP_DIR/test-append.jsonl"
    rm -f "$test_file"

    # Write 10 entries with cap of 5
    for i in $(seq 1 10); do
        octo_db_append "$test_file" "{\"n\":$i}" 5
    done

    local count
    count=$(wc -l < "$test_file" | tr -d ' ')

    if assert_equals "5" "$count" "Should cap at 5 entries"; then
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Provider Intelligence Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_record_outcome() {
    test_case "record_outcome writes telemetry entry"

    export OCTOPUS_PROVIDER_INTELLIGENCE="shadow"
    local telemetry_file="$WORKSPACE_DIR/.octo/provider-telemetry.jsonl"
    rm -f "$telemetry_file"
    mkdir -p "$(dirname "$telemetry_file")"

    record_outcome "codex" "backend-architect" "api-design" "tangle" "success" "1500"

    if [[ -f "$telemetry_file" ]]; then
        local content
        content=$(cat "$telemetry_file")
        if assert_contains "$content" '"provider":"codex"' "Should contain provider" && \
           assert_contains "$content" '"outcome":"success"' "Should contain outcome"; then
            test_pass
        fi
    else
        test_fail "Telemetry file not created"
    fi
}

test_record_outcome_off() {
    test_case "record_outcome is no-op when intelligence is off"

    export OCTOPUS_PROVIDER_INTELLIGENCE="off"
    local telemetry_file="$WORKSPACE_DIR/.octo/provider-telemetry-off.jsonl"
    rm -f "$telemetry_file"

    # Override the WORKSPACE_DIR temporarily
    local orig_ws="$WORKSPACE_DIR"
    WORKSPACE_DIR="$TEST_TMP_DIR/workspace-off"
    mkdir -p "$WORKSPACE_DIR/.octo"
    local off_telemetry="$WORKSPACE_DIR/.octo/provider-telemetry.jsonl"
    rm -f "$off_telemetry"

    record_outcome "codex" "test" "test" "test" "success" "100"
    WORKSPACE_DIR="$orig_ws"

    if [[ ! -f "$off_telemetry" ]]; then
        test_pass
    else
        test_fail "Should not write telemetry when off"
    fi
}

test_provider_score_default() {
    test_case "get_provider_score returns 0.70 default with no data"

    local orig_ws="$WORKSPACE_DIR"
    WORKSPACE_DIR="$TEST_TMP_DIR/workspace-empty"
    mkdir -p "$WORKSPACE_DIR/.octo"
    rm -f "$WORKSPACE_DIR/.octo/provider-telemetry.jsonl"

    local score
    score=$(get_provider_score "codex")
    WORKSPACE_DIR="$orig_ws"

    if assert_equals "0.70" "$score" "Should return default score"; then
        test_pass
    fi
}

test_provider_score_bayesian() {
    test_case "get_provider_score computes Bayesian score with sufficient data"

    local orig_ws="$WORKSPACE_DIR"
    WORKSPACE_DIR="$TEST_TMP_DIR/workspace-bayes"
    mkdir -p "$WORKSPACE_DIR/.octo"
    local tel="$WORKSPACE_DIR/.octo/provider-telemetry.jsonl"
    rm -f "$tel"

    # Write 8 successes and 2 failures for codex
    for i in $(seq 1 8); do
        echo '{"provider":"codex","outcome":"success"}' >> "$tel"
    done
    echo '{"provider":"codex","outcome":"fail"}' >> "$tel"
    echo '{"provider":"codex","outcome":"fail"}' >> "$tel"

    local score
    score=$(get_provider_score "codex")
    WORKSPACE_DIR="$orig_ws"

    # Expected: (8 + 3.5) / (8 + 2 + 5) = 11.5 / 15 = 0.76 (or 0.77 depending on rounding)
    if [[ "$score" == "0.76" || "$score" == "0.77" || "$score" == ".76" || "$score" == ".77" ]]; then
        test_pass
    else
        test_fail "Expected score ~0.76-0.77, got: $score"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Cost Routing Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_detect_trivial_typo() {
    test_case "detect_trivial_task identifies typo fixes"

    local result
    result=$(detect_trivial_task "Fix the typo in README.md")

    if assert_equals "trivial" "$result" "Typo fix should be trivial"; then
        test_pass
    fi
}

test_detect_trivial_rename() {
    test_case "detect_trivial_task identifies renames"

    local result
    result=$(detect_trivial_task "rename myVar to my_var")

    if assert_equals "trivial" "$result" "Rename should be trivial"; then
        test_pass
    fi
}

test_detect_trivial_version_bump() {
    test_case "detect_trivial_task identifies version bumps"

    local result
    result=$(detect_trivial_task "bump the version to 2.0.0")

    if assert_equals "trivial" "$result" "Version bump should be trivial"; then
        test_pass
    fi
}

test_detect_standard_task() {
    test_case "detect_trivial_task returns standard for complex tasks"

    local result
    result=$(detect_trivial_task "Implement user authentication with OAuth2")

    if assert_equals "standard" "$result" "Complex task should be standard"; then
        test_pass
    fi
}

test_cost_routing_aggressive() {
    test_case "select_cost_aware_agent skips for complexity=0 in aggressive mode"

    export OCTOPUS_COST_TIER="aggressive"
    local result
    result=$(select_cost_aware_agent "backend-architect" "0")

    if assert_equals "skip" "$result" "Should skip in aggressive mode for complexity=0"; then
        test_pass
    fi
}

test_cost_routing_balanced() {
    test_case "select_cost_aware_agent uses spark for complexity=0 in balanced mode"

    export OCTOPUS_COST_TIER="balanced"
    local result
    result=$(select_cost_aware_agent "backend-architect" "0")

    if assert_equals "codex-spark" "$result" "Should use spark in balanced mode for complexity=0"; then
        test_pass
    fi
}

test_cost_routing_premium() {
    test_case "select_cost_aware_agent keeps original agent in premium mode"

    export OCTOPUS_COST_TIER="premium"
    local result
    result=$(select_cost_aware_agent "backend-architect" "0")

    if assert_equals "backend-architect" "$result" "Should keep original in premium mode"; then
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Capability Matching Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_extract_task_capabilities_security() {
    test_case "extract_task_capabilities detects security keywords"

    local result
    result=$(extract_task_capabilities "Run a security audit on the API")

    if assert_contains "$result" "vulnerability-scanning" "Should detect security capabilities" && \
       assert_contains "$result" "owasp-compliance" "Should detect OWASP capability"; then
        test_pass
    fi
}

test_extract_task_capabilities_frontend() {
    test_case "extract_task_capabilities detects frontend keywords"

    local result
    result=$(extract_task_capabilities "Build a React frontend with CSS")

    if assert_contains "$result" "react" "Should detect react" && \
       assert_contains "$result" "css" "Should detect css"; then
        test_pass
    fi
}

test_extract_task_capabilities_empty() {
    test_case "extract_task_capabilities returns empty for generic prompt"

    local result
    result=$(extract_task_capabilities "hello world")

    if assert_equals "" "$result" "Should return empty for unmatched prompt"; then
        test_pass
    fi
}

test_score_capability_match() {
    test_case "score_capability_match computes intersection score"

    # Create a temporary config with known capabilities
    local orig_plugin="$PLUGIN_DIR"
    PLUGIN_DIR="$TEST_TMP_DIR/plugin"
    mkdir -p "$PLUGIN_DIR/agents"

    cat > "$PLUGIN_DIR/agents/config.yaml" << 'YAML'
agents:
  test-agent:
    phases: [tangle]
    capabilities: [react, css, accessibility, typescript]
YAML

    local score
    score=$(score_capability_match "test-agent" "react css python")

    PLUGIN_DIR="$orig_plugin"

    # 2 out of 3 task caps matched = 66
    if assert_equals "66" "$score" "Should compute 2/3 = 66% match"; then
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Quorum Consensus Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_extract_keywords() {
    test_case "extract_keywords filters stop words"

    local result
    result=$(extract_keywords "the quick brown fox jumps over the lazy dog" 5)

    # Should not contain stop words like "the" or "over"
    if assert_not_contains "$result" "the" "Should filter 'the'" && \
       assert_not_contains "$result" "over" "Should filter 'over'" && \
       assert_contains "$result" "quick" "Should keep 'quick'"; then
        test_pass
    fi
}

test_detect_agreement_similar() {
    test_case "detect_agreement returns agree for similar outputs"

    local output="We should use React with TypeScript for the frontend component architecture"
    local result
    result=$(detect_agreement "$output" "$output" "$output")

    if assert_equals "agree" "$result" "Identical outputs should agree"; then
        test_pass
    fi
}

test_detect_agreement_different() {
    test_case "detect_agreement returns disagree for dissimilar outputs"

    local a="React TypeScript frontend component architecture state management"
    local b="Python Django backend API REST database PostgreSQL migrations"
    local c="Kubernetes Docker deployment infrastructure cloud AWS scaling"

    local result
    result=$(detect_agreement "$a" "$b" "$c")

    if assert_equals "disagree" "$result" "Dissimilar outputs should disagree"; then
        test_pass
    fi
}

test_apply_consensus_moderator() {
    test_case "apply_consensus returns MODERATOR_MODE for moderator mode"

    local result
    result=$(apply_consensus "moderator" "output_a" "output_b" "output_c" "prompt")

    if assert_equals "MODERATOR_MODE" "$result" "Should return MODERATOR_MODE"; then
        test_pass
    fi
}

test_apply_consensus_quorum() {
    test_case "apply_consensus resolves by quorum for matching outputs"

    local similar_a="React TypeScript frontend component state management hooks"
    local similar_b="React TypeScript frontend component architecture rendering hooks"
    local different="Python Django backend API REST PostgreSQL migrations"

    local result
    result=$(apply_consensus "quorum" "$similar_a" "$similar_b" "$different" "build frontend")

    if assert_not_equals "MODERATOR_MODE" "$result" "Should not return MODERATOR_MODE in quorum" && \
       [[ -n "$result" ]]; then
        test_pass
    else
        test_fail "Quorum should resolve to one of the similar outputs"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# File Path Validation Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_check_file_references_existing() {
    test_case "check_file_references returns empty for existing files"

    # Use a known existing file
    local output="Check the file scripts/orchestrate.sh for issues"
    local result
    result=$(check_file_references "$output" "$PROJECT_ROOT")

    if assert_equals "" "$result" "Should return empty for existing file"; then
        test_pass
    fi
}

test_check_file_references_missing() {
    test_case "check_file_references detects nonexistent files"

    local output="Please update src/nonexistent/fake-file.ts with the changes"
    local result
    result=$(check_file_references "$output" "$PROJECT_ROOT")

    if assert_contains "$result" "src/nonexistent/fake-file.ts" "Should detect missing file"; then
        test_pass
    fi
}

test_run_file_validation_disabled() {
    test_case "run_file_validation is no-op when disabled"

    export OCTOPUS_FILE_VALIDATION="false"

    # Should not error even with bad references
    run_file_validation "test-agent" "src/nonexistent/file.py"
    local exit_code=$?

    export OCTOPUS_FILE_VALIDATION="true"

    if assert_equals "0" "$exit_code" "Should exit 0 when disabled"; then
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Baseline Telemetry Tests (v8.20.1)
# ═══════════════════════════════════════════════════════════════════════════════

test_record_task_metric() {
    test_case "record_task_metric writes to metrics.jsonl"

    export OCTOPUS_PROVIDER_INTELLIGENCE="shadow"
    local orig_ws="$WORKSPACE_DIR"
    WORKSPACE_DIR="$TEST_TMP_DIR/workspace-metrics"
    mkdir -p "$WORKSPACE_DIR/.octo"
    local metrics_file="$WORKSPACE_DIR/.octo/metrics.jsonl"
    rm -f "$metrics_file"

    record_task_metric "task_duration_ms" "1500"
    record_task_metric "task_duration_ms" "2000"
    WORKSPACE_DIR="$orig_ws"

    if [[ -f "$metrics_file" ]]; then
        local count
        count=$(wc -l < "$metrics_file" | tr -d ' ')
        if assert_equals "2" "$count" "Should have 2 metric entries" && \
           assert_contains "$(cat "$metrics_file")" '"metric":"task_duration_ms"' "Should contain metric name"; then
            test_pass
        fi
    else
        test_fail "Metrics file not created"
    fi
}

test_get_metric_summary() {
    test_case "get_metric_summary computes stats"

    local orig_ws="$WORKSPACE_DIR"
    WORKSPACE_DIR="$TEST_TMP_DIR/workspace-summary"
    mkdir -p "$WORKSPACE_DIR/.octo"
    local metrics_file="$WORKSPACE_DIR/.octo/metrics.jsonl"
    rm -f "$metrics_file"

    # Write some metrics
    echo '{"metric":"duration","value":"100","timestamp":"2026-02-22T00:00:00Z","session":"test"}' >> "$metrics_file"
    echo '{"metric":"duration","value":"200","timestamp":"2026-02-22T00:00:00Z","session":"test"}' >> "$metrics_file"
    echo '{"metric":"duration","value":"300","timestamp":"2026-02-22T00:00:00Z","session":"test"}' >> "$metrics_file"

    local result
    result=$(get_metric_summary "duration")
    WORKSPACE_DIR="$orig_ws"

    # Expected: count=3 sum=600 min=100 max=300 avg=200
    if assert_contains "$result" "3" "Should have count 3" && \
       assert_contains "$result" "600" "Should have sum 600"; then
        test_pass
    fi
}

test_get_metric_summary_empty() {
    test_case "get_metric_summary returns zeros for no data"

    local orig_ws="$WORKSPACE_DIR"
    WORKSPACE_DIR="$TEST_TMP_DIR/workspace-empty-metrics"
    mkdir -p "$WORKSPACE_DIR/.octo"
    rm -f "$WORKSPACE_DIR/.octo/metrics.jsonl"

    local result
    result=$(get_metric_summary "nonexistent")
    WORKSPACE_DIR="$orig_ws"

    if assert_equals "0 0 0 0 0" "$result" "Should return all zeros"; then
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Anti-Drift Checkpoint Tests (v8.21.0)
# ═══════════════════════════════════════════════════════════════════════════════

test_drift_check_ok() {
    test_case "check_output_drift returns ok for normal output"

    local prompt="Build a React frontend with TypeScript"
    local output="Here is the React TypeScript component implementation with proper typing and hooks. The frontend uses functional components with useState and useEffect for state management."

    local result
    result=$(check_output_drift "$prompt" "$output" "codex")

    if assert_equals "ok" "$result" "Normal output should return ok"; then
        test_pass
    fi
}

test_drift_check_too_short() {
    test_case "check_output_drift warns on very short output"

    local result
    result=$(check_output_drift "Build a complex system" "OK done" "codex")

    if assert_contains "$result" "warn:output_too_short" "Should warn about short output"; then
        test_pass
    fi
}

test_drift_check_refusal() {
    test_case "check_output_drift detects agent refusal"

    local result
    result=$(check_output_drift "Build authentication" "I cannot help with that request because it violates my guidelines. Please try something else." "codex")

    if assert_equals "drift:agent_refusal" "$result" "Should detect refusal"; then
        test_pass
    fi
}

test_drift_check_low_overlap() {
    test_case "check_output_drift warns on low key term overlap"

    local prompt="kubernetes docker deployment infrastructure cloud scaling containers"
    local output="The recipe calls for flour, sugar, eggs, and butter. Mix thoroughly and bake at 350 degrees for thirty minutes until golden brown on top."

    local result
    result=$(check_output_drift "$prompt" "$output" "codex")

    if assert_contains "$result" "warn:low_key_term_overlap" "Should warn about low term overlap"; then
        test_pass
    fi
}

test_run_drift_check_off() {
    test_case "run_drift_check is no-op when disabled"

    export OCTOPUS_ANTI_DRIFT="off"
    run_drift_check "test" "test" "codex" "tangle"
    local exit_code=$?
    export OCTOPUS_ANTI_DRIFT="warn"

    if assert_equals "0" "$exit_code" "Should exit 0 when disabled"; then
        test_pass
    fi
}

test_run_drift_check_nonblocking() {
    test_case "run_drift_check always returns 0 (non-blocking)"

    export OCTOPUS_ANTI_DRIFT="warn"
    run_drift_check "Build auth" "I cannot help with that" "codex" "tangle"
    local exit_code=$?

    if assert_equals "0" "$exit_code" "Should always return 0 even on drift"; then
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Persona Packs Tests (v8.21.0)
# ═══════════════════════════════════════════════════════════════════════════════

# Source the personas library
source "$PROJECT_ROOT/scripts/lib/personas.sh"

test_discover_packs_empty() {
    test_case "discover_persona_packs returns empty when no packs exist"

    local orig_home="$HOME"
    local orig_root="${PROJECT_ROOT}"
    HOME="$TEST_TMP_DIR/fake-home"
    PROJECT_ROOT="$TEST_TMP_DIR/fake-project"
    mkdir -p "$HOME" "$PROJECT_ROOT"

    local result
    result=$(discover_persona_packs)

    HOME="$orig_home"
    PROJECT_ROOT="$orig_root"

    if assert_equals "" "$result" "Should return empty with no packs"; then
        test_pass
    fi
}

test_discover_packs_found() {
    test_case "discover_persona_packs finds packs with pack.yaml"

    local pack_dir="$TEST_TMP_DIR/personas/test-pack"
    mkdir -p "$pack_dir"
    echo 'name: "Test Pack"' > "$pack_dir/pack.yaml"

    local result
    result=$(discover_persona_packs "$TEST_TMP_DIR/personas")

    if assert_contains "$result" "test-pack" "Should find test pack"; then
        test_pass
    fi
}

test_load_pack_metadata() {
    test_case "load_persona_pack extracts metadata"

    local pack_dir="$TEST_TMP_DIR/pack-meta"
    mkdir -p "$pack_dir"
    cat > "$pack_dir/pack.yaml" << 'YAML'
name: "Security Hardened"
version: "2.0.0"
author: "tester"
description: "Security-focused personas"
personas:
  - file: strict-auditor.md
    replaces: security-auditor
YAML

    local result
    result=$(load_persona_pack "$pack_dir")

    if assert_contains "$result" "name=Security Hardened" "Should extract name" && \
       assert_contains "$result" "version=2.0.0" "Should extract version" && \
       assert_contains "$result" "author=tester" "Should extract author"; then
        test_pass
    fi
}

test_load_pack_missing_name() {
    test_case "load_persona_pack fails on missing name"

    local pack_dir="$TEST_TMP_DIR/pack-no-name"
    mkdir -p "$pack_dir"
    echo 'version: "1.0.0"' > "$pack_dir/pack.yaml"

    local exit_code=0
    local result
    result=$(load_persona_pack "$pack_dir" 2>/dev/null) || exit_code=$?

    if assert_equals "1" "$exit_code" "Should fail without name field"; then
        test_pass
    fi
}

test_get_pack_personas_entries() {
    test_case "get_pack_personas extracts persona entries"

    local pack_dir="$TEST_TMP_DIR/pack-entries"
    mkdir -p "$pack_dir"
    cat > "$pack_dir/pack.yaml" << 'YAML'
name: "Test Pack"
personas:
  - file: custom-reviewer.md
    replaces: code-reviewer
  - file: extended-architect.md
    extends: backend-architect
YAML

    local result
    result=$(get_pack_personas "$pack_dir")

    if assert_contains "$result" "custom-reviewer.md|replaces|code-reviewer" "Should parse replaces entry" && \
       assert_contains "$result" "extended-architect.md|extends|backend-architect" "Should parse extends entry"; then
        test_pass
    fi
}

test_persona_packs_off() {
    test_case "auto_load_persona_packs respects OCTOPUS_PERSONA_PACKS=off"

    export OCTOPUS_PERSONA_PACKS="off"
    auto_load_persona_packs
    local exit_code=$?
    export OCTOPUS_PERSONA_PACKS="auto"

    if assert_equals "0" "$exit_code" "Should exit 0 when disabled"; then
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run all tests
# ═══════════════════════════════════════════════════════════════════════════════

# JSON Wrappers
test_db_set_get
test_db_get_default
test_db_append_cap

# Provider Intelligence
test_record_outcome
test_record_outcome_off
test_provider_score_default
test_provider_score_bayesian

# Cost Routing
test_detect_trivial_typo
test_detect_trivial_rename
test_detect_trivial_version_bump
test_detect_standard_task
test_cost_routing_aggressive
test_cost_routing_balanced
test_cost_routing_premium

# Capability Matching
test_extract_task_capabilities_security
test_extract_task_capabilities_frontend
test_extract_task_capabilities_empty
test_score_capability_match

# Quorum Consensus
test_extract_keywords
test_detect_agreement_similar
test_detect_agreement_different
test_apply_consensus_moderator
test_apply_consensus_quorum

# File Path Validation
test_check_file_references_existing
test_check_file_references_missing
test_run_file_validation_disabled

# Baseline Telemetry (v8.20.1)
test_record_task_metric
test_get_metric_summary
test_get_metric_summary_empty

# Anti-Drift Checkpoints (v8.21.0)
test_drift_check_ok
test_drift_check_too_short
test_drift_check_refusal
test_drift_check_low_overlap
test_run_drift_check_off
test_run_drift_check_nonblocking

# Persona Packs (v8.21.0)
test_discover_packs_empty
test_discover_packs_found
test_load_pack_metadata
test_load_pack_missing_name
test_get_pack_personas_entries
test_persona_packs_off

# Print summary
test_summary
