#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Council Command"

test_council_command_files_are_registered() {
    test_case "Council command and skill are registered"

    local command_file="$PROJECT_ROOT/.claude/commands/council.md"
    local skill_file="$PROJECT_ROOT/skills/skill-council/SKILL.md"
    local plugin_file="$PROJECT_ROOT/.claude-plugin/plugin.json"

    [[ -f "$command_file" ]] || { test_fail "Missing $command_file"; return 1; }
    [[ -f "$skill_file" ]] || { test_fail "Missing $skill_file"; return 1; }

    if jq -e '.commands[] | select(. == "./.claude/commands/council.md")' "$plugin_file" >/dev/null &&
       jq -e '.skills[] | select(. == "./skills/skill-council")' "$plugin_file" >/dev/null; then
        test_pass
    else
        test_fail "plugin.json missing council command or skill"
        return 1
    fi
}

test_council_orchestrate_route_exists() {
    test_case "orchestrate.sh routes council command"

    if grep -q 'council)' "$PROJECT_ROOT/scripts/orchestrate.sh" &&
       grep -q 'council_run' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "council route missing"
        return 1
    fi
}

load_council_lib() {
    local lib="$PROJECT_ROOT/scripts/lib/council.sh"
    if [[ ! -f "$lib" ]]; then
        test_fail "Missing $lib"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$lib"
}

test_council_defaults_are_depth_aware() {
    test_case "Council defaults are depth aware"
    load_council_lib || return 1

    council_parse_args --depth standard --dry-run "Review auth"

    [[ "$COUNCIL_DEPTH" == "standard" ]] || { test_fail "depth not parsed"; return 1; }
    [[ "$COUNCIL_MEMBERS" == "auto" ]] || { test_fail "members default not auto"; return 1; }
    [[ "$COUNCIL_RESOLVED_MEMBERS" == "5" ]] || { test_fail "standard should resolve to 5 members"; return 1; }
    [[ "$COUNCIL_MAX_COST" == "2.00" ]] || { test_fail "standard default budget should be 2.00"; return 1; }
    test_pass
}

test_council_rejects_non_usd_budget() {
    test_case "Council rejects non-USD budget values"
    load_council_lib || return 1

    local out_file="$TEST_TMP_DIR/council-budget.out"
    set +e
    council_parse_args --max-cost '$2.00' "Review auth" >"$out_file" 2>&1
    local status=$?
    set -e

    [[ $status -eq 2 ]] || { test_fail "expected exit code 2, got $status"; return 1; }
    grep -q "USD decimal" "$out_file" || { test_fail "missing usage hint"; return 1; }
    test_pass
}

test_council_dry_run_writes_summary_json() {
    test_case "Council dry-run writes summary JSON"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council.XXXXXX")"

    council_run --dry-run --goal advice --depth quick --output-dir "$tmp_dir" "Should we use Redis?"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.command == "council" and .status == "dry-run" and .implementation.worktree == "auto"' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "summary JSON contract mismatch"
        return 1
    fi
}

test_council_explicit_members_override_depth() {
    test_case "Explicit members override depth member preset"
    load_council_lib || return 1

    council_parse_args --depth quick --members 7 --dry-run "Review auth"

    [[ "$COUNCIL_RESOLVED_MEMBERS" == "7" ]] || { test_fail "explicit members should win"; return 1; }
    [[ "$COUNCIL_MEMBER_OVERRIDE_WARNING" == "true" ]] || { test_fail "missing member override warning"; return 1; }
    test_pass
}

test_council_dry_run_maps_implementation_and_worktree() {
    test_case "Council dry-run maps implementation and worktree flags"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-impl.XXXXXX")"

    council_run --dry-run --goal implement --implement after-approval --worktree on --output-dir "$tmp_dir" "Refactor auth flow"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.implementation.permission == "after-approval" and .implementation.worktree == "on"' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "implementation/worktree mapping mismatch"
        return 1
    fi
}

test_council_dry_run_has_multi_seat_recommendation_and_cost() {
    test_case "Council dry-run has multiple seats and positive cost estimate"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-cost.XXXXXX")"

    council_run --dry-run --depth quick --output-dir "$tmp_dir" "Should we use Redis?"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '(.council | length) >= 2 and .budget.estimated_cost_usd > 0' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "missing multi-seat recommendation or positive cost"
        return 1
    fi
}

test_council_critical_veto_fixture_marks_veto() {
    test_case "Critical veto fixture marks veto path"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-veto.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=critical-veto \
        council_run --dry-run --goal implement --output-dir "$tmp_dir" "Ship this without tests"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.veto.triggered == true and .veto.severity == "critical"' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "critical veto fixture did not trigger veto"
        return 1
    fi
}

test_council_dry_run_loads_fresh_benchmark_snapshot() {
    test_case "Council dry-run loads fresh benchmark snapshot"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-benchmark.XXXXXX")"

    council_run --dry-run --benchmark auto --output-dir "$tmp_dir" "Should we use Redis?"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.benchmark.used == true and (.benchmark.freshness_days | type == "number")' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "benchmark snapshot not loaded"
        return 1
    fi
}

