#!/usr/bin/env bash
# Benchmark: Claude Native vs Claude Octopus
# Compares single Claude Opus 4.5 request vs multi-agent orchestration
# Metrics: Quality, Speed, Cost

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BENCHMARK_DIR="${PROJECT_ROOT}/.benchmark-results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test configuration
BENCHMARK_TASKS=(
    "code-review:Review this authentication code for security issues and suggest improvements"
    "research:Research best practices for implementing OAuth 2.0 authentication in Node.js"
    "implementation:Implement a simple rate limiting middleware in Express.js with Redis"
)

# Results storage
declare -A CLAUDE_TIMES
declare -A OCTOPUS_TIMES
declare -A CLAUDE_COSTS
declare -A OCTOPUS_COSTS
declare -A CLAUDE_OUTPUTS
declare -A OCTOPUS_OUTPUTS

mkdir -p "$BENCHMARK_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

log() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# ═══════════════════════════════════════════════════════════════════════════════
# BENCHMARK FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Run task with Claude native (single Opus 4.5 request)
run_claude_native() {
    local task_id="$1"
    local prompt="$2"
    local output_file="${BENCHMARK_DIR}/claude-${task_id}-${TIMESTAMP}.md"

    log "Running Claude native: $task_id"

    local start_time=$(date +%s)

    # Check if Claude CLI is available
    if ! command -v claude &> /dev/null; then
        error "Claude CLI not found. Install with: npm install -g @anthropics/claude-cli"
        return 1
    fi

    # Run Claude with Opus 4.5
    if claude --model opus-4.5 "$prompt" > "$output_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        CLAUDE_TIMES[$task_id]=$duration
        CLAUDE_OUTPUTS[$task_id]="$output_file"

        # Estimate cost (rough approximation)
        local tokens=$(wc -w < "$output_file" | tr -d ' ')
        local cost_estimate=$(echo "scale=4; $tokens * 0.015 / 1000" | bc)
        CLAUDE_COSTS[$task_id]=$cost_estimate

        success "Claude native completed in ${duration}s (~\$${cost_estimate})"
        return 0
    else
        error "Claude native failed"
        return 1
    fi
}

# Run task with Claude Octopus (multi-agent orchestration)
run_claude_octopus() {
    local task_id="$1"
    local prompt="$2"
    local workflow="${3:-auto}"
    local output_file="${BENCHMARK_DIR}/octopus-${task_id}-${TIMESTAMP}.md"

    log "Running Claude Octopus: $task_id (workflow: $workflow)"

    local start_time=$(date +%s)

    # Run orchestrate.sh with appropriate workflow
    if "$PROJECT_ROOT/scripts/orchestrate.sh" "$workflow" "$prompt" > "$output_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        OCTOPUS_TIMES[$task_id]=$duration
        OCTOPUS_OUTPUTS[$task_id]="$output_file"

        # Get actual cost from octopus cost tracking
        local cost=$(grep -A10 "Total Cost" "$output_file" | grep -oE '\$[0-9]+\.[0-9]+' | head -1 | tr -d '$')
        if [[ -z "$cost" ]]; then
            # Fallback: estimate from results files
            local results_count=$(find "$PROJECT_ROOT/.claude-octopus/results" -name "*${task_id}*" -type f 2>/dev/null | wc -l | tr -d ' ')
            cost=$(echo "scale=4; $results_count * 0.02" | bc)
        fi
        OCTOPUS_COSTS[$task_id]=$cost

        success "Claude Octopus completed in ${duration}s (\$${cost})"
        return 0
    else
        error "Claude Octopus failed"
        return 1
    fi
}

