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

test_council_enforces_provider_diversity_when_available() {
    test_case "Council enforces provider diversity when another provider org is available"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-diversity.XXXXXX")"

    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:missing,codex:available,gemini:available' \
        council_run --dry-run --depth standard --domain security --output-dir "$tmp_dir" "Review auth"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '([.council[].provider_org] | unique | length) >= 2 and (.warnings.provider_diversity_replaced == true)' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "provider diversity replacement did not happen"
        return 1
    fi
}

test_council_scores_roster_with_benchmark_signal() {
    test_case "Council roster has normalized scores and benchmark signals"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-score.XXXXXX")"

    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --dry-run --depth quick --output-dir "$tmp_dir" "Review auth"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '
      all(.council[]; (.score | type) == "number" and .score >= 0 and .score <= 1) and
      any(.council[]; .benchmark_signal != null and .benchmark_signal > 0)
    ' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "roster score or benchmark signal missing"
        return 1
    fi
}

test_council_benchmark_freshness_decays() {
    test_case "Benchmark freshness decays after 30 days and reaches zero after 90"
    load_council_lib || return 1

    local day_10 day_60 day_91
    day_10="$(council_benchmark_freshness_weight 10)"
    day_60="$(council_benchmark_freshness_weight 60)"
    day_91="$(council_benchmark_freshness_weight 91)"

    if awk -v d10="$day_10" -v d60="$day_60" -v d91="$day_91" 'BEGIN { exit !((d10 == 1.0 || d10 == 1) && d60 > 0 && d60 < 1 && d91 == 0) }'; then
        test_pass
    else
        test_fail "freshness weights unexpected: 10=$day_10 60=$day_60 91=$day_91"
        return 1
    fi
}