test_council_provider_fixture_records_status() {
    test_case "Council provider fixture records availability"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-providers.XXXXXX")"

    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:missing' \
        council_run --dry-run --providers auto --output-dir "$tmp_dir" "Review auth"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.provider_status.claude == "available" and .provider_status.gemini == "missing"' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "provider status fixture not recorded"
        return 1
    fi
}

test_council_rejects_unknown_provider() {
    test_case "Council rejects unknown providers"
    load_council_lib || return 1

    local out_file="$TEST_TMP_DIR/council-provider.out"
    set +e
    council_parse_args --providers claude,not-a-provider "Review auth" >"$out_file" 2>&1
    local status=$?
    set -e

    [[ $status -eq 2 ]] || { test_fail "expected exit code 2, got $status"; return 1; }
    grep -q "unknown provider" "$out_file" || { test_fail "missing provider usage hint"; return 1; }
    test_pass
}

test_council_roster_matches_resolved_members() {
    test_case "Council roster matches resolved member count"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-roster.XXXXXX")"

    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --dry-run --depth standard --output-dir "$tmp_dir" "Review auth"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.members == 5 and (.council | length) == .members' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "roster length does not match resolved members"
        return 1
    fi
}

test_council_persona_pin_affects_roster() {
    test_case "Persona pin affects council roster"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-persona.XXXXXX")"

    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --dry-run --members 3 --persona finance-analyst --output-dir "$tmp_dir" "Review pricing"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.personas_requested == "finance-analyst" and any(.council[]; .persona == "finance-analyst")' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "pinned persona missing from roster"
        return 1
    fi
}

test_council_skill_documents_gates() {
    test_case "Council skill documents preflight, quorum, and gates"

    local skill_file="$PROJECT_ROOT/skills/skill-council/SKILL.md"

    if grep -q "Phase 0: Preflight" "$skill_file" &&
       grep -q "Quorum" "$skill_file" &&
       grep -q "Gate A" "$skill_file" &&
       grep -q "Gate B" "$skill_file"; then
        test_pass
    else
        test_fail "skill-council missing operational procedure"
        return 1
    fi
}

test_council_pass_parser_accepts_variants() {
    test_case "Council PASS parser accepts variants"
    load_council_lib || return 1

    council_is_pass "PASS" || { test_fail "PASS not accepted"; return 1; }
    council_is_pass " pass. " || { test_fail "pass. not accepted"; return 1; }
    council_is_pass "PASS - nothing to add" || { test_fail "PASS suffix not accepted"; return 1; }

    if council_is_pass "PASS but this implementation is risky"; then
        test_fail "substantive PASS response should not be accepted"
        return 1
    fi

    test_pass
}

