#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# factory.sh — Dark Factory functions extracted from orchestrate.sh
# Functions: factory_run, split_holdout_scenarios, run_holdout_tests
# ═══════════════════════════════════════════════════════════════════════════════

split_holdout_scenarios() {
    local scenarios_file="$1"
    local run_dir="$2"
    local holdout_ratio="${3:-$OCTOPUS_FACTORY_HOLDOUT_RATIO}"

    if [[ ! -f "$scenarios_file" ]]; then
        log ERROR "Scenarios file not found: $scenarios_file"
        return 1
    fi

    local all_scenarios
    all_scenarios=$(<"$scenarios_file")

    # Extract individual scenarios (split on "### Scenario")
    local scenario_blocks=()
    local current_block=""
    local in_scenario=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^###\ Scenario ]]; then
            if [[ -n "$current_block" ]]; then
                scenario_blocks+=("$current_block")
            fi
            current_block="$line"
            in_scenario=true
        elif [[ "$in_scenario" == true ]]; then
            current_block="${current_block}
${line}"
        fi
    done <<< "$all_scenarios"
    # Capture last block
    if [[ -n "$current_block" ]]; then
        scenario_blocks+=("$current_block")
    fi

    local total=${#scenario_blocks[@]}
    if [[ $total -eq 0 ]]; then
        log WARN "No scenario blocks found, treating entire file as single scenario set"
        cp "$scenarios_file" "$run_dir/scenarios-visible.md"
        echo "# No structured scenarios to holdout" > "$run_dir/scenarios-holdout.md"
        return 0
    fi

    # Calculate holdout count (minimum 1 if there are scenarios, max 20%)
    local holdout_count
    holdout_count=$(echo "$total $holdout_ratio" | awk '{printf "%d", $1 * $2 + 0.5}')
    if [[ $holdout_count -lt 1 && $total -gt 1 ]]; then
        holdout_count=1
    fi
    if [[ $holdout_count -ge $total ]]; then
        holdout_count=$(( total > 1 ? 1 : 0 ))
    fi

    local visible_count=$(( total - holdout_count ))

    log INFO "Splitting scenarios: $total total, $visible_count visible, $holdout_count holdout (ratio=$holdout_ratio)"

    # Deterministic shuffle using scenario index modulo for reproducibility
    # Holdout picks scenarios spread across types for coverage diversity
    local holdout_indices=()
    local step=$(( total / (holdout_count > 0 ? holdout_count : 1) ))
    if [[ $step -lt 1 ]]; then step=1; fi

    local idx=0
    for (( i=0; i<holdout_count; i++ )); do
        idx=$(( (i * step + step / 2) % total ))
        holdout_indices+=("$idx")
    done

    # Write visible and holdout files
    local visible_content="# Factory Visible Scenarios ($visible_count of $total)
"
    local holdout_content="# Factory Holdout Scenarios ($holdout_count of $total)
"

    for (( i=0; i<total; i++ )); do
        local is_holdout=false
        for hi in "${holdout_indices[@]}"; do
            if [[ $i -eq $hi ]]; then
                is_holdout=true
                break
            fi
        done

        if [[ "$is_holdout" == true ]]; then
            holdout_content="${holdout_content}
${scenario_blocks[$i]}
"
        else
            visible_content="${visible_content}
${scenario_blocks[$i]}
"
        fi
    done

    echo "$visible_content" > "$run_dir/scenarios-visible.md"
    echo "$holdout_content" > "$run_dir/scenarios-holdout.md"

    log INFO "Split complete: $run_dir/scenarios-visible.md ($visible_count), $run_dir/scenarios-holdout.md ($holdout_count)"
}

run_holdout_tests() {
    local run_dir="$1"
    local holdout_file="$run_dir/scenarios-holdout.md"

    if [[ ! -f "$holdout_file" ]]; then
        log WARN "No holdout file found, skipping holdout evaluation"
        echo "1.00"
        return 0
    fi

    local holdout_content
    holdout_content=$(<"$holdout_file")

    # If no real holdout scenarios, score perfect
    if [[ "$holdout_content" == *"No structured scenarios to holdout"* ]]; then
        log INFO "No holdout scenarios to evaluate"
        echo "1.00"
        return 0
    fi

    log INFO "Running holdout tests against implementation..."

    # Gather implementation context (recent files modified)
    local impl_context=""
    local recent_files
    recent_files=$(git diff --name-only HEAD~5 HEAD 2>/dev/null | head -20) || true
    if [[ -n "$recent_files" ]]; then
        impl_context="Recently modified files:
$recent_files"
    fi

    local holdout_prompt="You are a QA reviewer evaluating whether an implementation satisfies test scenarios.

## Holdout Test Scenarios (these were NOT visible during implementation)
${holdout_content:0:4000}

## Implementation Context
${impl_context:0:3000}

For EACH scenario, evaluate:
- **PASS**: Implementation clearly satisfies the scenario
- **PARTIAL**: Implementation partially addresses the scenario
- **FAIL**: Implementation does not address the scenario

Output format:
### Scenario N: <title>
**Verdict:** PASS | PARTIAL | FAIL
**Evidence:** <brief explanation>

After all scenarios, output:
## Summary
- Total: N
- Pass: N
- Partial: N
- Fail: N
- Score: X.XX (PASS=1.0, PARTIAL=0.5, FAIL=0.0, averaged)"

    # Cross-model holdout evaluation for objectivity
    local eval_result
    eval_result=$(run_agent_sync "gemini" "$holdout_prompt" 180 "qa-reviewer" "factory" 2>/dev/null) || true

    if [[ -z "$eval_result" ]]; then
        eval_result=$(run_agent_sync "codex" "$holdout_prompt" 180 "qa-reviewer" "factory" 2>/dev/null) || true
    fi

    if [[ -z "$eval_result" ]]; then
        eval_result=$(run_agent_sync "claude" "$holdout_prompt" 180 "qa-reviewer" "factory" 2>/dev/null) || true
    fi

    if [[ -z "$eval_result" ]]; then
        log WARN "Holdout evaluation failed from all providers, defaulting to 0.50"
        echo "0.50"
        return 0
    fi

    echo "$eval_result" > "$run_dir/holdout-results.md"

    # Extract score from evaluation
    local holdout_score
    holdout_score=$(echo "$eval_result" | grep -oi 'score[: ]*[0-9]*\.[0-9]*' | tail -1 | grep -o '[0-9]*\.[0-9]*' || echo "")

    if [[ -z "$holdout_score" ]]; then
        # Fallback: count PASS/PARTIAL/FAIL verdicts
        local pass_count partial_count fail_count total_count
        pass_count=$(echo "$eval_result" | grep -ci 'verdict.*pass' || echo "0")
        partial_count=$(echo "$eval_result" | grep -ci 'verdict.*partial' || echo "0")
        fail_count=$(echo "$eval_result" | grep -ci 'verdict.*fail' || echo "0")
        total_count=$(( pass_count + partial_count + fail_count ))

        if [[ $total_count -gt 0 ]]; then
            holdout_score=$(echo "$pass_count $partial_count $total_count" | awk '{printf "%.2f", ($1 + $2 * 0.5) / $3}')
        else
            holdout_score="0.50"
        fi
    fi

    log INFO "Holdout test score: $holdout_score"
    echo "$holdout_score"
}

factory_run() {
    local spec_path="$1"
    local holdout_ratio="${2:-$OCTOPUS_FACTORY_HOLDOUT_RATIO}"
    local max_retries="${3:-$OCTOPUS_FACTORY_MAX_RETRIES}"
    local ci_mode="${4:-false}"

    # Validate spec exists
    if [[ ! -f "$spec_path" ]]; then
        log ERROR "Spec file not found: $spec_path"
        echo "Usage: $(basename "$0") factory --spec <path-to-spec.md>"
        return 1
    fi

    # ── Pre-flight: Specification Maturity Assessment (E27) ──────────────
    local maturity_result maturity_level maturity_sections maturity_json
    maturity_result=$(assess_spec_maturity "$spec_path")
    maturity_level=$(echo "$maturity_result" | cut -d'|' -f1)
    maturity_sections=$(echo "$maturity_result" | cut -d'|' -f2)
    maturity_json=$(echo "$maturity_result" | cut -d'|' -f3)

    if [[ "$maturity_level" == "Skeleton" ]]; then
        log ERROR "Spec maturity too low: $maturity_level ($maturity_sections/6 sections)"
        echo -e "${RED}  ✗ Maturity: $maturity_level ($maturity_sections/6 sections)${NC}"
        echo "  Factory requires at least Draft level. Use /octo:spec to develop the specification."
        return 1
    fi

    if [[ "$maturity_level" == "Draft" ]]; then
        log WARN "Spec maturity is Draft ($maturity_sections/6 sections) — results may be limited"
    fi

    # Create run directory
    local run_id
    run_id="factory-$(date +%Y%m%d-%H%M%S)"
    local run_dir=".octo/factory/$run_id"
    mkdir -p "$run_dir"

    echo ""
    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    echo -e "${MAGENTA}║  ${GREEN}DARK FACTORY${MAGENTA} — Spec-In, Software-Out Pipeline            ║${NC}"
    echo -e "${MAGENTA}║  Parse → Scenarios → Embrace → Holdout → Score → Report  ║${NC}"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""
    echo -e "${CYAN}  Run ID:    ${NC}$run_id"
    echo -e "${CYAN}  Spec:      ${NC}$spec_path"
    echo -e "${CYAN}  Maturity:  ${NC}$maturity_level ($maturity_sections/6 sections)"
    echo -e "${CYAN}  Holdout:   ${NC}${holdout_ratio} ($(echo "$holdout_ratio" | awk '{printf "%d", $1 * 100}')%)"
    echo -e "${CYAN}  Retries:   ${NC}$max_retries"
    echo ""

    # ── Phase 1: Parse spec ──────────────────────────────────────────────
    echo -e "${YELLOW}[1/7]${NC} Parsing factory spec..."
    local satisfaction_target
    satisfaction_target=$(parse_factory_spec "$spec_path" "$run_dir")
    if [[ $? -ne 0 || -z "$satisfaction_target" ]]; then
        log ERROR "Failed to parse factory spec"
        return 1
    fi
    echo -e "${GREEN}  ✓${NC} Satisfaction target: $satisfaction_target"

    # ── Phase 1b: NQS Quality Score (E25) ────────────────────────────────
    echo -e "${YELLOW}[1b/7]${NC} Scoring spec quality (NQS)..."
    local nqs_result nqs_score nqs_verdict
    nqs_result=$(score_nlspec_quality "$spec_path" "$run_dir")
    nqs_score=$(echo "$nqs_result" | cut -d'|' -f1)
    nqs_verdict=$(echo "$nqs_result" | cut -d'|' -f2)

    if [[ "$nqs_verdict" == "FAIL" ]]; then
        echo -e "${RED}  ✗ NQS Score: ${nqs_score}/100 (minimum 85 required)${NC}"
        echo "  Spec quality too low for autonomous execution. Use /octo:spec to improve."
        log ERROR "NQS gate failed: $nqs_score/100"
        return 1
    elif [[ "$nqs_verdict" == "WARN" ]]; then
        echo -e "${YELLOW}  ⚠ NQS Score: ${nqs_score}/100 (proceeding with caution)${NC}"
    else
        echo -e "${GREEN}  ✓${NC} NQS Score: ${nqs_score}/100"
    fi

    # Cost estimate and approval gate
    if [[ "$ci_mode" != "true" ]]; then
        display_workflow_cost_estimate "factory" 8 6 4000 2>/dev/null || true
    fi

    # ── Phase 2: Generate scenarios ──────────────────────────────────────
    echo ""
    echo -e "${YELLOW}[2/7]${NC} Generating test scenarios from spec..."
    local scenarios
    scenarios=$(generate_factory_scenarios "$spec_path" "$run_dir")
    if [[ $? -ne 0 || -z "$scenarios" ]]; then
        log ERROR "Scenario generation failed"
        return 1
    fi
    local scenario_count
    scenario_count=$(grep -c '### Scenario' "$run_dir/scenarios-all.md" || echo "0")
    echo -e "${GREEN}  ✓${NC} Generated $scenario_count scenarios"

    # ── Phase 3: Split holdout ───────────────────────────────────────────
    echo ""
    echo -e "${YELLOW}[3/7]${NC} Splitting holdout scenarios (${holdout_ratio})..."
    split_holdout_scenarios "$run_dir/scenarios-all.md" "$run_dir" "$holdout_ratio"
    local visible_count holdout_count
    visible_count=$(grep -c '### Scenario' "$run_dir/scenarios-visible.md" 2>/dev/null || echo "0")
    holdout_count=$(grep -c '### Scenario' "$run_dir/scenarios-holdout.md" 2>/dev/null || echo "0")
    echo -e "${GREEN}  ✓${NC} Visible: $visible_count, Holdout: $holdout_count"

    # ── Phase 4: Embrace workflow ────────────────────────────────────────
    echo ""
    echo -e "${YELLOW}[4/7]${NC} Running embrace workflow (4-phase implementation)..."

    # Build augmented prompt with visible scenarios
    local visible_scenarios=""
    [[ -f "$run_dir/scenarios-visible.md" ]] && visible_scenarios=$(<"$run_dir/scenarios-visible.md")

    local spec_content
    [[ -f "$spec_path" ]] || { log ERROR "Spec not found: $spec_path"; return 1; }
    spec_content=$(<"$spec_path")

    local embrace_prompt="## Factory Mode: Implement from NLSpec

${spec_content}

## Test Scenarios to Satisfy

${visible_scenarios:0:8000}

Implement the specification above. Ensure all visible test scenarios pass."

    # Set factory environment flags
    export OCTOPUS_FACTORY_MODE=true
    export AUTONOMY_MODE=autonomous
    export OCTOPUS_SKIP_PHASE_COST_PROMPT=true

    embrace_full_workflow "$embrace_prompt"

    # ── Phase 5: Holdout tests ───────────────────────────────────────────
    echo ""
    echo -e "${YELLOW}[5/7]${NC} Running holdout tests (blind evaluation)..."
    local holdout_score
    holdout_score=$(run_holdout_tests "$run_dir")
    echo -e "${GREEN}  ✓${NC} Holdout score: $holdout_score"

    # ── Phase 6: Satisfaction scoring ────────────────────────────────────
    echo ""
    echo -e "${YELLOW}[6/7]${NC} Scoring satisfaction..."
    local score_result
    score_result=$(score_satisfaction "$run_dir" "$satisfaction_target")
    local composite verdict
    composite=$(echo "$score_result" | cut -d'|' -f1)
    verdict=$(echo "$score_result" | cut -d'|' -f2)
    echo -e "${GREEN}  ✓${NC} Score: $composite -> $verdict"

    # ── Retry logic ──────────────────────────────────────────────────────
    local retry_count=0
    while [[ "$verdict" == "FAIL" && $retry_count -lt $max_retries ]]; do
        retry_count=$((retry_count + 1))
        echo ""
        echo -e "${YELLOW}[RETRY $retry_count/$max_retries]${NC} Re-running phases 3-4 with remediation context..."

        # Build remediation prompt from failing holdout scenarios
        local holdout_results=""
        [[ -f "$run_dir/holdout-results.md" ]] && holdout_results=$(<"$run_dir/holdout-results.md")

        local remediation_prompt="## Factory Mode: Remediation Pass ($retry_count/$max_retries)

The initial implementation did not meet the satisfaction target ($satisfaction_target).
Current score: $composite

## Failing Holdout Scenarios
${holdout_results:0:4000}

## Original Spec
${spec_content:0:4000}

Focus on fixing the failing scenarios. Do NOT restart from scratch — improve the existing implementation."

        export OCTOPUS_FACTORY_MODE=true
        export AUTONOMY_MODE=autonomous
        export OCTOPUS_SKIP_PHASE_COST_PROMPT=true

        embrace_full_workflow "$remediation_prompt"

        # Re-evaluate
        holdout_score=$(run_holdout_tests "$run_dir")
        score_result=$(score_satisfaction "$run_dir" "$satisfaction_target")
        composite=$(echo "$score_result" | cut -d'|' -f1)
        verdict=$(echo "$score_result" | cut -d'|' -f2)
        echo -e "${GREEN}  ✓${NC} Retry score: $composite -> $verdict"
    done

    # ── Phase 7: Generate report ─────────────────────────────────────────
    echo ""
    echo -e "${YELLOW}[7/7]${NC} Generating factory report..."
    generate_factory_report "$run_dir" "$satisfaction_target"
    echo -e "${GREEN}  ✓${NC} Report: $run_dir/factory-report.md"

    # Clean up exported flags
    unset OCTOPUS_FACTORY_MODE
    unset OCTOPUS_SKIP_PHASE_COST_PROMPT

    # ── Final summary ────────────────────────────────────────────────────
    echo ""
    local verdict_color="$RED"
    if [[ "$verdict" == "PASS" ]]; then verdict_color="$GREEN"
    elif [[ "$verdict" == "WARN" ]]; then verdict_color="$YELLOW"; fi

    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    echo -e "${MAGENTA}║  FACTORY COMPLETE                                         ║${NC}"
    echo -e "${MAGENTA}${_BOX_MID}${NC}"
    echo -e "${MAGENTA}║${NC}  Verdict:    ${verdict_color}${verdict}${NC} ($composite / $satisfaction_target target)"
    echo -e "${MAGENTA}║${NC}  Scenarios:  $scenario_count generated, $holdout_count holdout"
    echo -e "${MAGENTA}║${NC}  Retries:    $retry_count / $max_retries"
    echo -e "${MAGENTA}║${NC}  Report:     $run_dir/factory-report.md"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""
}
