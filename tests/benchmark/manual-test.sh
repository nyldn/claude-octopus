#!/usr/bin/env bash
# Manual Benchmark Test Script
# Helps users test Claude with/without plugin and compare results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_CASE_DIR="$SCRIPT_DIR/test-cases/vulnerable/sql-injection-login"
RESULTS_DIR="$PROJECT_ROOT/.dev/benchmarks/manual"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

#===============================================================================
# Helper Functions
#===============================================================================

show_header() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_code() {
    local code_file="$1"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Vulnerable Code (Flask Authentication Module)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cat "$code_file"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

show_prompt() {
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Analysis Prompt (copy this to Claude Code)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cat "$RESULTS_DIR/analysis-prompt.txt"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

capture_response() {
    local output_file="$1"
    local plugin_status="$2"

    echo -e "${MAGENTA}Please paste Claude's complete response below.${NC}"
    echo -e "${MAGENTA}When finished, press Ctrl+D (or Cmd+D on Mac) to save.${NC}"
    echo ""
    echo -e "${CYAN}Waiting for input...${NC}"
    echo ""

    # Capture multi-line input until EOF (Ctrl+D)
    cat > "$output_file"

    if [ -s "$output_file" ]; then
        local line_count=$(wc -l < "$output_file")
        echo ""
        echo -e "${GREEN}✓ Response saved ($line_count lines)${NC}"
        echo -e "${GREEN}  Location: $output_file${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}✗ No response captured${NC}"
        return 1
    fi
}

#===============================================================================
# Command: with-plugin
#===============================================================================

cmd_with_plugin() {
    show_header "MANUAL TEST: WITH PLUGIN ENABLED                  "

    # Copy code and prompt to results for reference
    cp "$TEST_CASE_DIR/code.py" "$RESULTS_DIR/vulnerable-code.py"

    # Generate analysis prompt
    cat > "$RESULTS_DIR/analysis-prompt.txt" << 'EOF'
Review this Python code for security vulnerabilities. List ALL security issues found with:
1. Severity (CRITICAL/HIGH/MEDIUM/LOW)
2. CWE category
3. Line number
4. Description
5. Attack vector

Code to analyze:
```python
EOF
    cat "$TEST_CASE_DIR/code.py" >> "$RESULTS_DIR/analysis-prompt.txt"
    cat >> "$RESULTS_DIR/analysis-prompt.txt" << 'EOF'
```

Be comprehensive and list every vulnerability, even minor ones.
EOF

    # Show the code
    show_code "$TEST_CASE_DIR/code.py"

    # Show the prompt
    show_prompt

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}INSTRUCTIONS${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}1. VERIFY PLUGIN IS ENABLED${NC}"
    echo "   Check: ls ~/.claude/plugins/claude-octopus"
    echo ""
    echo -e "${CYAN}2. COPY THE PROMPT ABOVE${NC}"
    echo "   Paste it into Claude Code (this session or a new one)"
    echo ""
    echo -e "${CYAN}3. WAIT FOR FULL RESPONSE${NC}"
    echo "   Let Claude complete the full security analysis"
    echo "   (May take 1-2 minutes with multi-agent orchestration)"
    echo ""
    echo -e "${CYAN}4. COPY CLAUDE'S COMPLETE RESPONSE${NC}"
    echo "   Select all of Claude's analysis"
    echo ""
    echo -e "${CYAN}5. PASTE THE RESPONSE BELOW${NC}"
    echo "   After pasting, press Ctrl+D (or Cmd+D) to finish"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Capture response
    if capture_response "$RESULTS_DIR/with-plugin-response.md" "WITH plugin"; then
        echo ""
        echo -e "${GREEN}✓ Step 1 complete!${NC}"
        echo ""
        echo -e "${CYAN}Next step:${NC}"
        echo "  1. Disable the plugin:"
        echo "     ${YELLOW}mv ~/.claude/plugins/claude-octopus{,.disabled}${NC}"
        echo ""
        echo "  2. Run without plugin:"
        echo "     ${YELLOW}./tests/benchmark/manual-test.sh without-plugin${NC}"
        echo ""
    else
        echo -e "${RED}Failed to capture response. Please try again.${NC}"
        exit 1
    fi
}

#===============================================================================
# Command: without-plugin
#===============================================================================

cmd_without_plugin() {
    show_header "MANUAL TEST: WITHOUT PLUGIN (BASELINE)            "

    # Verify plugin is disabled
    if [ -d "$HOME/.claude/plugins/claude-octopus" ]; then
        echo -e "${RED}⚠ WARNING: Plugin appears to still be enabled!${NC}"
        echo ""
        echo "Please disable it first:"
        echo "  ${YELLOW}mv ~/.claude/plugins/claude-octopus{,.disabled}${NC}"
        echo ""
        echo "Then run this command again."
        exit 1
    fi

    echo -e "${GREEN}✓ Plugin is disabled${NC}"
    echo ""

    # Show the code
    show_code "$TEST_CASE_DIR/code.py"

    # Show the prompt (same as before)
    show_prompt

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}INSTRUCTIONS${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}1. PLUGIN IS DISABLED ✓${NC}"
    echo ""
    echo -e "${CYAN}2. COPY THE PROMPT ABOVE (same as before)${NC}"
    echo "   Paste it into Claude Code"
    echo ""
    echo -e "${CYAN}3. WAIT FOR FULL RESPONSE${NC}"
    echo "   Let Claude complete the security analysis"
    echo "   (Should be faster - single agent, no orchestration)"
    echo ""
    echo -e "${CYAN}4. COPY CLAUDE'S COMPLETE RESPONSE${NC}"
    echo "   Select all of Claude's analysis"
    echo ""
    echo -e "${CYAN}5. PASTE THE RESPONSE BELOW${NC}"
    echo "   After pasting, press Ctrl+D (or Cmd+D) to finish"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Capture response
    if capture_response "$RESULTS_DIR/without-plugin-response.md" "WITHOUT plugin"; then
        echo ""
        echo -e "${GREEN}✓ Step 2 complete!${NC}"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo "  1. Re-enable the plugin:"
        echo "     ${YELLOW}mv ~/.claude/plugins/claude-octopus{.disabled,}${NC}"
        echo ""
        echo "  2. Compare results:"
        echo "     ${YELLOW}./tests/benchmark/manual-test.sh compare${NC}"
        echo ""
    else
        echo -e "${RED}Failed to capture response. Please try again.${NC}"
        exit 1
    fi
}