test_council_fixture_run_writes_phase_artifacts() {
    test_case "Council fixture run writes phase artifacts"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-full.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --goal advice --depth standard --output-dir "$tmp_dir" "Should we use Redis?"

    local run_dir summary
    run_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    summary="$run_dir/summary.json"

    [[ -f "$run_dir/config.json" ]] || { test_fail "config.json not written"; return 1; }
    [[ -f "$run_dir/synthesis.md" ]] || { test_fail "synthesis.md not written"; return 1; }
    [[ -f "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    local response_count critique_count
    response_count="$(find "$run_dir/responses" -type f -name '*.md' | wc -l | tr -d ' ')"
    critique_count="$(find "$run_dir/critiques" -type f -name '*.md' | wc -l | tr -d ' ')"

    if [[ "$response_count" -eq 5 ]] &&
       [[ "$critique_count" -eq 5 ]] &&
       jq -e '.status == "completed" and .quorum.met == true and .quorum.received_non_chair == 4' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "phase artifacts or quorum summary mismatch"
        return 1
    fi
}

test_council_plan_only_writes_implementation_plan_without_handoff() {
    test_case "Council plan-only writes implementation plan without handoff"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-plan.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --goal implement --implement plan-only --depth standard --output-dir "$tmp_dir" "Refactor auth flow"

    local run_dir summary
    run_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    summary="$run_dir/summary.json"

    [[ -f "$run_dir/implementation-plan.md" ]] || { test_fail "implementation-plan.md not written"; return 1; }

    if jq -e '.status == "completed" and .implementation.permission == "plan-only" and .implementation.handoff == null and .artifacts.implementation_plan == "implementation-plan.md"' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "implementation plan summary mismatch"
        return 1
    fi
}

test_council_after_approval_does_not_handoff_without_gate() {
    test_case "Council after-approval does not hand off without gate approval"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-gate.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --goal implement --implement after-approval --depth standard --output-dir "$tmp_dir" "Refactor auth flow"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.status == "completed" and .implementation.gate_a_approved == false and .implementation.gate_b_approved == false and .implementation.handoff == null' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "implementation gates should remain closed"
        return 1
    fi
}

test_council_critical_veto_aborts_implementation_run() {
    test_case "Council critical veto aborts implementation run"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-veto-run.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=critical-veto \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --goal implement --implement after-approval --depth standard --output-dir "$tmp_dir" "Ship this without tests"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.status == "aborted" and .veto.triggered == true and .implementation.handoff == null' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "critical veto should abort without handoff"
        return 1
    fi
}

test_council_cost_cap_aborts_before_fanout() {
    test_case "Council cost cap aborts before fanout"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-cost-cap.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --max-cost 0.00 --output-dir "$tmp_dir" "Should we use Redis?"

    local run_dir summary response_count
    run_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    summary="$run_dir/summary.json"
    response_count="$(find "$run_dir/responses" -type f -name '*.md' | wc -l | tr -d ' ')"

    if [[ "$response_count" -eq 0 ]] &&
       jq -e '.status == "aborted" and .budget.aborted_for_cost == true and .quorum.met == false' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "cost cap should abort before fanout"
        return 1
    fi
}

test_council_deep_fixture_writes_revision_artifacts() {
    test_case "Council deep run writes revision artifacts"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-deep.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --depth deep --output-dir "$tmp_dir" "Review platform architecture"

    local run_dir summary revision_count
    run_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    summary="$run_dir/summary.json"
    revision_count="$(find "$run_dir/revisions" -type f -name '*.md' | wc -l | tr -d ' ')"

    if [[ "$revision_count" -eq 7 ]] &&
       jq -e '.status == "completed" and .artifacts.revisions_dir == "revisions"' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "deep revision artifacts missing"
        return 1
    fi
}

test_council_cross_critique_prompt_includes_peer_responses() {
    test_case "Council cross-critique prompt includes semi-anonymized peer responses"
    load_council_lib || return 1

    local tmp_dir prompt
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-prompt.XXXXXX")"
    mkdir -p "$tmp_dir/responses" "$tmp_dir/critiques"

    COUNCIL_RUN_DIR="$tmp_dir"
    COUNCIL_TASK="Review auth"
    COUNCIL_GOAL="advice"
    COUNCIL_DOMAIN="architecture"
    COUNCIL_STYLE="balanced"
    COUNCIL_DEPTH="standard"

    printf 'Strategy recommendation\n' > "$tmp_dir/responses/00-strategy-analyst.md"
    printf 'Security recommendation\n' > "$tmp_dir/responses/01-security-auditor.md"

    prompt="$(council_prompt_for_member "backend-architect" "cross-critique")"

    if grep -q "COUNCIL_PEER_RESPONSES" <<< "$prompt" &&
       grep -q "Role: strategy analyst" <<< "$prompt" &&
       grep -q "Strategy recommendation" <<< "$prompt" &&
       ! grep -q "provider:" <<< "$prompt"; then
        test_pass
    else
        test_fail "cross-critique prompt missing semi-anonymized peer context"
        return 1
    fi
}

test_council_revision_prompt_includes_prior_critiques() {
    test_case "Council revision prompt includes prior critiques"
    load_council_lib || return 1

    local tmp_dir prompt
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-revision-prompt.XXXXXX")"
    mkdir -p "$tmp_dir/responses" "$tmp_dir/critiques"

    COUNCIL_RUN_DIR="$tmp_dir"
    COUNCIL_TASK="Review auth"
    COUNCIL_GOAL="advice"
    COUNCIL_DOMAIN="architecture"
    COUNCIL_STYLE="balanced"
    COUNCIL_DEPTH="deep"

    printf 'Risk: missing migration plan\n' > "$tmp_dir/critiques/01-security-auditor.md"

    prompt="$(council_prompt_for_member "backend-architect" "revision-after-critique")"

    if grep -q "COUNCIL_PRIOR_CRITIQUES" <<< "$prompt" &&
       grep -q "Risk: missing migration plan" <<< "$prompt"; then
        test_pass
    else
        test_fail "revision prompt missing prior critique context"
        return 1
    fi
}

test_council_command_files_are_registered
test_council_orchestrate_route_exists
test_council_defaults_are_depth_aware
test_council_rejects_non_usd_budget
test_council_dry_run_writes_summary_json
test_council_explicit_members_override_depth
test_council_dry_run_maps_implementation_and_worktree
test_council_dry_run_has_multi_seat_recommendation_and_cost
test_council_critical_veto_fixture_marks_veto
test_council_dry_run_loads_fresh_benchmark_snapshot
test_council_provider_fixture_records_status
test_council_rejects_unknown_provider
test_council_roster_matches_resolved_members
test_council_persona_pin_affects_roster
test_council_skill_documents_gates
test_council_pass_parser_accepts_variants
test_council_fixture_run_writes_phase_artifacts
test_council_plan_only_writes_implementation_plan_without_handoff
test_council_after_approval_does_not_handoff_without_gate
test_council_critical_veto_aborts_implementation_run
test_council_cost_cap_aborts_before_fanout
test_council_deep_fixture_writes_revision_artifacts
test_council_cross_critique_prompt_includes_peer_responses
test_council_revision_prompt_includes_prior_critiques
test_summary
