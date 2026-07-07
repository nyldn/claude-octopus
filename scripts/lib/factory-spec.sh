#!/usr/bin/env bash
# factory-spec.sh — NLSpec factory pipeline: spec scoring, parsing, scenarios, satisfaction
# Functions: assess_spec_maturity, parse_factory_spec, generate_factory_scenarios, score_nlspec_quality, score_satisfaction, generate_factory_report
# Extracted from orchestrate.sh (v9.7.8)
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════
# DARK FACTORY MODE — Spec-in, software-out autonomous pipeline (v8.25.0)
# Issue #37: E19 (Scenario Holdout) + E21 (Satisfaction Scoring) + E22 (Factory)
# ═══════════════════════════════════════════════════════════════════════════

assess_spec_maturity() {
    local spec_path="$1"

    if [[ ! -f "$spec_path" ]]; then
        echo "Skeleton|0|{}"
        return 0
    fi

    local spec_content
    spec_content=$(<"$spec_path")

    # Count NLSpec template sections
    local has_purpose=0 has_actors=0 has_behaviors=0
    local has_constraints=0 has_dependencies=0 has_acceptance=0

    shopt -s nocasematch
    [[ "$spec_content" == *"## Purpose"* ]] && has_purpose=1
    [[ "$spec_content" == *"## Actors"* ]] && has_actors=1
    [[ "$spec_content" == *"## Behaviors"* ]] && has_behaviors=1
    [[ "$spec_content" == *"## Constraints"* ]] && has_constraints=1
    [[ "$spec_content" == *"## Dependencies"* ]] && has_dependencies=1
    [[ "$spec_content" == *"## Acceptance"* ]] && has_acceptance=1

    local sections=$((has_purpose + has_actors + has_behaviors + has_constraints + has_dependencies + has_acceptance))

    # Quality markers (edge cases, preconditions, postconditions)
    local has_edge_cases=0 has_preconditions=0 has_postconditions=0
    local _re_edge='edge.case|exception|error.handling'
    [[ "$spec_content" =~ $_re_edge ]] && has_edge_cases=1
    [[ "$spec_content" == *"precondition"* ]] && has_preconditions=1
    [[ "$spec_content" == *"postcondition"* ]] && has_postconditions=1
    shopt -u nocasematch

    local quality_markers=$((has_edge_cases + has_preconditions + has_postconditions))

    # Determine maturity level
    local level
    if [[ $sections -lt 2 ]]; then
        level="Skeleton"
    elif [[ $sections -lt 4 ]]; then
        level="Draft"
    elif [[ $sections -lt 5 ]]; then
        level="Structured"
    elif [[ $sections -lt 6 || $quality_markers -lt 2 ]]; then
        level="Validated"
    else
        level="Mature"
    fi

    # Build JSON
    local json
    json=$(cat <<MATEOF
{"level":"$level","sections":$sections,"quality_markers":$quality_markers,"detail":{"purpose":$has_purpose,"actors":$has_actors,"behaviors":$has_behaviors,"constraints":$has_constraints,"dependencies":$has_dependencies,"acceptance":$has_acceptance,"edge_cases":$has_edge_cases,"preconditions":$has_preconditions,"postconditions":$has_postconditions},"assessed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
MATEOF
)

    echo "${level}|${sections}|${json}"
}

parse_factory_spec() {
    local spec_path="$1"
    local run_dir="$2"

    if [[ ! -f "$spec_path" ]]; then
        log ERROR "Factory spec not found: $spec_path"
        return 1
    fi

    # Copy spec into run directory
    cp "$spec_path" "$run_dir/spec.md"

    local spec_content
    spec_content=$(<"$spec_path")

    # Extract satisfaction target from spec (format: "Satisfaction Target: 0.90" or similar)
    local satisfaction_target
    satisfaction_target=$(echo "$spec_content" | grep -oi 'satisfaction.*target[: ]*[0-9]*\.[0-9]*' | head -1 | grep -o '[0-9]*\.[0-9]*' || echo "")
    # Extract complexity class (single nocasematch block for both satisfaction + complexity)
    local complexity="complex"
    shopt -s nocasematch
    if [[ "$spec_content" == *complexity*clear* ]]; then
        complexity="clear"
    elif [[ "$spec_content" == *complexity*complicated* ]]; then
        complexity="complicated"
    fi
    shopt -u nocasematch

    if [[ -z "$satisfaction_target" ]]; then
        # Infer from complexity class
        case "$complexity" in
            clear)       satisfaction_target="0.95" ;;
            complicated) satisfaction_target="0.90" ;;
            *)           satisfaction_target="0.85" ;;
        esac
        log INFO "No explicit satisfaction target in spec, inferred: $satisfaction_target"
    fi

    # Override with env var if set
    if [[ -n "$OCTOPUS_FACTORY_SATISFACTION_TARGET" ]]; then
        satisfaction_target="$OCTOPUS_FACTORY_SATISFACTION_TARGET"
        log INFO "Satisfaction target overridden by env: $satisfaction_target"
    fi

    # Extract behaviors (lines starting with "### " under Behaviors section, or numbered items)
    local behavior_count
    behavior_count=$(echo "$spec_content" | grep -c '^\(### \|[0-9]\+\.\s\+\*\*\)' || echo "0")
    if [[ "$behavior_count" -eq 0 ]]; then
        behavior_count=$(echo "$spec_content" | grep -c '^- \*\*' || echo "3")
    fi

    log INFO "Factory spec parsed: complexity=$complexity, satisfaction_target=$satisfaction_target, behaviors=$behavior_count"

    # Write parsed metadata (includes maturity from pre-flight E27 assessment)
    cat > "$run_dir/session.json" << SPECEOF
{
  "run_id": "$(basename "$run_dir")",
  "spec_path": "$spec_path",
  "satisfaction_target": $satisfaction_target,
  "complexity": "$complexity",
  "behavior_count": $behavior_count,
  "holdout_ratio": $OCTOPUS_FACTORY_HOLDOUT_RATIO,
  "max_retries": $OCTOPUS_FACTORY_MAX_RETRIES,
  "maturity": $maturity_json,
  "status": "initialized",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
SPECEOF

    echo "$satisfaction_target"
}

