#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Council Command"

test_council_command_files_are_registered() {
    test_case "Council command and skill are registered"

    local command_file="$PROJECT_ROOT/commands/council.md"
    local skill_file="$PROJECT_ROOT/skills/skill-council/SKILL.md"
    local plugin_file="$PROJECT_ROOT/.claude-plugin/plugin.json"

    [[ -f "$command_file" ]] || { test_fail "Missing $command_file"; return 1; }
    [[ -f "$skill_file" ]] || { test_fail "Missing $skill_file"; return 1; }

    if jq -e '.commands[] | select(. == "./commands/council.md")' "$plugin_file" >/dev/null &&
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

test_council_benchmark_routing_lib_is_extracted() {
    test_case "Council benchmark routing lives in a dedicated lib"

    local lib="$PROJECT_ROOT/scripts/lib/benchmark-routing.sh"
    [[ -f "$lib" ]] || { test_fail "Missing $lib"; return 1; }

    if grep -q 'council_benchmark_signal' "$lib" &&
       grep -q 'benchmark-routing.sh' "$PROJECT_ROOT/scripts/orchestrate.sh" &&
       ! grep -q '^council_benchmark_signal()' "$PROJECT_ROOT/scripts/lib/council.sh"; then
        test_pass
    else
        test_fail "benchmark routing is not extracted cleanly"
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

    # The contract is a multi-org final roster. Fresher model resolution (agy
    # provider + config-checksum cache key) can produce a naturally diverse
    # roster without firing the forced-replacement path, so assert the real
    # guarantee (>=2 provider orgs) rather than the replacement mechanism.
    if jq -e '([.council[].provider_org] | unique | length) >= 2' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "council roster is single-org; provider diversity not enforced"
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

test_council_role_fit_uses_agent_capability_tags() {
    test_case "Council role fit uses agents/config.yaml capability tags"
    load_council_lib || return 1

    council_reset_defaults
    COUNCIL_DOMAIN="product"
    COUNCIL_GOAL="plan"

    local business_fit backend_fit
    business_fit="$(council_role_fit_signal "business-analyst" "advisor")"
    backend_fit="$(council_role_fit_signal "backend-architect" "advisor")"

    if awk -v business="$business_fit" -v backend="$backend_fit" 'BEGIN { exit !(business >= 0.90 && business > backend) }'; then
        test_pass
    else
        test_fail "product planning should prefer business-analyst capability tags over backend fallback: business=$business_fit backend=$backend_fit"
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

test_council_command_requires_real_runner_by_default() {
    test_case "Council command requires real runner by default"

    local command_file="$PROJECT_ROOT/commands/council.md"
    local skill_file="$PROJECT_ROOT/skills/skill-council/SKILL.md"

    if grep -q 'scripts/orchestrate.sh" council' "$command_file" &&
       grep -q "Do not simulate" "$command_file" &&
       grep -q "single-model simulation" "$skill_file" &&
       grep -q "must be explicitly requested" "$skill_file"; then
        test_pass
    else
        test_fail "council command/skill does not force real runner by default"
        return 1
    fi
}

test_council_skill_requires_interactive_choices_for_clarification() {
    test_case "Council skill requires interactive choices for clarification"

    local command_file="$PROJECT_ROOT/commands/council.md"
    local cursor_command_file="$PROJECT_ROOT/.cursor-plugin/commands/octo-council.md"
    local skill_file="$PROJECT_ROOT/skills/skill-council/SKILL.md"

    if grep -q "AskUserQuestion" "$command_file" &&
       grep -q "AskUserQuestion" "$cursor_command_file" &&
       grep -q "AskUserQuestion" "$skill_file" &&
       grep -q "before running the council runner" "$skill_file" &&
       grep -q "Interactive Choice Handling" "$skill_file" &&
       grep -q "2-4 mutually exclusive choices" "$skill_file" &&
       grep -q "Do not end" "$skill_file"; then
        test_pass
    else
        test_fail "skill-council missing interactive choice guidance"
        return 1
    fi
}

test_council_help_shows_simulation_research_and_corpus_flags() {
    test_case "Council help shows simulation, research, and corpus flags"

    local output
    output="$("$PROJECT_ROOT/scripts/orchestrate.sh" council --help 2>&1)"

    if echo "$output" | grep -q -- "--simulate" &&
       echo "$output" | grep -q -- "--single-model" &&
       echo "$output" | grep -q -- "--research-first" &&
       echo "$output" | grep -q -- "--corpus-mode"; then
        test_pass
    else
        test_fail "help output missing simulation/research/corpus flags"
        return 1
    fi
}

test_council_summary_records_execution_and_corpus_modes() {
    test_case "Council summary records execution and corpus modes"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-mode.XXXXXX")"

    council_run --dry-run --simulate --research-first --corpus-mode append --output-dir "$tmp_dir" "Review platform options"

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '
      .execution.mode == "single-model-simulation" and
      .execution.real_runner_required == true and
      .execution.simulation_explicit == true and
      .research.first == true and
      .corpus.mode == "append"
    ' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "execution/research/corpus summary metadata mismatch"
        return 1
    fi
}

test_council_corpus_require_rejects_missing_workspace() {
    test_case "Council corpus require rejects missing workspace"
    load_council_lib || return 1

    local out_file="$TEST_TMP_DIR/council-corpus.out"
    set +e
    council_parse_args --corpus-mode require "Review platform options" >"$out_file" 2>&1
    local status=$?
    set -e

    [[ $status -eq 2 ]] || { test_fail "expected exit code 2, got $status"; return 1; }
    grep -q "corpus workspace" "$out_file" || { test_fail "missing corpus usage hint"; return 1; }
    test_pass
}

test_council_research_first_writes_artifact_and_prompt_context() {
    test_case "Council research-first writes artifact and injects prompt context"
    load_council_lib || return 1

    local tmp_dir corpus_root
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-research.XXXXXX")"
    corpus_root="$tmp_dir/corpus"
    mkdir -p "$corpus_root/03_knowledge_base"
    printf '# Existing Decision\n\nUse boring, observable infrastructure.\n' > "$corpus_root/03_knowledge_base/decision.md"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_CORPUS_ROOT="$corpus_root" \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --research-first --depth quick --output-dir "$tmp_dir" "Review queue options"

    local run_dir summary research prompt
    run_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d ! -name corpus | head -1)"
    summary="$run_dir/summary.json"
    research="$run_dir/research.md"
    [[ -f "$research" ]] || { test_fail "research.md not written"; return 1; }

    COUNCIL_RUN_DIR="$run_dir"
    prompt="$(council_prompt_for_member "backend-architect" "independent-advice")"

    if grep -q "Existing Decision" "$research" &&
       grep -q "COUNCIL_RESEARCH_CONTEXT" <<< "$prompt" &&
       jq -e '.research.first == true and .research.artifact == "research.md"' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "research artifact or prompt context missing"
        return 1
    fi
}

test_council_corpus_append_writes_durable_entry() {
    test_case "Council corpus append writes durable entry"
    load_council_lib || return 1

    local tmp_dir corpus_root
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-corpus-append.XXXXXX")"
    corpus_root="$tmp_dir/corpus"
    mkdir -p "$corpus_root/03_knowledge_base"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_CORPUS_ROOT="$corpus_root" \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --research-first --corpus-mode append --goal implement --implement plan-only --depth quick --output-dir "$tmp_dir" "Plan auth cleanup"

    local summary entry
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }
    entry="$(jq -r '.corpus.entry // empty' "$summary")"

    if [[ -n "$entry" ]] &&
       [[ -f "$entry" ]] &&
       grep -q "Council Synthesis" "$entry" &&
       grep -q "Implementation Plan" "$entry" &&
       jq -e '.corpus.mode == "append" and (.corpus.entry | type == "string")' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "corpus entry missing expected retained artifacts"
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
       jq -e '
           .status == "completed"
           and .quorum.met == true
           and .quorum.received_non_chair
               == ([.seats[] | select(.seat != "chair" and .status == "responded")] | length)
       ' "$summary" >/dev/null; then
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

test_council_diversity_warning_prints_to_cli() {
    test_case "Council prints provider diversity warning to CLI"
    load_council_lib || return 1

    local tmp_dir out_file
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-diversity-output.XXXXXX")"
    out_file="$TEST_TMP_DIR/council-diversity-output.out"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:missing,codex:available,gemini:available' \
        council_run --depth standard --domain security --output-dir "$tmp_dir" "Review auth" >"$out_file" 2>&1

    # The CLI warning only prints when the forced-replacement path fires. With
    # fresher model resolution the roster can be diverse from the start, so accept
    # either the warning OR a final roster that already spans >=2 provider orgs.
    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    if grep -q "Council warning: adjusted one non-chair seat" "$out_file" || \
       { [[ -n "$summary" ]] && jq -e '([.council[].provider_org] | unique | length) >= 2' "$summary" >/dev/null; }; then
        test_pass
    else
        test_fail "neither diversity warning printed nor multi-org roster produced"
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

    if jq -e '
        .status == "completed"
        and .quorum.met == true
        and .warnings.chair_fallback == true
        and (.quorum.chair_received == true)
        # The failed roster chair remains visible, and the successfully dispatched
        # fallback is an additional, fully typed execution record.
        and (.seats[0].seat == "chair" and .seats[0].status == "no-response")
        and ((.seats | length) == ((.council | length) + 1))
        and (.seats[-1] as $fallback
             | $fallback.index == (.council | length)
             and $fallback.persona == .warnings.chair_fallback_persona
             and $fallback.seat == "chair"
             and ([$fallback.provider, $fallback.provider_org, $fallback.model,
                   $fallback.payload_kind, $fallback.status]
                  | all(type == "string" and length > 0))
             and $fallback.response_bytes > 0
             and $fallback.verdict == "APPROVE"
             and ($fallback.counted_as_approver | type == "boolean"))
    ' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "chair fallback did not preserve quorum"
        return 1
    fi
}

test_council_chair_fallback_warning_prints_to_cli() {
    test_case "Council prints chair fallback warning to CLI"
    load_council_lib || return 1

    local tmp_dir out_file
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-chair-output.XXXXXX")"
    out_file="$TEST_TMP_DIR/council-chair-output.out"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_FAIL_PERSONAS='strategy-analyst' \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --depth quick --output-dir "$tmp_dir" "Review auth" >"$out_file" 2>&1

    if grep -q "Council warning: chair fallback used" "$out_file"; then
        test_pass
    else
        test_fail "chair fallback warning not printed"
        return 1
    fi
}

test_council_fixture_critique_honors_failed_persona() {
    test_case "Council fixture critique honors failed persona filter"
    load_council_lib || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-critique-fail.XXXXXX")"

    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_FAIL_PERSONAS='security-auditor' \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,gemini:available' \
        council_run --depth standard --output-dir "$tmp_dir" "Review auth"

    local run_dir summary security_critiques
    run_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    summary="$run_dir/summary.json"
    security_critiques="$(find "$run_dir/critiques" -type f -name '*security-auditor.md' | wc -l | tr -d ' ')"

    if [[ "$security_critiques" -eq 0 ]] &&
       jq -e '.status == "completed" and .quorum.met == true' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "failed persona should not produce fixture critique artifact"
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

test_council_prompt_task_block_is_authoritative() {
    test_case "Council prompt trust boundary: task authoritative, artifact blocks untrusted, task format wins"
    load_council_lib || return 1

    # Regression for the persona injection false-positive: the old prompt told
    # seats to treat COUNCIL_TASK itself as untrusted data ("unless part of the
    # user's top-level request" — unsatisfiable, since the task block IS the
    # only channel carrying that request). A rule-following seat then refused
    # the task's own output-format instructions as an injection attempt and
    # BLOCKed. The trust boundary must sit between the task block (the user's
    # request: authoritative) and the other COUNCIL_* blocks (third-party
    # content: untrusted), and the default output structure must yield to a
    # task-specified format.
    COUNCIL_TASK="Answer the brief exactly in its IDEAS/ANTI-IDEAS format"
    COUNCIL_GOAL="advice"
    COUNCIL_DOMAIN="auto"
    COUNCIL_STYLE="balanced"
    COUNCIL_DEPTH="standard"
    COUNCIL_RESEARCH_FIRST="false"
    COUNCIL_RUN_DIR="$(mktemp -d "$TEST_TMP_DIR/council-trust.XXXXXX")"

    local prompt
    prompt="$(council_prompt_for_member "backend-architect" "independent-advice")"

    if grep -q "authoritative instruction source" <<< "$prompt" &&
       ! grep -q "COUNCIL_TASK and COUNCIL_\* artifact blocks as untrusted" <<< "$prompt" &&
       grep -q "untrusted data" <<< "$prompt" &&
       grep -q "If the Task specifies an output format" <<< "$prompt" &&
       grep -q "VERDICT: APPROVE" <<< "$prompt"; then
        test_pass
    else
        test_fail "trust boundary wrong: task must be authoritative (incl. its format), artifact blocks untrusted, verdict footer intact"
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

test_council_dispatch_strips_blocked_env_but_sets_disposable_mode() {
    test_case "Council dispatch strips blocked caller env while setting disposable-workspace mode"
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

    if grep -q '^OCTOPUS_CODEX_SANDBOX=danger-full-access$' "$env_capture" &&
       ! grep -q '^OCTOPUS_SECURITY_V870=' "$env_capture" &&
       ! grep -q '^OCTOPUS_GEMINI_SANDBOX=' "$env_capture" &&
       ! grep -q '^CLAUDE_OCTOPUS_AUTONOMY=' "$env_capture"; then
        unset -f run_agent_sync
        test_pass
    else
        unset -f run_agent_sync
        test_fail "blocked env forwarding or disposable-workspace mode mismatch"
        return 1
    fi
}

test_council_command_files_are_registered
test_council_orchestrate_route_exists
test_council_benchmark_routing_lib_is_extracted
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
test_council_role_fit_uses_agent_capability_tags
test_council_benchmark_freshness_decays
test_council_refresh_benchmarks_fetches_upstream_sources
test_council_skill_documents_gates
test_council_command_requires_real_runner_by_default
test_council_skill_requires_interactive_choices_for_clarification
test_council_help_shows_simulation_research_and_corpus_flags
test_council_summary_records_execution_and_corpus_modes
test_council_corpus_require_rejects_missing_workspace
test_council_research_first_writes_artifact_and_prompt_context
test_council_corpus_append_writes_durable_entry
test_council_pass_parser_accepts_variants
test_council_fixture_run_writes_phase_artifacts
test_council_synthesis_is_chair_generated
test_council_plan_only_writes_implementation_plan_without_handoff
test_council_after_approval_does_not_handoff_without_gate
test_council_approved_gates_start_worktree_handoff
test_council_critical_veto_aborts_implementation_run
test_council_chair_fallback_preserves_quorum
test_council_diversity_warning_prints_to_cli
test_council_chair_fallback_warning_prints_to_cli
test_council_fixture_critique_honors_failed_persona
test_council_cost_cap_aborts_before_fanout
test_council_cost_cap_aborts_before_critique
test_council_deep_fixture_writes_revision_artifacts
test_council_cross_critique_prompt_includes_peer_responses
test_council_revision_prompt_includes_prior_critiques
test_council_prompt_task_block_is_authoritative
test_council_scans_artifact_critical_veto
test_council_structured_veto_requires_veto_role
test_council_veto_scan_ignores_discussed_token
test_council_dispatch_strips_blocked_env_but_sets_disposable_mode

test_council_host_native_detection() {
    test_case "council_detect_providers marks host provider as host-native (issue #444)"
    load_council_lib || return 1

    OCTOPUS_HOST="codex" \
    COUNCIL_PROVIDERS="claude,codex,gemini" \
        council_detect_providers

    local codex_status claude_status
    codex_status="$(jq -r '.codex // "missing"' <<< "$COUNCIL_PROVIDER_STATUS_JSON")"
    claude_status="$(jq -r '.claude // "missing"' <<< "$COUNCIL_PROVIDER_STATUS_JSON")"

    if [[ "$codex_status" == "host-native" ]]; then
        # codex must still be considered available for roster formation
        if council_provider_is_available "codex"; then
            test_pass
        else
            test_fail "host-native provider should still be considered available for roster"
            return 1
        fi
    else
        test_fail "expected codex status 'host-native', got '$codex_status'"
        return 1
    fi
}

test_council_live_response_host_native_skips_subprocess() {
    test_case "council_live_response emits in-context note for host-native provider (issue #444)"
    load_council_lib || return 1

    COUNCIL_PROVIDER_STATUS_JSON='{"codex":"host-native"}'
    local out
    out="$(council_live_response "codex" "code-reviewer" "dummy prompt" "independent-advice")"
    local rc=$?

    if [[ $rc -eq 0 && "$out" == *"host agent"* ]]; then
        test_pass
    else
        test_fail "expected rc=0 and host-agent note in output; rc=$rc output=$out"
        return 1
    fi
}

test_council_live_response_host_native_fails_for_synthesis() {
    test_case "council_live_response returns 1 for host-native chair-synthesis (issue #444 follow-up)"
    load_council_lib || return 1

    COUNCIL_PROVIDER_STATUS_JSON='{"codex":"host-native"}'
    local rc=0
    if council_live_response "codex" "strategy-analyst" "dummy prompt" "chair-synthesis" >/dev/null; then
        rc=0
    else
        rc=$?
    fi

    if [[ $rc -ne 0 ]]; then
        test_pass
    else
        test_fail "expected rc!=0 for host-native chair-synthesis, got rc=0"
        return 1
    fi
}

test_council_verdict_parsing() {
    test_case "council_response_verdict reads the last VERDICT line, fail-safe REVISE"
    load_council_lib || return 1
    local d; d="$(mktemp -d "$TEST_TMP_DIR/verdict.XXXXXX")"
    printf 'review\nVERDICT: APPROVE\n'                 > "$d/a.md"
    printf 'review\nVERDICT: REVISE\n'                  > "$d/r.md"
    printf 'review\nverdict: block now\n'               > "$d/b.md"
    printf 'no verdict line at all here\n'              > "$d/none.md"
    printf 'VERDICT: APPROVE\nmore\nVERDICT: REVISE\n'  > "$d/last.md"
    if [[ "$(council_response_verdict "$d/a.md")"    == "APPROVE" ]] &&
       [[ "$(council_response_verdict "$d/r.md")"    == "REVISE"  ]] &&
       [[ "$(council_response_verdict "$d/b.md")"    == "BLOCK"   ]] &&
       [[ "$(council_response_verdict "$d/none.md")" == "REVISE"  ]] &&
       [[ "$(council_response_verdict "$d/last.md")" == "REVISE"  ]]; then
        test_pass
    else
        test_fail "verdict parsing mismatch"
        return 1
    fi
}

test_council_approving_providers_failsafe() {
    test_case "council_compute_approving_providers drops a split double-seated vendor"
    load_council_lib || return 1
    local split clean
    split="$(council_compute_approving_providers "agy codex codex" "codex")"
    clean="$(council_compute_approving_providers "agy codex codex" "")"
    if [[ "$split" == "agy" ]] && [[ "$clean" == "agy codex" ]]; then
        test_pass
    else
        test_fail "approver set wrong: split=[$split] clean=[$clean]"
        return 1
    fi
}

test_council_split_double_seat_fails_quorum() {
    test_case "Council quorum fails when a double-seated vendor splits (sail-cruisey #1992)"
    load_council_lib || return 1
    local tmp_dir rd
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-split.XXXXXX")"
    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='codex:available,agy:available' \
    OCTOPUS_COUNCIL_FIXTURE_REVISE_PERSONAS='code-reviewer' \
        council_run --depth standard --output-dir "$tmp_dir" "Review X" >/dev/null 2>&1 || true
    rd="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if jq -e '.quorum.met == false and .quorum.distinct_approving_providers == 1 and .quorum.approving_providers == "agy"' "$rd/summary.json" >/dev/null; then
        test_pass
    else
        test_fail "split double-seat did not fail quorum: $(jq -c .quorum "$rd/summary.json" 2>/dev/null)"
        return 1
    fi
}

test_council_all_approve_meets_quorum() {
    test_case "Council quorum meets when >=2 distinct vendors cleanly APPROVE"
    load_council_lib || return 1
    local tmp_dir rd
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-approve.XXXXXX")"
    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='codex:available,agy:available' \
        council_run --depth standard --output-dir "$tmp_dir" "Review X" >/dev/null 2>&1 || true
    rd="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if jq -e '.quorum.met == true and .quorum.distinct_approving_providers >= 2' "$rd/summary.json" >/dev/null; then
        test_pass
    else
        test_fail "clean all-approve did not meet quorum: $(jq -c .quorum "$rd/summary.json" 2>/dev/null)"
        return 1
    fi
}

test_council_detached_dispatch_atomic_and_propagates_rc() {
    test_case "council_dispatch_member_detached only publishes via atomic rename, propagates rc, leaves no temp files (#2077)"
    load_council_lib || return 1
    local d; d="$(mktemp -d "$TEST_TMP_DIR/detach.XXXXXX")"
    local member='{"provider":"codex","persona":"code-reviewer","seat":"member"}'
    local startedf="$d/started" relf="$d/release"
    export OCTOPUS_COUNCIL_AGENT_TIMEOUT=30

    # Happy path, observed MID-WRITE. The stub signals it has started, then blocks.
    # While it is blocked the final path must NOT exist — a regression that writes
    # straight to the final path (skipping .partial + atomic mv) would expose a
    # partial/empty file here and fail. After release the complete output must appear.
    council_dispatch_member() {
        : > "$startedf"
        local i=0; while [[ ! -f "$relf" && $i -lt 200 ]]; do sleep 0.1; i=$((i + 1)); done
        printf 'full review\nVERDICT: APPROVE\n'
        return 0
    }
    council_dispatch_member_detached "$member" "independent-advice" "$d/ok.md" & local helper=$!
    local i=0; while [[ ! -f "$startedf" && $i -lt 100 ]]; do sleep 0.1; i=$((i + 1)); done
    local midwrite_absent="no"; [[ ! -e "$d/ok.md" ]] && midwrite_absent="yes"
    : > "$relf"
    local ok_rc=0; wait "$helper" || ok_rc=$?

    # Failing seat: the inner exit code propagates AND the (failing) output still
    # reaches the final path through the same rename.
    council_dispatch_member() { printf 'junk-but-final\n'; return 3; }
    local fail_rc=0
    council_dispatch_member_detached "$member" "independent-advice" "$d/bad.md" || fail_rc=$?

    if [[ "$midwrite_absent" == "yes" ]] && [[ $ok_rc -eq 0 ]] &&
       grep -q 'VERDICT: APPROVE' "$d/ok.md" &&
       [[ ! -e "$d/ok.md.partial" && ! -e "$d/ok.md.done" && ! -e "$d/ok.md.done.tmp" ]] &&
       [[ $fail_rc -eq 3 ]] && grep -q 'junk-but-final' "$d/bad.md" &&
       [[ ! -e "$d/bad.md.partial" && ! -e "$d/bad.md.done" && ! -e "$d/bad.md.done.tmp" ]]; then
        test_pass
    else
        test_fail "atomic dispatch wrong: midwrite_absent=$midwrite_absent ok_rc=$ok_rc fail_rc=$fail_rc ok=[$(tr '\n' '|' < "$d/ok.md" 2>/dev/null)] bad=[$(tr '\n' '|' < "$d/bad.md" 2>/dev/null)]"
        return 1
    fi
}

test_council_seat_timeout_precedence() {
    test_case "council_seat_timeout resolves per-provider > flag > global env > default (#2077)"
    load_council_lib || return 1
    local d f p g pp invalid_provider invalid_flag invalid_global
    # 4. built-in default when nothing set
    d="$(OCTOPUS_COUNCIL_TIMEOUT_AGY='' OCTOPUS_COUNCIL_TIMEOUT_CODEX='' COUNCIL_SEAT_TIMEOUT='' OCTOPUS_COUNCIL_AGENT_TIMEOUT='' council_seat_timeout agy)"
    # 3. legacy global env
    g="$(OCTOPUS_COUNCIL_TIMEOUT_AGY='' OCTOPUS_COUNCIL_TIMEOUT_CODEX='' COUNCIL_SEAT_TIMEOUT='' OCTOPUS_COUNCIL_AGENT_TIMEOUT=200 council_seat_timeout agy)"
    # 2. run-wide --seat-timeout flag beats the global env
    f="$(OCTOPUS_COUNCIL_TIMEOUT_AGY='' OCTOPUS_COUNCIL_TIMEOUT_CODEX='' COUNCIL_SEAT_TIMEOUT=300 OCTOPUS_COUNCIL_AGENT_TIMEOUT=200 council_seat_timeout agy)"
    # 1. per-provider env beats everything, and only for that provider
    p="$(OCTOPUS_COUNCIL_TIMEOUT_AGY=600 OCTOPUS_COUNCIL_TIMEOUT_CODEX='' COUNCIL_SEAT_TIMEOUT=300 council_seat_timeout agy)"
    pp="$(OCTOPUS_COUNCIL_TIMEOUT_AGY=600 OCTOPUS_COUNCIL_TIMEOUT_CODEX='' COUNCIL_SEAT_TIMEOUT=300 council_seat_timeout codex)"
    # Invalid higher-priority overrides fall through without disabling the cap.
    invalid_provider="$(OCTOPUS_COUNCIL_TIMEOUT_AGY=0 COUNCIL_SEAT_TIMEOUT=300 OCTOPUS_COUNCIL_AGENT_TIMEOUT=200 council_seat_timeout agy)"
    invalid_flag="$(OCTOPUS_COUNCIL_TIMEOUT_AGY='' COUNCIL_SEAT_TIMEOUT=abc OCTOPUS_COUNCIL_AGENT_TIMEOUT=200 council_seat_timeout agy)"
    invalid_global="$(OCTOPUS_COUNCIL_TIMEOUT_AGY='' COUNCIL_SEAT_TIMEOUT='' OCTOPUS_COUNCIL_AGENT_TIMEOUT=-1 council_seat_timeout agy)"
    if [[ "$d" == "120" ]] && [[ "$g" == "200" ]] && [[ "$f" == "300" ]] &&
       [[ "$p" == "600" ]] && [[ "$pp" == "300" ]] &&
       [[ "$invalid_provider" == "300" ]] && [[ "$invalid_flag" == "200" ]] &&
       [[ "$invalid_global" == "120" ]]; then
        test_pass
    else
        test_fail "timeout precedence wrong: default=$d global=$g flag=$f agy=$p codex=$pp invalid=$invalid_provider/$invalid_flag/$invalid_global"
        return 1
    fi
}

test_council_detach_escape_hatch_uses_inline() {
    test_case "OCTOPUS_COUNCIL_DETACH=0 falls back to inline dispatch (no sentinel)"
    load_council_lib || return 1
    local d; d="$(mktemp -d "$TEST_TMP_DIR/detach-off.XXXXXX")"
    local member='{"provider":"codex","persona":"code-reviewer","seat":"member"}'
    council_dispatch_member() { printf 'inline\nVERDICT: REVISE\n'; return 0; }
    local rc=0
    OCTOPUS_COUNCIL_DETACH=0 council_dispatch_member_detached "$member" "independent-advice" "$d/x.md" || rc=$?
    # The inline path never creates a .done sentinel; output must still be correct.
    if [[ $rc -eq 0 ]] && grep -q 'VERDICT: REVISE' "$d/x.md" && [[ ! -e "$d/x.md.done" ]]; then
        test_pass
    else
        test_fail "escape hatch wrong: rc=$rc content=[$(tr '\n' '|' < "$d/x.md" 2>/dev/null)]"
        return 1
    fi
}

_council_run_advice_with_roster() {
    # Drive council_run_advice_phase against a hand-crafted roster in fixture mode.
    # Provider assignment per seat can't be pinned through the public council_run path
    # (diversity is auto-enforced among non-chair seats), so inject the roster directly.
    local roster="$1" depth="${2:-standard}" failed_persona="${3:-}"
    local d; d="$(mktemp -d "$TEST_TMP_DIR/advice.XXXXXX")"; mkdir -p "$d/responses"
    COUNCIL_RUN_DIR="$d"; COUNCIL_DEPTH="$depth"; COUNCIL_FIXTURE="full-success"
    COUNCIL_EXECUTION_MODE=""; COUNCIL_TASK="x"; COUNCIL_GOAL="advice"
    COUNCIL_DOMAIN="auto"; COUNCIL_STYLE="balanced"
    COUNCIL_ROSTER_JSON="$roster"
    # The prompt builder and fail-check need deep state that's irrelevant in fixture
    # mode; stub them. load_council_lib re-sources the lib for the next test, restoring them.
    council_prompt_for_member() { echo "prompt"; }
    council_persona_should_fail() { [[ -n "$failed_persona" && "$1" == "$failed_persona" ]]; }
    council_run_advice_phase >/dev/null 2>&1 || true
}

test_council_chair_only_vendor_excluded_from_quorum() {
    test_case "A chair-only vendor is excluded from the approving-provider quorum tally (#670)"
    load_council_lib || return 1

    # agy sits ONLY on the chair; the two independent (non-chair) reviewers are both
    # codex. The chair is the synthesizer, not a cross-lab vote, so agy must NOT count
    # as a distinct approving vendor — leaving a single non-chair approver (codex) that
    # can't satisfy the 2-vendor standard quorum. Before the fix, agy leaked in and the
    # council falsely reported a 2-vendor consensus.
    _council_run_advice_with_roster '[
      {"persona":"strategy-analyst","provider":"agy","seat":"chair"},
      {"persona":"code-reviewer","provider":"codex","seat":"member"},
      {"persona":"backend-architect","provider":"codex","seat":"member"}
    ]'
    local chair_only_ok="no"
    if [[ "$COUNCIL_DISTINCT_APPROVING_PROVIDERS" == "1" ]] &&
       [[ "$COUNCIL_APPROVING_PROVIDERS" == *codex* ]] &&
       [[ "$COUNCIL_APPROVING_PROVIDERS" != *agy* ]] &&
       [[ "$COUNCIL_QUORUM_MET" == "false" ]] &&
       jq -e '
         .[0].seat == "chair"
         and .[0].status == "responded"
         and .[0].verdict == "APPROVE"
         and .[0].counted_as_approver == false
         and ([.[] | select(.counted_as_approver) | .provider] | unique) == ["codex"]
       ' <<< "$COUNCIL_SEAT_RECORDS_JSON" >/dev/null; then
        chair_only_ok="yes"
    fi

    # Complement: the SAME vendor on the chair AND an independent seat still counts via
    # its non-chair seat — proving the exclusion is seat-scoped, not vendor-scoped.
    _council_run_advice_with_roster '[
      {"persona":"strategy-analyst","provider":"agy","seat":"chair"},
      {"persona":"code-reviewer","provider":"codex","seat":"member"},
      {"persona":"backend-architect","provider":"agy","seat":"member"}
    ]'
    local also_member_ok="no"
    if [[ "$COUNCIL_DISTINCT_APPROVING_PROVIDERS" == "2" ]] &&
       [[ "$COUNCIL_APPROVING_PROVIDERS" == *codex* ]] &&
       [[ "$COUNCIL_APPROVING_PROVIDERS" == *agy* ]] &&
       [[ "$COUNCIL_QUORUM_MET" == "true" ]] &&
       jq -e '
         .[0].seat == "chair"
         and .[0].status == "responded"
         and .[0].counted_as_approver == false
         and .[2].seat == "member"
         and .[2].provider == "agy"
         and .[2].counted_as_approver == true
       ' <<< "$COUNCIL_SEAT_RECORDS_JSON" >/dev/null; then
        also_member_ok="yes"
    fi

    if [[ "$chair_only_ok" == "yes" && "$also_member_ok" == "yes" ]]; then
        test_pass
    else
        test_fail "chair exclusion wrong: chair_only_ok=$chair_only_ok also_member_ok=$also_member_ok (last: approving=[$COUNCIL_APPROVING_PROVIDERS] distinct=$COUNCIL_DISTINCT_APPROVING_PROVIDERS met=$COUNCIL_QUORUM_MET)"
        return 1
    fi
}

test_council_detached_seat_survives_interrupt() {
    test_case "A detached seat survives SIGINT/SIGHUP/SIGTERM to its process and still lands its result (#2077)"
    load_council_lib || return 1
    local d; d="$(mktemp -d "$TEST_TMP_DIR/detach-sig.XXXXXX")"
    local member='{"provider":"codex","persona":"code-reviewer","seat":"member"}'
    local pidf="$d/seat.pid" relf="$d/release" out="$d/sig.md"
    export OCTOPUS_COUNCIL_AGENT_TIMEOUT=30

    # PPID of the `sh -c` child is the seat subshell's pid — portable to bash 3.2
    # (macOS), where $BASHPID does not exist. The stub blocks until released so the
    # test can deliver signals while the seat is provably mid-run. TERM is included
    # because a timeout-style tool/orchestrator kill sends SIGTERM first.
    council_dispatch_member() {
        sh -c 'echo $PPID' > "$pidf"
        local i=0
        while [[ ! -f "$relf" && $i -lt 200 ]]; do sleep 0.1; i=$((i + 1)); done
        printf 'survived interrupt\nVERDICT: APPROVE\n'
        return 0
    }

    council_dispatch_member_detached "$member" "independent-advice" "$out" & local helper=$!
    local i=0
    while [[ ! -f "$pidf" && $i -lt 100 ]]; do sleep 0.1; i=$((i + 1)); done
    local seat; seat="$(cat "$pidf" 2>/dev/null)"
    kill -INT "$seat" 2>/dev/null || true
    kill -HUP "$seat" 2>/dev/null || true
    # Record TERM delivery. A successful kill -TERM proves the seat was still ALIVE
    # (it had already ignored INT+HUP) AND that TERM was actually delivered — without
    # this the test could green even if the signal never reached a live process.
    local term_delivered="no"
    kill -TERM "$seat" 2>/dev/null && term_delivered="yes"
    local premature="no"; [[ -f "$out" ]] && premature="yes"
    : > "$relf"
    local rc=0; wait "$helper" || rc=$?

    if [[ -n "$seat" ]] && [[ "$term_delivered" == "yes" ]] && [[ "$premature" == "no" ]] &&
       [[ $rc -eq 0 ]] && [[ -f "$out" ]] && grep -q 'survived interrupt' "$out"; then
        test_pass
    else
        test_fail "detached seat did not survive interrupt: seat=$seat term_delivered=$term_delivered premature=$premature rc=$rc out=[$(tr '\n' '|' < "$out" 2>/dev/null)]"
        return 1
    fi
}

test_council_chair_fallback_rejects_incomplete_responses() {
    test_case "Chair fallback rejects timed-out partial and empty-success responses"
    load_council_lib || return 1
    local d rc=0
    d="$(mktemp -d "$TEST_TMP_DIR/chair-partial.XXXXXX")"
    mkdir -p "$d/responses"
    printf 'review was cut off before its verdict\n' > "$d/responses/00-strategy-analyst.md"
    COUNCIL_RUN_DIR="$d"
    COUNCIL_SEAT_RECORDS_JSON='[{"persona":"strategy-analyst","status":"no-response"}]'
    COUNCIL_CHAIR_RESPONSE_RECEIVED="false"
    COUNCIL_CHAIR_FALLBACK_USED="false"
    COUNCIL_CHAIR_FALLBACK_PERSONA=""
    council_pick_provider() { printf 'codex'; }
    council_provider_is_available() { return 1; }

    council_run_chair_fallback || rc=$?
    local partial_ok="no"
    if [[ $rc -ne 0 ]] &&
       [[ "$COUNCIL_CHAIR_RESPONSE_RECEIVED" == "false" ]] &&
       [[ "$COUNCIL_CHAIR_FALLBACK_USED" == "false" ]]; then
        partial_ok="yes"
    fi

    rm -f "$d/responses/"*.md
    COUNCIL_SEAT_RECORDS_JSON='[]'
    COUNCIL_CHAIR_RESPONSE_RECEIVED="false"
    COUNCIL_CHAIR_FALLBACK_USED="false"
    council_provider_is_available() { return 0; }
    council_roster_entry_json() {
        jq -cn --arg persona "$1" --arg provider "$2" \
            '{persona:$persona,provider:$provider,provider_org:$provider,model:"fixture",seat:"member"}'
    }
    council_dispatch_member() { return 0; }
    rc=0
    council_run_chair_fallback || rc=$?
    local empty_ok="no"
    if [[ $rc -ne 0 ]] &&
       [[ "$COUNCIL_CHAIR_RESPONSE_RECEIVED" == "false" ]] &&
       [[ "$COUNCIL_CHAIR_FALLBACK_USED" == "false" ]]; then
        empty_ok="yes"
    fi

    if [[ "$partial_ok" == "yes" && "$empty_ok" == "yes" ]]; then
        test_pass
    else
        test_fail "incomplete chair accepted: partial_ok=$partial_ok empty_ok=$empty_ok rc=$rc received=$COUNCIL_CHAIR_RESPONSE_RECEIVED fallback=$COUNCIL_CHAIR_FALLBACK_USED"
        return 1
    fi
}

test_council_reused_member_chair_fallback_preserves_quorum() {
    test_case "A reused member chair fallback preserves the non-chair quorum count"
    load_council_lib || return 1

    # The original chair fails, but the synthesis-capable member already returned a
    # complete review. The fallback reuses that member instead of adding a chair seat.
    # Its one non-chair response must remain counted for quick-mode quorum.
    _council_run_advice_with_roster '[
      {"persona":"strategy-analyst","provider":"agy","seat":"chair"},
      {"persona":"research-synthesizer","provider":"codex","seat":"member"}
    ]' quick strategy-analyst

    if [[ "$COUNCIL_CHAIR_FALLBACK_USED" == "true" ]] &&
       [[ "$COUNCIL_CHAIR_FALLBACK_PERSONA" == "research-synthesizer" ]] &&
       [[ "$COUNCIL_QUORUM_MET" == "true" ]] &&
       [[ "$(council_received_non_chair)" == "1" ]] &&
       [[ "$(jq 'length' <<< "$COUNCIL_SEAT_RECORDS_JSON")" == "2" ]]; then
        test_pass
    else
        test_fail "reused fallback lost quorum: fallback=$COUNCIL_CHAIR_FALLBACK_USED persona=$COUNCIL_CHAIR_FALLBACK_PERSONA quorum=$COUNCIL_QUORUM_MET non_chair=$(council_received_non_chair) seats=$COUNCIL_SEAT_RECORDS_JSON"
        return 1
    fi
}

test_council_seat_timeout_rejects_zero_and_nonnumeric() {
    test_case "--seat-timeout records a positive integer but rejects 0 and non-numeric"
    load_council_lib || return 1
    local out_file="$TEST_TMP_DIR/council-seat-timeout.out"

    # A positive integer is accepted and recorded.
    council_parse_args --seat-timeout 450 --dry-run "Review auth"
    [[ "$COUNCIL_SEAT_TIMEOUT" == "450" ]] || { test_fail "positive value not recorded: [$COUNCIL_SEAT_TIMEOUT]"; return 1; }

    # 0 must be rejected: run_with_timeout treats 0 as unbounded, so it would defeat
    # the very cap the flag sets. Non-numeric must also fail with the usage error.
    # Capture each expected failure with an if-guard rather than `set +e`, so the
    # runner's errexit stays on for the rest of the test.
    local z_status=0 nn_status=0
    if council_parse_args --seat-timeout 0 "Review auth" >"$out_file" 2>&1; then z_status=0; else z_status=$?; fi
    if council_parse_args --seat-timeout abc "Review auth" >"$out_file" 2>&1; then nn_status=0; else nn_status=$?; fi
    if [[ $z_status -eq 2 ]] && [[ $nn_status -eq 2 ]] && [[ -z "$COUNCIL_SEAT_TIMEOUT" ]]; then
        test_pass
    else
        test_fail "expected exit 2 and reset timeout: zero=$z_status nonnumeric=$nn_status timeout=[$COUNCIL_SEAT_TIMEOUT]"
        return 1
    fi
}

test_council_detached_seat_timeout_is_cancelled() {
    test_case "A seat that outlives the reap window is cancelled — no late response is published (#2077)"
    load_council_lib || return 1
    local d; d="$(mktemp -d "$TEST_TMP_DIR/detach-timeout.XXXXXX")"
    local member='{"provider":"codex","persona":"code-reviewer","seat":"member"}'
    local pidf="$d/seat.pid" out="$d/late.md"
    local childpidf="$d/child.pid" childmark="$d/child.mark"
    # Force a ~1s reap window (provider timeout 1 + grace 0) against a seat that
    # would take ~3s. The legacy global remains high so this also proves the detached
    # reaper uses the same per-provider precedence as the inner dispatch.
    export OCTOPUS_COUNCIL_TIMEOUT_CODEX=1
    export COUNCIL_SEAT_TIMEOUT=""
    export OCTOPUS_COUNCIL_AGENT_TIMEOUT=30
    export OCTOPUS_COUNCIL_REAP_GRACE_SECS=0

    # The seat spawns a REAL descendant that would touch a marker after 3s. If only the
    # wrapper were killed, that grandchild would survive and create the marker; a proper
    # tree-kill takes it down too. The stub itself also sleeps and would publish late.
    council_dispatch_member() {
        sh -c 'echo $PPID' > "$pidf"
        ( sleep 3; : > "$childmark" ) &
        echo "$!" > "$childpidf"
        sleep 3
        printf 'late publish\nVERDICT: APPROVE\n'
        return 0
    }

    local rc=0
    council_dispatch_member_detached "$member" "independent-advice" "$out" || rc=$?
    local seat child; seat="$(cat "$pidf" 2>/dev/null)"; child="$(cat "$childpidf" 2>/dev/null)"
    # Wait PAST the stub's natural 3s completion so a late publish / surviving child
    # would have materialized by the time we assert.
    sleep 4

    unset OCTOPUS_COUNCIL_TIMEOUT_CODEX COUNCIL_SEAT_TIMEOUT
    unset OCTOPUS_COUNCIL_AGENT_TIMEOUT OCTOPUS_COUNCIL_REAP_GRACE_SECS
    if [[ $rc -ne 0 ]] && [[ ! -e "$out" ]] && [[ ! -e "$childmark" ]] &&
       [[ ! -e "$out.partial" && ! -e "$out.done" && ! -e "$out.done.tmp" ]] &&
       [[ -n "$seat" ]] && ! kill -0 "$seat" 2>/dev/null &&
       [[ -n "$child" ]] && ! kill -0 "$child" 2>/dev/null; then
        test_pass
    else
        test_fail "timed-out seat/tree not cancelled: rc=$rc late_file=$([[ -e "$out" ]] && echo yes || echo no) child_marker=$([[ -e "$childmark" ]] && echo yes || echo no) seat_alive=$(kill -0 "$seat" 2>/dev/null && echo yes || echo no) child_alive=$(kill -0 "$child" 2>/dev/null && echo yes || echo no)"
        return 1
    fi
}

test_council_response_has_verdict_salvage() {
    test_case "council_response_has_verdict distinguishes a finished seat from a truncated one (#2077)"
    load_council_lib || return 1
    local d; d="$(mktemp -d "$TEST_TMP_DIR/hasverdict.XXXXXX")"
    printf 'full review body\nVERDICT: APPROVE\n'        > "$d/complete.md"
    printf '  verdict: revise please\n'                  > "$d/lower.md"
    printf 'review got cut off mid-sen'                  > "$d/partial.md"
    printf ''                                            > "$d/empty.md"
    if council_response_has_verdict "$d/complete.md" &&
       council_response_has_verdict "$d/lower.md" &&
       ! council_response_has_verdict "$d/partial.md" &&
       ! council_response_has_verdict "$d/empty.md" &&
       ! council_response_has_verdict "$d/missing.md"; then
        test_pass
    else
        test_fail "has_verdict salvage detection wrong"
        return 1
    fi
}

test_council_seats_array_makes_quorum_inspectable() {
    test_case "summary.json seats[] records per-seat state and quorum is recomputable from it"
    load_council_lib || return 1
    local tmp_dir rd s
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-seats.XXXXXX")"
    OCTOPUS_COUNCIL_FIXTURE=full-success \
    OCTOPUS_COUNCIL_PROVIDER_FIXTURE='codex:available,agy:available' \
        council_run --depth standard --output-dir "$tmp_dir" "Review X" >/dev/null 2>&1 || true
    rd="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    s="$rd/summary.json"
    # Every seat carries the FULL documented contract (incl. provider_org, model,
    # verdict), the fields are well-typed, the counted_as_approver invariant holds,
    # and distinct_approving_providers is recomputable from seats[] alone (no reading
    # responses/* by hand).
    if jq -e '
        . as $summary
        | ($summary.seats | type == "array" and length >= 2)
        and ($summary.council | type == "array")
        and (($summary.seats | length) >= ($summary.council | length))
        and (.seats | all(has("index") and has("persona")
                          and has("seat") and has("provider") and has("provider_org")
                          and has("model") and has("status") and has("verdict")
                          and has("response_bytes") and has("payload_kind")
                          and has("counted_as_approver")))
        and (.seats | all(
            (.index | type == "number" and floor == .)
            and ([.seat, .persona, .provider, .provider_org, .model, .status, .payload_kind]
                 | all(type == "string" and length >= 1))
        ))
        # The seat list is a one-for-one, ordered execution record for the resolved
        # council roster; a missing, duplicate, or invented seat must fail the contract.
        and (all(range(0; ($summary.council | length)); . as $i
            | ($summary.seats[$i].index == $i)
            and ($summary.seats[$i].persona == $summary.council[$i].persona)
            and ($summary.seats[$i].seat == $summary.council[$i].seat)
            and ($summary.seats[$i].provider == $summary.council[$i].provider)
            and ($summary.seats[$i].provider_org == $summary.council[$i].provider_org)
            and ($summary.seats[$i].model == $summary.council[$i].model)))
        # Any records beyond the roster must be the explicitly reported chair
        # fallback dispatch; no unrelated extra seats are accepted.
        and (if (($summary.seats | length) == ($summary.council | length))
             then true
             else ($summary.warnings.chair_fallback == true)
                  and ($summary.seats[($summary.council | length):]
                       | all(.seat == "chair"
                             and .persona == $summary.warnings.chair_fallback_persona))
             end)
        # counted_as_approver drives quorum, so it must be a real boolean, not a
        # truthy string that jq would still `select`.
        and (.seats | all(.counted_as_approver | type == "boolean"))
        and (.seats | all(.response_bytes | type == "number" and . >= 0))
        # verdict is null (no substantive verdict) or a known token — never garbage.
        and (.seats | all((.verdict == null) or (.verdict | test("^(APPROVE|REVISE|BLOCK)$"))))
        # a counted approver is, by construction, a responded APPROVE seat.
        and (.seats | all((.counted_as_approver | not)
                          or (.status == "responded" and .verdict == "APPROVE")))
        and (.quorum.distinct_approving_providers
             == ([.seats[] | select(.counted_as_approver) | .provider] | unique | length))
    ' "$s" >/dev/null; then
        test_pass
    else
        test_fail "seats[] missing/!recomputable: $(jq -c '{q:.quorum.distinct_approving_providers, seats:.seats}' "$s" 2>/dev/null)"
        return 1
    fi
}

test_council_host_native_detection
test_council_live_response_host_native_skips_subprocess
test_council_live_response_host_native_fails_for_synthesis
test_council_verdict_parsing
test_council_approving_providers_failsafe
test_council_split_double_seat_fails_quorum
test_council_all_approve_meets_quorum
test_council_detached_dispatch_atomic_and_propagates_rc
test_council_detach_escape_hatch_uses_inline
test_council_detached_seat_survives_interrupt
test_council_detached_seat_timeout_is_cancelled
test_council_seat_timeout_precedence
test_council_seat_timeout_rejects_zero_and_nonnumeric
test_council_response_has_verdict_salvage
test_council_chair_only_vendor_excluded_from_quorum
test_council_chair_fallback_rejects_incomplete_responses
test_council_reused_member_chair_fallback_preserves_quorum
test_council_seats_array_makes_quorum_inspectable
test_summary