#===============================================================================
# Command: compare
#===============================================================================

cmd_compare() {
    show_header "COMPARING RESULTS                                  "

    # Check both files exist
    if [ ! -f "$RESULTS_DIR/with-plugin-response.md" ]; then
        echo -e "${RED}✗ Missing: with-plugin-response.md${NC}"
        echo "  Please run: ./tests/benchmark/manual-test.sh with-plugin"
        exit 1
    fi

    if [ ! -f "$RESULTS_DIR/without-plugin-response.md" ]; then
        echo -e "${RED}✗ Missing: without-plugin-response.md${NC}"
        echo "  Please run: ./tests/benchmark/manual-test.sh without-plugin"
        exit 1
    fi

    echo -e "${GREEN}✓ Found both responses${NC}"
    echo ""

    # Load ground truth
    local ground_truth="$TEST_CASE_DIR/ground-truth.json"
    local expected_total=$(jq '.expected_issues | length' "$ground_truth")

    echo -e "${CYAN}Ground Truth: $expected_total known vulnerabilities${NC}"
    echo ""

    # Count issues in each response (simple heuristic: look for CWE- mentions)
    local with_plugin_issues=$(grep -o 'CWE-[0-9]\+' "$RESULTS_DIR/with-plugin-response.md" | sort -u | wc -l | tr -d ' ')
    local without_plugin_issues=$(grep -o 'CWE-[0-9]\+' "$RESULTS_DIR/without-plugin-response.md" | sort -u | wc -l | tr -d ' ')

    echo -e "${CYAN}Analysis:${NC}"
    echo "  WITH plugin:    $with_plugin_issues unique CWE categories found"
    echo "  WITHOUT plugin: $without_plugin_issues unique CWE categories found"
    echo "  Expected:       $expected_total vulnerabilities"
    echo ""

    # Generate comparison report
    cat > "$RESULTS_DIR/COMPARISON-REPORT.md" << EOF
# Benchmark Comparison Report

**Date**: $(date)
**Test Case**: SQL Injection Login Vulnerability

---

## Summary

| Metric | WITH Plugin | WITHOUT Plugin | Ground Truth |
|--------|-------------|----------------|--------------|
| Unique CWE Categories | $with_plugin_issues | $without_plugin_issues | $expected_total |
| Response Size (lines) | $(wc -l < "$RESULTS_DIR/with-plugin-response.md") | $(wc -l < "$RESULTS_DIR/without-plugin-response.md") | - |

---

## Detailed Analysis

### Expected Vulnerabilities (Ground Truth)

$(jq -r '.expected_issues[] | "**\(.id). \(.category)** (CWE-\(.cwe | ltrimstr("CWE-")))\n- Severity: \(.severity)\n- Location: \(.location)\n- Description: \(.description)\n"' "$ground_truth")

---

## WITH Plugin Response

**Analysis Preview** (first 100 lines):
\`\`\`
$(head -100 "$RESULTS_DIR/with-plugin-response.md")
\`\`\`

**Full response**: See \`with-plugin-response.md\`

---

## WITHOUT Plugin Response

**Analysis Preview** (first 100 lines):
\`\`\`
$(head -100 "$RESULTS_DIR/without-plugin-response.md")
\`\`\`

**Full response**: See \`without-plugin-response.md\`

---

## Comparison Analysis

### Quantitative Metrics

- **Detection Rate (WITH)**: $with_plugin_issues/$expected_total CWE categories
- **Detection Rate (WITHOUT)**: $without_plugin_issues/$expected_total CWE categories
- **Difference**: $((with_plugin_issues - without_plugin_issues)) additional CWE categories

### Qualitative Assessment

**To complete this analysis, ask Claude to:**
1. Review both responses side-by-side
2. Identify which vulnerabilities each found
3. Calculate True/False Positives/Negatives
4. Assess depth and quality of analysis
5. Determine if plugin added measurable value

**Suggested prompt for Claude:**

\`\`\`
I ran a benchmark test comparing your security analysis with and without the claude-octopus plugin.

Test case: Flask authentication with 12 known vulnerabilities

Files:
- Ground truth: tests/benchmark/test-cases/vulnerable/sql-injection-login/ground-truth.json
- WITH plugin: .dev/benchmarks/manual/with-plugin-response.md
- WITHOUT plugin: .dev/benchmarks/manual/without-plugin-response.md

Please:
1. Compare both responses to ground truth
2. Calculate True Positive, False Positive, False Negative rates
3. Assess quality differences (depth, actionability, accuracy)
4. Determine if the multi-agent plugin provided measurable value
5. Recommend whether to use the plugin for security reviews

Be objective and quantitative. If the baseline (without plugin) performed just as well, acknowledge that.
\`\`\`

---

## Files

All results saved to: \`.dev/benchmarks/manual/\`

- \`vulnerable-code.py\` - Test case code
- \`analysis-prompt.txt\` - Exact prompt used
- \`with-plugin-response.md\` - Response WITH plugin
- \`without-plugin-response.md\` - Response WITHOUT plugin
- \`COMPARISON-REPORT.md\` - This file

---

## Next Steps

1. Review both responses manually
2. Ask Claude to analyze the comparison (use prompt above)
3. Decide if plugin adds value for your use cases
4. Consider testing with harder/more complex test cases

EOF

    echo -e "${GREEN}✓ Comparison report generated!${NC}"
    echo ""
    echo -e "${CYAN}Report saved to:${NC}"
    echo "  $RESULTS_DIR/COMPARISON-REPORT.md"
    echo ""
    echo -e "${CYAN}To complete the analysis:${NC}"
    echo "  1. Read the comparison report:"
    echo "     ${YELLOW}cat $RESULTS_DIR/COMPARISON-REPORT.md${NC}"
    echo ""
    echo "  2. Ask Claude to analyze it (copy this prompt):"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cat << 'PROMPT'
I ran a benchmark test comparing your security analysis with and without the claude-octopus plugin.

Test case: Flask authentication with 12 known vulnerabilities

Files:
- Ground truth: tests/benchmark/test-cases/vulnerable/sql-injection-login/ground-truth.json
- WITH plugin: .dev/benchmarks/manual/with-plugin-response.md
- WITHOUT plugin: .dev/benchmarks/manual/without-plugin-response.md

Please:
1. Compare both responses to ground truth
2. Calculate True Positive, False Positive, False Negative rates
3. Assess quality differences (depth, actionability, accuracy)
4. Determine if the multi-agent plugin provided measurable value
5. Recommend whether to use the plugin for security reviews

Be objective and quantitative. If the baseline (without plugin) performed just as well, acknowledge that.
PROMPT
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

#===============================================================================
# Command: clean
#===============================================================================

cmd_clean() {
    echo -e "${YELLOW}Cleaning all manual test results...${NC}"
    rm -rf "$RESULTS_DIR"/*
    echo -e "${GREEN}✓ Cleaned: $RESULTS_DIR${NC}"
}

#===============================================================================
# Main
#===============================================================================

usage() {
    echo "Usage: $0 {with-plugin|without-plugin|compare|clean}"
    echo ""
    echo "Commands:"
    echo "  with-plugin      - Run test WITH claude-octopus plugin enabled"
    echo "  without-plugin   - Run test WITHOUT plugin (baseline)"
    echo "  compare          - Compare results and generate report"
    echo "  clean            - Remove all test results"
    echo ""
    echo "For detailed instructions, see: tests/benchmark/MANUAL-TEST-GUIDE.md"
    exit 1
}

# Main command dispatch
case "${1:-}" in
    with-plugin)
        cmd_with_plugin
        ;;
    without-plugin)
        cmd_without_plugin
        ;;
    compare)
        cmd_compare
        ;;
    clean)
        cmd_clean
        ;;
    *)
        usage
        ;;
esac