generate_factory_scenarios() {
    local spec_path="$1"
    local run_dir="$2"

    [[ -f "$spec_path" ]] || { log ERROR "Spec not found: $spec_path"; return 1; }
    local spec_content
    spec_content=$(<"$spec_path")

    log INFO "Generating test scenarios from spec..."

    local scenario_prompt="You are a QA engineer generating test scenarios from a product specification.

Given this NLSpec:
---
${spec_content:0:6000}
---

Generate 10-20 test scenarios that cover:
1. Happy-path behaviors (each behavior from the spec gets at least one scenario)
2. Edge cases and boundary conditions
3. Error handling scenarios
4. Integration points between behaviors
5. Non-functional requirements (performance, security constraints)

For each scenario, output:
### Scenario N: <title>
**Behavior:** <which spec behavior this tests>
**Type:** happy-path | edge-case | error-handling | integration | non-functional
**Given:** <preconditions>
**When:** <action/trigger>
**Then:** <expected outcome>
**Verification:** <how to verify PASS/FAIL>

Generate scenarios that are specific enough to evaluate against an implementation."

    local scenarios=""

    # Multi-provider scenario generation for diversity
    local provider_scenarios
    provider_scenarios=$(run_agent_sync "codex" "$scenario_prompt" 120 "qa-engineer" "factory" 2>/dev/null) || true

    if [[ -n "$provider_scenarios" ]]; then
        scenarios="$provider_scenarios"
    fi

    # Fallback/supplement with second provider
    local supplemental
    supplemental=$(run_agent_sync "agy" "$scenario_prompt" 120 "qa-engineer" "factory" 2>/dev/null) || true

    if [[ -n "$supplemental" && -n "$scenarios" ]]; then
        # Merge unique scenarios from supplemental
        scenarios="${scenarios}

## Additional Scenarios (Cross-Provider)

${supplemental}"
    elif [[ -n "$supplemental" ]]; then
        scenarios="$supplemental"
    fi

    # Fallback to Claude if both external providers failed
    if [[ -z "$scenarios" ]]; then
        log WARN "External providers unavailable for scenario generation, using Claude"
        scenarios=$(run_agent_sync "claude" "$scenario_prompt" "${TIMEOUT:-300}" "qa-engineer" "factory" 2>/dev/null) || true
    fi

    if [[ -z "$scenarios" ]]; then
        log ERROR "Failed to generate scenarios from any provider"
        return 1
    fi

    echo "$scenarios" > "$run_dir/scenarios-all.md"
    log INFO "Scenarios generated and saved to $run_dir/scenarios-all.md"

    echo "$scenarios"
}

