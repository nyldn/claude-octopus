#!/usr/bin/env bash
# Real Benchmark: Claude Code vs Claude Code + Octopus Plugin
# Tests actual plugin usage against ground truth vulnerable code

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_CASES_DIR="$SCRIPT_DIR/test-cases/vulnerable"
RESULTS_DIR="$PROJECT_ROOT/.dev/benchmarks/$(date +%Y%m%d-%H%M%S)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

mkdir -p "$RESULTS_DIR"

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  REAL CODE ANALYSIS BENCHMARK                             ║${NC}"
echo -e "${BLUE}║  Testing against ground truth vulnerable code            ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Find test cases
test_cases=($(find "$TEST_CASES_DIR" -name "ground-truth.json" -type f))

if [ ${#test_cases[@]} -eq 0 ]; then
    echo -e "${RED}ERROR: No test cases found in $TEST_CASES_DIR${NC}"
    exit 1
fi

echo -e "${CYAN}Found ${#test_cases[@]} test case(s)${NC}"
echo ""

for ground_truth_file in "${test_cases[@]}"; do
    test_dir=$(dirname "$ground_truth_file")
    test_name=$(basename "$test_dir")
    code_file="$test_dir/code.py"

    if [ ! -f "$code_file" ]; then
        echo -e "${YELLOW}⚠ Skipping $test_name: code.py not found${NC}"
        continue
    fi

    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Test Case: $test_name${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Read ground truth
    expected_issues=$(jq '.expected_issues | length' "$ground_truth_file")
    echo -e "${CYAN}Expected issues: $expected_issues${NC}"
    echo ""

    #===========================================================================
    # TEST 1: WITHOUT PLUGIN (Baseline - Claude direct response)
    #===========================================================================

    echo -e "${CYAN}[1/2] Analyzing WITHOUT plugin (baseline)...${NC}"
    echo ""

    # Create prompt
    prompt="Review this Python code for security vulnerabilities. List ALL security issues found with:
1. Severity (CRITICAL/HIGH/MEDIUM/LOW)
2. CWE category
3. Line number
4. Description
5. Attack vector

Code to analyze:
\`\`\`python
$(cat "$code_file")
\`\`\`

Be comprehensive and list every vulnerability, even minor ones."

    # Save baseline results
    # NOTE: This would normally be me (Claude) responding directly
    # For automation, we'll mark this as requiring manual input
    echo "$prompt" > "$RESULTS_DIR/${test_name}-baseline-prompt.txt"

    echo -e "${YELLOW}Manual step required:${NC}"
    echo -e "  1. Run Claude Code (without plugin) with this prompt:"
    echo -e "     cat $RESULTS_DIR/${test_name}-baseline-prompt.txt"
    echo -e "  2. Save the response to:"
    echo -e "     $RESULTS_DIR/${test_name}-baseline-response.md"
    echo ""

    #===========================================================================
    # TEST 2: WITH PLUGIN (Using orchestrate.sh probe)
    #===========================================================================

    echo -e "${CYAN}[2/2] Analyzing WITH plugin (probe workflow)...${NC}"
    echo ""

    PLUGIN_START=$(date +%s)

    # Use probe for multi-perspective security analysis
    if "$PROJECT_ROOT/scripts/orchestrate.sh" probe "$prompt" > "$RESULTS_DIR/${test_name}-plugin-output.txt" 2>&1; then
        PLUGIN_END=$(date +%s)
        PLUGIN_TIME=$((PLUGIN_END - PLUGIN_START))

        echo -e "${GREEN}✓${NC} Plugin analysis completed in ${PLUGIN_TIME}s"

        # Extract results from probe output
        # Results are in ~/.claude-octopus/results/
        latest_results=$(find ~/.claude-octopus/results/ -name "*probe-*" -type f -mmin -5 | sort -t- -k3 -n | tail -4)

        if [ -n "$latest_results" ]; then
            echo "$latest_results" | while read result_file; do
                agent_name=$(basename "$result_file" | cut -d'-' -f1)
                echo "  Agent: $agent_name"
            done

            # Combine results
            cat $latest_results > "$RESULTS_DIR/${test_name}-plugin-raw-results.md"
        fi
    else
        echo -e "${RED}✗${NC} Plugin analysis failed"
        cat "$RESULTS_DIR/${test_name}-plugin-output.txt"
    fi

    echo ""
done

#===============================================================================
# Generate Comparison Report
#===============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Benchmark Results Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

cat > "$RESULTS_DIR/README.md" << EOF
# Benchmark Results

**Date:** $(date)
**Test Cases:** ${#test_cases[@]}

## How to Complete This Benchmark

### Step 1: Baseline Analysis (Manual)

For each test case, run Claude Code WITHOUT the plugin:

\`\`\`bash
# Read the prompt
cat $RESULTS_DIR/*-baseline-prompt.txt

# Get Claude's response (without using orchestrate.sh)
# Save to: *-baseline-response.md
\`\`\`

### Step 2: Compare Results

For each test case:

1. **Count findings** in baseline response
2. **Count findings** in plugin response
3. **Compare to ground truth** (ground-truth.json)
4. **Calculate metrics:**
   - True Positives: Issues found that are in ground truth
   - False Positives: Issues found that are NOT in ground truth
   - False Negatives: Ground truth issues that were NOT found
   - True Positive Rate: TP / (TP + FN)
   - False Positive Rate: FP / (FP + TN)
   - F1 Score: 2 × (Precision × Recall) / (Precision + Recall)

### Step 3: Compare Quality

**Baseline (Single Agent):**
- Number of issues found
- Categories covered
- Severity distribution
- Depth of analysis

**Plugin (Multi-Agent):**
- Number of issues found
- Number of perspectives (agents)
- Consensus rate
- Architectural insights
- Categories covered

## Results

| Test Case | Ground Truth | Baseline Found | Plugin Found | Baseline TP Rate | Plugin TP Rate |
|-----------|--------------|----------------|--------------|------------------|----------------|
| sql-injection-login | $expected_issues | TBD | TBD | TBD | TBD |

## Analysis

### Detection Effectiveness

TBD - Complete manual baseline analysis first

### Multi-Agent Value

TBD - Compare multi-perspective findings vs single analysis

### Recommendations

TBD - Based on results
EOF

echo -e "${GREEN}✓ Benchmark setup complete!${NC}"
echo ""
echo -e "${YELLOW}Results saved to:${NC}"
echo "  $RESULTS_DIR"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Complete baseline analysis (see $RESULTS_DIR/README.md)"
echo "  2. Compare findings against ground truth"
echo "  3. Calculate TP/FP/FN rates"
echo "  4. Generate final report"
echo ""
echo -e "${YELLOW}Plugin results are already captured in:${NC}"
echo "  $RESULTS_DIR/*-plugin-raw-results.md"
echo ""