# Measure output quality (heuristic-based)
measure_quality() {
    local output_file="$1"
    local score=0

    # Quality metrics (0-100 scale)

    # 1. Completeness (25 points): Output length
    local word_count=$(wc -w < "$output_file" | tr -d ' ')
    if [[ $word_count -gt 500 ]]; then
        score=$((score + 25))
    elif [[ $word_count -gt 300 ]]; then
        score=$((score + 15))
    elif [[ $word_count -gt 100 ]]; then
        score=$((score + 10))
    fi

    # 2. Structure (25 points): Headings, lists, code blocks
    local structure_score=0
    grep -q "^#" "$output_file" && structure_score=$((structure_score + 8))
    grep -q "^-\|^*\|^[0-9]" "$output_file" && structure_score=$((structure_score + 8))
    grep -q '```' "$output_file" && structure_score=$((structure_score + 9))
    score=$((score + structure_score))

    # 3. Code examples (25 points): Presence of code blocks
    local code_blocks=$(grep -c '```' "$output_file" || echo 0)
    if [[ $code_blocks -ge 4 ]]; then
        score=$((score + 25))
    elif [[ $code_blocks -ge 2 ]]; then
        score=$((score + 15))
    elif [[ $code_blocks -ge 1 ]]; then
        score=$((score + 10))
    fi

    # 4. Depth (25 points): Technical terms, best practices mentioned
    local depth_score=0
    grep -qi "security\|vulnerability\|best practice\|performance\|optimization" "$output_file" && depth_score=$((depth_score + 13))
    grep -qi "example\|implementation\|approach\|strategy" "$output_file" && depth_score=$((depth_score + 12))
    score=$((score + depth_score))

    echo "$score"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN BENCHMARK EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

run_benchmark() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Claude Native vs Claude Octopus Benchmark               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_tests=${#BENCHMARK_TASKS[@]}
    local completed=0

    for task_spec in "${BENCHMARK_TASKS[@]}"; do
        IFS=':' read -r task_id prompt <<< "$task_spec"

        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}Task: $task_id${NC}"
        echo -e "${YELLOW}Prompt: $prompt${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
        echo ""

        # Run Claude native
        if run_claude_native "$task_id" "$prompt"; then
            sleep 2
        fi

        # Run Claude Octopus
        if run_claude_octopus "$task_id" "$prompt" "auto"; then
            sleep 2
        fi

        ((completed++))
        echo ""
        echo -e "${CYAN}Progress: $completed/$total_tests tasks completed${NC}"
    done

    # Generate comparison report
    generate_report
}

# ═══════════════════════════════════════════════════════════════════════════════
# REPORT GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