test_council_refresh_benchmarks_fetches_upstream_sources() {
    test_case "Benchmark refresh script fetches upstream snapshot sources"

    local script="$PROJECT_ROOT/scripts/refresh-benchmarks.sh"
    [[ -x "$script" ]] || { test_fail "refresh script missing or not executable"; return 1; }

    if grep -q "raw.githubusercontent.com/petergpt/bullshit-benchmark" "$script" &&
       grep -q "curl" "$script" &&
       grep -q "leaderboard_with_launch.csv" "$script"; then
        test_pass
    else
        test_fail "refresh script does not fetch upstream BullshitBench sources"
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

test_council_synthesis_is_chair_generated() {
    test_case "Council synthesis is generated by chair dispatch"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-synthesis.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --goal advice --depth standard --output-dir "$tmp_dir" "Should we use Redis?"

    local synthesis
    synthesis="$(find "$tmp_dir" -name synthesis.md -type f | head -1)"
    [[ -n "$synthesis" ]] || { test_fail "synthesis.md not written"; return 1; }

    if grep -q "Fixture response for chair-synthesis" "$synthesis" &&
       grep -q "Council Recommendation" "$synthesis"; then
        test_pass
    else
        test_fail "synthesis did not come from chair dispatch"
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

test_council_approved_gates_start_worktree_handoff() {
    test_case "Council approved gates start implementation handoff with worktree"
    load_council_lib || return 1

    local tmp_dir worktree_root
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-approved.XXXXXX")"
    worktree_root="$tmp_dir/worktrees"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_APPROVED_GATES='gate-a,gate-b' \
    OCTOPUS_COUNCIL_WORKTREE_ROOT="$worktree_root" \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --goal implement --implement after-approval --worktree on --depth quick --output-dir "$tmp_dir" "Refactor auth flow"

    local summary worktree_path
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    worktree_path="$(jq -r '.implementation.handoff.worktree // empty' "$summary")"

    if [[ -n "$worktree_path" ]] &&
       [[ -d "$worktree_path" ]] &&
       jq -e '.implementation.gate_a_approved == true and .implementation.gate_b_approved == true and .implementation.handoff.workflow == "tangle" and .implementation.handoff.status == "started"' "$summary" >/dev/null; then
        git -C "$PROJECT_ROOT" worktree remove --force "$worktree_path" >/dev/null 2>&1 || rm -rf "$worktree_path"
        test_pass
    else
        [[ -n "$worktree_path" ]] && git -C "$PROJECT_ROOT" worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
        test_fail "approved implementation handoff did not create expected worktree"
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

test_council_chair_fallback_preserves_quorum() {
    test_case "Council retries failed chair with synthesis-capable fallback"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-chair-fallback.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_FAIL_PERSONAS='strategy-analyst' \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --depth quick --output-dir "$tmp_dir" "Review auth"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.status == "completed" and .quorum.met == true and .warnings.chair_fallback == true and (.quorum.chair_received == true)' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "chair fallback did not preserve quorum"
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

test_council_cost_cap_aborts_before_critique() {
    test_case "Council cost cap re-check aborts before critique"
    load_council_lib || return 1

    local tmp_dir task
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-cost-critique.XXXXXX")"
    task="$(printf '%0640d' 0 | tr '0' 'x')"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --depth standard --max-cost 0.02 --output-dir "$tmp_dir" "$task"

    local run_dir summary response_count critique_count
    run_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    summary="$run_dir/summary.json"
    response_count="$(find "$run_dir/responses" -type f -name '*.md' | wc -l | tr -d ' ')"
    critique_count="$(find "$run_dir/critiques" -type f -name '*.md' | wc -l | tr -d ' ')"

    if [[ "$response_count" -eq 5 ]] &&
       [[ "$critique_count" -eq 0 ]] &&
       jq -e '.status == "aborted" and .budget.aborted_for_cost == true and .quorum.met == true' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "cost cap should abort after advice and before critique"
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

test_council_scans_artifact_critical_veto() {
    test_case "Council scans artifacts for critical veto"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-artifact-veto.XXXXXX")"
    mkdir -p "$tmp_dir/responses" "$tmp_dir/critiques" "$tmp_dir/revisions"

    council_reset_defaults
    COUNCIL_RUN_DIR="$tmp_dir"
    COUNCIL_FIXTURE=""

    cat > "$tmp_dir/responses/01-security-auditor.md" << 'EOF'
VETO: critical
Confidence: 0.86
Reason: The migration plan can corrupt production data.
EOF

    council_scan_veto_artifacts

    if [[ "$COUNCIL_VETO_TRIGGERED" == "true" ]] &&
       [[ "$COUNCIL_VETO_SEVERITY" == "critical" ]] &&
       [[ "$COUNCIL_VETO_CONFIDENCE" == "0.86" ]] &&
       grep -q "corrupt production data" <<< "$COUNCIL_VETO_REASON"; then
        test_pass
    else
        test_fail "critical artifact veto was not detected"
        return 1
    fi
}

test_council_structured_veto_requires_veto_role() {
    test_case "Structured critical veto only triggers from veto-capable roles"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-structured-veto.XXXXXX")"
    mkdir -p "$tmp_dir/responses" "$tmp_dir/critiques" "$tmp_dir/revisions"

    council_reset_defaults
    COUNCIL_RUN_DIR="$tmp_dir"
    COUNCIL_FIXTURE=""

    cat > "$tmp_dir/responses/01-backend-architect.md" << 'EOF'
```json
{"severity":"critical","confidence":0.9,"reason":"Architectural disagreement only"}
```
EOF

    council_scan_veto_artifacts
    if [[ "$COUNCIL_VETO_TRIGGERED" == "true" ]]; then
        test_fail "non-veto role should not trigger structured veto"
        return 1
    fi

    cat > "$tmp_dir/responses/02-security-auditor.md" << 'EOF'
```json
{"severity":"critical","confidence":0.92,"reason":"Credential exposure risk"}
```
EOF

    council_scan_veto_artifacts
    if [[ "$COUNCIL_VETO_TRIGGERED" == "true" ]] &&
       [[ "$COUNCIL_VETO_SEVERITY" == "critical" ]] &&
       grep -q "Credential exposure" <<< "$COUNCIL_VETO_REASON"; then
        test_pass
    else
        test_fail "veto-capable structured critical risk was not detected"
        return 1
    fi
}

test_council_veto_scan_ignores_discussed_token() {
    test_case "Council veto scan ignores incidental critical-veto text"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-veto-token.XXXXXX")"
    mkdir -p "$tmp_dir/responses" "$tmp_dir/critiques" "$tmp_dir/revisions"

    council_reset_defaults
    COUNCIL_RUN_DIR="$tmp_dir"
    COUNCIL_FIXTURE=""

    cat > "$tmp_dir/responses/01-security-auditor.md" << 'EOF'
This artifact discusses the critical-veto fixture token, but it is not issuing a veto.
EOF

    council_scan_veto_artifacts
    if [[ "$COUNCIL_VETO_TRIGGERED" == "true" ]]; then
        test_fail "incidental critical-veto token should not trigger veto"
        return 1
    fi

    test_pass
}

test_council_dispatch_strips_blocked_env_but_sets_readonly() {
    test_case "Council dispatch strips blocked caller env while setting read-only sandbox"
    load_council_lib || return 1

    local tmp_dir env_capture
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-env.XXXXXX")"
    env_capture="$tmp_dir/env.out"

    run_agent_sync() {
        env > "$env_capture"
        echo "ok"
    }

    OCTOPUS_SECURITY_V870=false \
    OCTOPUS_GEMINI_SANDBOX=unsafe \
    OCTOPUS_CODEX_SANDBOX=caller-danger \
    CLAUDE_OCTOPUS_AUTONOMY=autonomous \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='codex:available' \
        council_run --providers codex --depth quick --members 3 --output-dir "$tmp_dir" "Review auth"

    if grep -q '^OCTOPUS_CODEX_SANDBOX=read-only$' "$env_capture" &&
       ! grep -q '^OCTOPUS_SECURITY_V870=' "$env_capture" &&
       ! grep -q '^OCTOPUS_GEMINI_SANDBOX=' "$env_capture" &&
       ! grep -q '^CLAUDE_OCTOPUS_AUTONOMY=' "$env_capture"; then
        unset -f run_agent_sync
        test_pass
    else
        unset -f run_agent_sync
        test_fail "blocked env forwarding or read-only sandbox mismatch"
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
test_council_enforces_provider_diversity_when_available
test_council_scores_roster_with_benchmark_signal
test_council_benchmark_freshness_decays
test_council_refresh_benchmarks_fetches_upstream_sources
test_council_skill_documents_gates
test_council_pass_parser_accepts_variants
test_council_fixture_run_writes_phase_artifacts
test_council_synthesis_is_chair_generated
test_council_plan_only_writes_implementation_plan_without_handoff
test_council_after_approval_does_not_handoff_without_gate
test_council_approved_gates_start_worktree_handoff
test_council_critical_veto_aborts_implementation_run
test_council_chair_fallback_preserves_quorum
test_council_cost_cap_aborts_before_fanout
test_council_cost_cap_aborts_before_critique
test_council_deep_fixture_writes_revision_artifacts
test_council_cross_critique_prompt_includes_peer_responses
test_council_revision_prompt_includes_prior_critiques
test_council_scans_artifact_critical_veto
test_council_structured_veto_requires_veto_role
test_council_veto_scan_ignores_discussed_token
test_council_dispatch_strips_blocked_env_but_sets_readonly
test_summary