# [EXTRACTED to lib/factory.sh]

# [EXTRACTED to lib/factory.sh]

score_nlspec_quality() {
    local spec_path="$1"
    local output_dir="${2:-.}"

    if [[ ! -f "$spec_path" ]]; then
        log ERROR "Spec not found for NQS scoring: $spec_path"
        echo "0|FAIL"
        return 0
    fi

    local spec_content
    spec_content=$(head -500 "$spec_path")

    local nqs_prompt="You are a specification quality analyst. Score this NLSpec on 12 dimensions (0.0-1.0 each).

## Specification
${spec_content:0:6000}

## Scoring Dimensions (score each 0.0-1.0)
1. completeness — All required sections present and substantive
2. clarity — Clear, unambiguous language; no vague terms like 'should handle appropriately'
3. testability — Behaviors specific enough to write automated tests against
4. feasibility — Requirements are technically realistic and achievable
5. specificity — Concrete details, not generic descriptions
6. structure — Logical organization, clear hierarchy, consistent formatting
7. consistency — No contradictions or conflicting requirements
8. behavioral_coverage — All major use cases and user flows addressed
9. constraint_clarity — Performance, security, scale targets are quantified
10. dependency_completeness — External services, libraries, APIs identified
11. acceptance_criteria — Clear satisfaction targets with measurable metrics
12. complexity_match — Complexity classification matches actual content scope

## Output Format (STRICT — output ONLY this JSON, no other text)
{\"completeness\":0.0,\"clarity\":0.0,\"testability\":0.0,\"feasibility\":0.0,\"specificity\":0.0,\"structure\":0.0,\"consistency\":0.0,\"behavioral_coverage\":0.0,\"constraint_clarity\":0.0,\"dependency_completeness\":0.0,\"acceptance_criteria\":0.0,\"complexity_match\":0.0}"

    local nqs_result
    nqs_result=$(run_agent_sync "claude-sonnet" "$nqs_prompt" 120 "spec-quality-analyst" "factory" 2>/dev/null) || true

    if [[ -z "$nqs_result" ]]; then
        nqs_result=$(run_agent_sync "agy" "$nqs_prompt" 120 "spec-quality-analyst" "factory" 2>/dev/null) || true
    fi

    if [[ -z "$nqs_result" ]]; then
        log WARN "NQS scoring failed from all providers"
        echo "0|FAIL"
        return 0
    fi

    # Extract JSON from response (find first { to last })
    local json_scores
    json_scores=$(echo "$nqs_result" | grep -o '{[^}]*}' | head -1)

    if [[ -z "$json_scores" ]]; then
        log WARN "NQS scoring returned unparseable result"
        echo "0|FAIL"
        return 0
    fi

    # Calculate composite score (equal weights: 8.33% each)
    local composite
    composite=$(echo "$json_scores" | grep -o '[0-9]*\.[0-9]*' | awk '
        { sum += $1; count++ }
        END {
            if (count > 0) printf "%d", (sum / count) * 100
            else print "0"
        }')

    # Determine verdict
    local verdict="FAIL"
    if [[ "$composite" -ge 85 ]]; then
        verdict="PASS"
    elif [[ "$composite" -ge 75 ]]; then
        verdict="WARN"
    fi

    # Write scores file if output directory provided
    if [[ -d "$output_dir" ]]; then
        cat > "$output_dir/nqs-scores.json" << NQSEOF
{"composite":$composite,"verdict":"$verdict","dimensions":$json_scores,"scored_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
NQSEOF
    fi

    log INFO "NQS score: $composite ($verdict)"
    echo "${composite}|${verdict}"
}

score_satisfaction() {
    local run_dir="$1"
    local satisfaction_target="$2"

    log INFO "Scoring satisfaction against target: $satisfaction_target"

    local spec_content=""
    [[ -f "$run_dir/spec.md" ]] && spec_content=$(<"$run_dir/spec.md")

    local holdout_score="0.50"
    [[ -f "$run_dir/holdout-results.md" ]] && holdout_score=$(grep -oi 'score[: ]*[0-9]*\.[0-9]*' "$run_dir/holdout-results.md" | tail -1 | grep -o '[0-9]*\.[0-9]*' || echo "0.50")

    # Multi-provider satisfaction scoring
    local scoring_prompt="You are evaluating whether an implementation satisfies its original specification.

## Original Specification
${spec_content:0:4000}

## Scoring Dimensions (rate each 0.00-1.00)

1. **Behavior Coverage** (weight: 40%): How many specified behaviors are fully implemented?
2. **Constraint Adherence** (weight: 20%): Are performance, security, and other constraints met?
3. **Quality** (weight: 15%): Code quality, test coverage, documentation completeness?

Rate each dimension and provide a brief justification.

Output format:
behavior_coverage: X.XX
constraint_adherence: X.XX
quality: X.XX
justification: <2-3 sentences>"

    local scoring_result
    scoring_result=$(run_agent_sync "claude-sonnet" "$scoring_prompt" 120 "evaluator" "factory" 2>/dev/null) || true

    if [[ -z "$scoring_result" ]]; then
        scoring_result=$(run_agent_sync "claude" "$scoring_prompt" 120 "evaluator" "factory" 2>/dev/null) || true
    fi

    # Parse scores from response
    local behavior_score constraint_score quality_score
    behavior_score=$(echo "$scoring_result" | grep -oi 'behavior_coverage[: ]*[0-9]*\.[0-9]*' | head -1 | grep -o '[0-9]*\.[0-9]*' || echo "0.70")
    constraint_score=$(echo "$scoring_result" | grep -oi 'constraint_adherence[: ]*[0-9]*\.[0-9]*' | head -1 | grep -o '[0-9]*\.[0-9]*' || echo "0.70")
    quality_score=$(echo "$scoring_result" | grep -oi 'quality[: ]*[0-9]*\.[0-9]*' | head -1 | grep -o '[0-9]*\.[0-9]*' || echo "0.70")

    # Weighted composite: behavior(40%) + constraints(20%) + holdout(25%) + quality(15%)
    local composite
    composite=$(echo "$behavior_score $constraint_score $holdout_score $quality_score" | \
        awk '{printf "%.2f", $1 * 0.40 + $2 * 0.20 + $3 * 0.25 + $4 * 0.15}')

    # Determine verdict
    local verdict="FAIL"
    local target_minus_05
    target_minus_05=$(echo "$satisfaction_target" | awk '{printf "%.2f", $1 - 0.05}')

    if awk "BEGIN {exit !($composite >= $satisfaction_target)}"; then
        verdict="PASS"
    elif awk "BEGIN {exit !($composite >= $target_minus_05)}"; then
        verdict="WARN"
    fi

    log INFO "Satisfaction score: $composite (target: $satisfaction_target) -> $verdict"

    # Write scores JSON
    cat > "$run_dir/satisfaction-scores.json" << SCOREEOF
{
  "behavior_coverage": $behavior_score,
  "constraint_adherence": $constraint_score,
  "holdout_pass_rate": $holdout_score,
  "quality": $quality_score,
  "composite": $composite,
  "satisfaction_target": $satisfaction_target,
  "verdict": "$verdict",
  "weights": {
    "behavior_coverage": 0.40,
    "constraint_adherence": 0.20,
    "holdout_pass_rate": 0.25,
    "quality": 0.15
  },
  "scored_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
SCOREEOF

    echo "$composite|$verdict"
}

generate_factory_report() {
    local run_dir="$1"
    local satisfaction_target="$2"

    log INFO "Generating factory report..."

    local run_id
    run_id=$(basename "$run_dir")

    local composite="N/A"
    local verdict="UNKNOWN"
    local behavior_score="N/A"
    local constraint_score="N/A"
    local holdout_score="N/A"
    local quality_score="N/A"

    if [[ -f "$run_dir/satisfaction-scores.json" ]] && command -v jq &>/dev/null; then
        composite=$(jq -r '.composite' "$run_dir/satisfaction-scores.json" 2>/dev/null || echo "N/A")
        verdict=$(jq -r '.verdict' "$run_dir/satisfaction-scores.json" 2>/dev/null || echo "UNKNOWN")
        behavior_score=$(jq -r '.behavior_coverage' "$run_dir/satisfaction-scores.json" 2>/dev/null || echo "N/A")
        constraint_score=$(jq -r '.constraint_adherence' "$run_dir/satisfaction-scores.json" 2>/dev/null || echo "N/A")
        holdout_score=$(jq -r '.holdout_pass_rate' "$run_dir/satisfaction-scores.json" 2>/dev/null || echo "N/A")
        quality_score=$(jq -r '.quality' "$run_dir/satisfaction-scores.json" 2>/dev/null || echo "N/A")
    fi

    local verdict_emoji="❌"
    if [[ "$verdict" == "PASS" ]]; then verdict_emoji="✅"
    elif [[ "$verdict" == "WARN" ]]; then verdict_emoji="⚠️"; fi

    local started_at=""
    if [[ -f "$run_dir/session.json" ]] && command -v jq &>/dev/null; then
        started_at=$(jq -r '.started_at' "$run_dir/session.json" 2>/dev/null || echo "")
    fi

    cat > "$run_dir/factory-report.md" << REPORTEOF
# Dark Factory Report

**Run ID:** $run_id
**Started:** ${started_at:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
**Completed:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Verdict: $verdict_emoji $verdict

**Composite Score:** $composite / $satisfaction_target target

## Score Breakdown

| Dimension            | Weight | Score |
|----------------------|--------|-------|
| Behavior Coverage    | 40%    | $behavior_score |
| Constraint Adherence | 20%    | $constraint_score |
| Holdout Pass Rate    | 25%    | $holdout_score |
| Quality              | 15%    | $quality_score |
| **Composite**        | 100%   | **$composite** |

## Artifacts

| File | Description |
|------|-------------|
| spec.md | Original NLSpec |
| scenarios-all.md | All generated test scenarios |
| scenarios-visible.md | Scenarios visible during implementation |
| scenarios-holdout.md | Blind holdout scenarios (20%) |
| holdout-results.md | Holdout evaluation results |
| satisfaction-scores.json | Structured score data |
| session.json | Run metadata |

## Pipeline Phases

1. **Parse Spec** — Extracted behaviors, constraints, satisfaction target
2. **Generate Scenarios** — Multi-provider scenario generation from spec
3. **Split Holdout** — 80/20 split with behavior-diverse holdout selection
4. **Embrace Workflow** — Full 4-phase implementation (discover → define → develop → deliver)
5. **Holdout Tests** — Blind evaluation against withheld scenarios
6. **Satisfaction Scoring** — Weighted multi-dimension assessment
7. **Report** — This document

---
*Generated by Claude Octopus Dark Factory Mode v8.25.0*
REPORTEOF

    # Update session.json status
    if [[ -f "$run_dir/session.json" ]] && command -v jq &>/dev/null; then
        jq --arg v "$verdict" --arg c "$composite" \
            '.status = "completed" | .verdict = $v | .composite_score = ($c | tonumber) | .completed_at = (now | todate)' \
            "$run_dir/session.json" > "$run_dir/session.json.tmp" && \
            mv "$run_dir/session.json.tmp" "$run_dir/session.json"
    fi

    log INFO "Factory report generated: $run_dir/factory-report.md"
}