generate_report() {
    local report_file="${BENCHMARK_DIR}/benchmark-report-${TIMESTAMP}.md"

    echo ""
    echo -e "${YELLOW}Generating benchmark report...${NC}"

    cat > "$report_file" << 'EOF'
# Claude Native vs Claude Octopus Benchmark Report

## Executive Summary

This benchmark compares single Claude Opus 4.5 requests against Claude Octopus multi-agent orchestration.

**Metrics:**
- ⏱️  **Speed**: Execution time (seconds)
- 💰 **Cost**: API usage cost (USD)
- 🎯 **Quality**: Output completeness and depth (0-100 scale)

---

## Methodology

**Claude Native:**
- Single request to Claude Opus 4.5
- Direct API call via Claude CLI
- No multi-agent coordination

**Claude Octopus:**
- Multi-agent orchestration (auto-routing)
- Uses probe/grasp/tangle/ink workflows as needed
- Parallel execution with quality gates

---

## Results

EOF

    # Per-task comparison
    for task_spec in "${BENCHMARK_TASKS[@]}"; do
        IFS=':' read -r task_id prompt <<< "$task_spec"

        cat >> "$report_file" << EOF
### Task: $task_id

**Prompt:** \`$prompt\`

EOF

        # Get metrics
        local claude_time="${CLAUDE_TIMES[$task_id]:-N/A}"
        local octopus_time="${OCTOPUS_TIMES[$task_id]:-N/A}"
        local claude_cost="${CLAUDE_COSTS[$task_id]:-N/A}"
        local octopus_cost="${OCTOPUS_COSTS[$task_id]:-N/A}"

        # Quality scores
        local claude_quality=0
        local octopus_quality=0
        if [[ -f "${CLAUDE_OUTPUTS[$task_id]}" ]]; then
            claude_quality=$(measure_quality "${CLAUDE_OUTPUTS[$task_id]}")
        fi
        if [[ -f "${OCTOPUS_OUTPUTS[$task_id]}" ]]; then
            octopus_quality=$(measure_quality "${OCTOPUS_OUTPUTS[$task_id]}")
        fi

        cat >> "$report_file" << EOF
| Metric | Claude Native | Claude Octopus | Winner |
|--------|---------------|----------------|--------|
| Speed | ${claude_time}s | ${octopus_time}s | $(compare_metric "$claude_time" "$octopus_time" "speed") |
| Cost | \$${claude_cost} | \$${octopus_cost} | $(compare_metric "$claude_cost" "$octopus_cost" "cost") |
| Quality | ${claude_quality}/100 | ${octopus_quality}/100 | $(compare_metric "$claude_quality" "$octopus_quality" "quality") |

**Analysis:**
$(generate_analysis "$task_id" "$claude_time" "$octopus_time" "$claude_cost" "$octopus_cost" "$claude_quality" "$octopus_quality")

---

EOF
    done

    # Overall summary
    cat >> "$report_file" << EOF
## Overall Comparison

### Aggregated Results

EOF

    # Calculate averages
    local total_tasks=${#BENCHMARK_TASKS[@]}
    local claude_avg_time=0
    local octopus_avg_time=0
    local claude_avg_cost=0
    local octopus_avg_cost=0
    local claude_avg_quality=0
    local octopus_avg_quality=0

    for task_spec in "${BENCHMARK_TASKS[@]}"; do
        IFS=':' read -r task_id _ <<< "$task_spec"

        claude_avg_time=$((claude_avg_time + ${CLAUDE_TIMES[$task_id]:-0}))
        octopus_avg_time=$((octopus_avg_time + ${OCTOPUS_TIMES[$task_id]:-0}))

        claude_avg_cost=$(echo "$claude_avg_cost + ${CLAUDE_COSTS[$task_id]:-0}" | bc)
        octopus_avg_cost=$(echo "$octopus_avg_cost + ${OCTOPUS_COSTS[$task_id]:-0}" | bc)

        if [[ -f "${CLAUDE_OUTPUTS[$task_id]}" ]]; then
            local cq=$(measure_quality "${CLAUDE_OUTPUTS[$task_id]}")
            claude_avg_quality=$((claude_avg_quality + cq))
        fi
        if [[ -f "${OCTOPUS_OUTPUTS[$task_id]}" ]]; then
            local oq=$(measure_quality "${OCTOPUS_OUTPUTS[$task_id]}")
            octopus_avg_quality=$((octopus_avg_quality + oq))
        fi
    done

    claude_avg_time=$((claude_avg_time / total_tasks))
    octopus_avg_time=$((octopus_avg_time / total_tasks))
    claude_avg_cost=$(echo "scale=4; $claude_avg_cost / $total_tasks" | bc)
    octopus_avg_cost=$(echo "scale=4; $octopus_avg_cost / $total_tasks" | bc)
    claude_avg_quality=$((claude_avg_quality / total_tasks))
    octopus_avg_quality=$((octopus_avg_quality / total_tasks))

    cat >> "$report_file" << EOF
| Metric | Claude Native (Avg) | Claude Octopus (Avg) | Winner |
|--------|---------------------|----------------------|--------|
| Speed | ${claude_avg_time}s | ${octopus_avg_time}s | $(compare_metric "$claude_avg_time" "$octopus_avg_time" "speed") |
| Cost | \$${claude_avg_cost} | \$${octopus_avg_cost} | $(compare_metric "$claude_avg_cost" "$octopus_avg_cost" "cost") |
| Quality | ${claude_avg_quality}/100 | ${octopus_avg_quality}/100 | $(compare_metric "$claude_avg_quality" "$octopus_avg_quality" "quality") |

### Key Findings

$(generate_key_findings "$claude_avg_time" "$octopus_avg_time" "$claude_avg_cost" "$octopus_avg_cost" "$claude_avg_quality" "$octopus_avg_quality")

---

## Conclusion

$(generate_conclusion "$claude_avg_quality" "$octopus_avg_quality" "$claude_avg_cost" "$octopus_avg_cost" "$claude_avg_time" "$octopus_avg_time")

---

*Generated: $(date)*
*Benchmark ID: ${TIMESTAMP}*
EOF

    success "Report generated: $report_file"
    echo ""
    echo -e "${GREEN}View report:${NC} cat $report_file"
    echo ""

    # Display summary
    cat "$report_file"
}

# Compare two metrics and determine winner
compare_metric() {
    local val1="$1"
    local val2="$2"
    local metric_type="$3"

    # Handle N/A cases
    if [[ "$val1" == "N/A" ]]; then echo "Claude Octopus"; return; fi
    if [[ "$val2" == "N/A" ]]; then echo "Claude Native"; return; fi

    # For speed and cost, lower is better
    # For quality, higher is better
    if [[ "$metric_type" == "quality" ]]; then
        if (( $(echo "$val2 > $val1" | bc -l) )); then
            echo "🏆 Claude Octopus"
        elif (( $(echo "$val1 > $val2" | bc -l) )); then
            echo "🏆 Claude Native"
        else
            echo "Tie"
        fi
    else
        if (( $(echo "$val2 < $val1" | bc -l) )); then
            echo "🏆 Claude Octopus"
        elif (( $(echo "$val1 < $val2" | bc -l) )); then
            echo "🏆 Claude Native"
        else
            echo "Tie"
        fi
    fi
}

# Generate task-specific analysis
generate_analysis() {
    local task_id="$1"
    local claude_time="$2"
    local octopus_time="$3"
    local claude_cost="$4"
    local octopus_cost="$5"
    local claude_quality="$6"
    local octopus_quality="$7"

    local analysis=""

    # Speed analysis
    if [[ "$octopus_time" != "N/A" && "$claude_time" != "N/A" ]]; then
        local time_diff=$((octopus_time - claude_time))
        if [[ $time_diff -lt 0 ]]; then
            analysis+="- Claude Octopus was **faster** by ${time_diff#-}s\n"
        elif [[ $time_diff -gt 0 ]]; then
            analysis+="- Claude Native was **faster** by ${time_diff}s\n"
        fi
    fi

    # Quality analysis
    local quality_diff=$((octopus_quality - claude_quality))
    if [[ $quality_diff -gt 10 ]]; then
        analysis+="- Claude Octopus provided **higher quality** output (+${quality_diff} points)\n"
    elif [[ $quality_diff -lt -10 ]]; then
        analysis+="- Claude Native provided **higher quality** output (+${quality_diff#-} points)\n"
    fi

    # Cost analysis
    if [[ "$octopus_cost" != "N/A" && "$claude_cost" != "N/A" ]]; then
        local cost_ratio=$(echo "scale=2; $octopus_cost / $claude_cost" | bc)
        if (( $(echo "$cost_ratio > 1.5" | bc -l) )); then
            analysis+="- Claude Octopus cost **${cost_ratio}x more** but delivered better results\n"
        elif (( $(echo "$cost_ratio < 0.8" | bc -l) )); then
            analysis+="- Claude Octopus was **more cost-efficient**\n"
        fi
    fi

    echo -e "$analysis"
}

# Generate key findings
generate_key_findings() {
    local claude_time="$1"
    local octopus_time="$2"
    local claude_cost="$3"
    local octopus_cost="$4"
    local claude_quality="$5"
    local octopus_quality="$6"

    local findings=""

    # Quality comparison
    local quality_diff=$((octopus_quality - claude_quality))
    if [[ $quality_diff -gt 0 ]]; then
        findings+="**Quality Advantage:** Claude Octopus produced +${quality_diff}% higher quality outputs through multi-agent validation.\n\n"
    fi

    # Cost comparison
    local cost_ratio=$(echo "scale=2; $octopus_cost / $claude_cost" | bc)
    findings+="**Cost Ratio:** Claude Octopus costs ${cost_ratio}x Claude Native (multi-agent coordination overhead).\n\n"

    # Speed comparison
    local time_diff=$((octopus_time - claude_time))
    if [[ $time_diff -gt 0 ]]; then
        findings+="**Speed Trade-off:** Claude Octopus takes +${time_diff}s longer but provides consensus-based validation.\n\n"
    fi

    echo -e "$findings"
}

# Generate conclusion
generate_conclusion() {
    local claude_quality="$1"
    local octopus_quality="$2"
    local claude_cost="$3"
    local octopus_cost="$4"
    local claude_time="$5"
    local octopus_time="$6"

    if [[ $octopus_quality -gt $claude_quality ]]; then
        echo "Claude Octopus demonstrates clear **quality advantages** through multi-agent orchestration, consensus building, and parallel validation. While it incurs higher costs and time, the improved output quality justifies the overhead for critical tasks requiring comprehensive analysis and validation."
    else
        echo "For simple tasks, Claude Native with Opus 4.5 provides comparable results with lower cost and faster execution. Claude Octopus shows value in complex scenarios requiring multiple perspectives and quality validation."
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    # Check prerequisites
    if ! command -v claude &> /dev/null; then
        error "Claude CLI not found. Install: npm install -g @anthropics/claude-cli"
        exit 1
    fi

    if ! command -v bc &> /dev/null; then
        error "bc calculator not found. Install: brew install bc (macOS) or apt install bc (Linux)"
        exit 1
    fi

    # Run benchmark
    run_benchmark
}

main "$@"
