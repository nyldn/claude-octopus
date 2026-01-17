#!/usr/bin/env bash
# Simple Benchmark: Claude Native vs Claude Octopus
# Bash 3.2 compatible version (macOS default)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BENCHMARK_DIR="${PROJECT_ROOT}/.benchmark-results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$BENCHMARK_DIR"

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Claude Native vs Claude Octopus Benchmark               ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Test task
TASK="Review this authentication code for security issues:
function login(username, password) {
  const query = 'SELECT * FROM users WHERE username = \"' + username + '\" AND password = \"' + password + '\"';
  const user = db.query(query);
  if (user) {
    localStorage.setItem('token', user.id);
    return true;
  }
  return false;
}"

echo -e "${YELLOW}Test Task:${NC} Security code review"
echo ""

# Run Claude Native
echo -e "${CYAN}[1/2] Running Claude Native (Opus 4.5)...${NC}"
CLAUDE_START=$(date +%s)

if claude --model opus-4 "$TASK" > "${BENCHMARK_DIR}/claude-native-${TIMESTAMP}.md" 2>&1; then
    CLAUDE_END=$(date +%s)
    CLAUDE_TIME=$((CLAUDE_END - CLAUDE_START))
    CLAUDE_WORDS=$(wc -w < "${BENCHMARK_DIR}/claude-native-${TIMESTAMP}.md" | tr -d ' ')
    CLAUDE_COST=$(echo "scale=4; $CLAUDE_WORDS * 0.015 / 1000" | bc)

    echo -e "${GREEN}✓${NC} Claude Native completed in ${CLAUDE_TIME}s (~\$${CLAUDE_COST})"
else
    echo -e "Claude Native failed"
    CLAUDE_TIME="N/A"
    CLAUDE_COST="N/A"
fi

echo ""

# Run Claude Octopus
echo -e "${CYAN}[2/2] Running Claude Octopus (auto-routing)...${NC}"
OCTOPUS_START=$(date +%s)

if "$PROJECT_ROOT/scripts/orchestrate.sh" auto "$TASK" > "${BENCHMARK_DIR}/octopus-${TIMESTAMP}.md" 2>&1; then
    OCTOPUS_END=$(date +%s)
    OCTOPUS_TIME=$((OCTOPUS_END - OCTOPUS_START))

    # Count result files
    RESULT_COUNT=$(find "$PROJECT_ROOT/.claude-octopus/results" -type f -newer "${BENCHMARK_DIR}/octopus-${TIMESTAMP}.md" 2>/dev/null | wc -l | tr -d ' ')
    OCTOPUS_COST=$(echo "scale=4; $RESULT_COUNT * 0.02" | bc)

    echo -e "${GREEN}✓${NC} Claude Octopus completed in ${OCTOPUS_TIME}s (~\$${OCTOPUS_COST})"
else
    echo -e "Claude Octopus failed"
    OCTOPUS_TIME="N/A"
    OCTOPUS_COST="N/A"
fi

echo ""

# Generate report
REPORT_FILE="${BENCHMARK_DIR}/benchmark-report-${TIMESTAMP}.md"

cat > "$REPORT_FILE" << EOF
# Claude Native vs Claude Octopus Benchmark Report

**Generated:** $(date)
**Test:** Security code review

---

## Test Task

Review this authentication code for security issues:

\`\`\`javascript
function login(username, password) {
  const query = 'SELECT * FROM users WHERE username = "' + username + '" AND password = "' + password + '"';
  const user = db.query(query);
  if (user) {
    localStorage.setItem('token', user.id);
    return true;
  }
  return false;
}
\`\`\`

---

## Results

| Metric | Claude Native | Claude Octopus | Winner |
|--------|---------------|----------------|--------|
| **Speed** | ${CLAUDE_TIME}s | ${OCTOPUS_TIME}s | $([ "$CLAUDE_TIME" != "N/A" ] && [ "$OCTOPUS_TIME" != "N/A" ] && [ "$CLAUDE_TIME" -lt "$OCTOPUS_TIME" ] && echo "🏆 Claude Native" || echo "🏆 Claude Octopus") |
| **Cost** | \$${CLAUDE_COST} | \$${OCTOPUS_COST} | $([ "$CLAUDE_COST" != "N/A" ] && [ "$OCTOPUS_COST" != "N/A" ] && echo "🏆 Claude Native" || echo "Octopus") |

---

## Output Analysis

### Claude Native Output

EOF

# Add Claude native output
if [[ -f "${BENCHMARK_DIR}/claude-native-${TIMESTAMP}.md" ]]; then
    cat "${BENCHMARK_DIR}/claude-native-${TIMESTAMP}.md" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << EOF

---

### Claude Octopus Output

EOF

# Add Octopus output
if [[ -f "${BENCHMARK_DIR}/octopus-${TIMESTAMP}.md" ]]; then
    cat "${BENCHMARK_DIR}/octopus-${TIMESTAMP}.md" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << EOF

---

## Findings

### Speed Comparison

EOF

if [[ "$CLAUDE_TIME" != "N/A" && "$OCTOPUS_TIME" != "N/A" ]]; then
    TIME_DIFF=$((OCTOPUS_TIME - CLAUDE_TIME))
    if [[ $TIME_DIFF -gt 0 ]]; then
        cat >> "$REPORT_FILE" << EOF
Claude Octopus took **${TIME_DIFF} seconds longer** than Claude Native. This is expected due to multi-agent coordination overhead.
EOF
    else
        cat >> "$REPORT_FILE" << EOF
Claude Octopus completed faster, likely due to parallel execution optimizations.
EOF
    fi
fi

cat >> "$REPORT_FILE" << EOF

### Cost Comparison

EOF

if [[ "$CLAUDE_COST" != "N/A" && "$OCTOPUS_COST" != "N/A" ]]; then
    COST_RATIO=$(echo "scale=2; $OCTOPUS_COST / $CLAUDE_COST" | bc)
    cat >> "$REPORT_FILE" << EOF
Claude Octopus cost approximately **${COST_RATIO}x** more than Claude Native due to multiple agent invocations.
EOF
fi

cat >> "$REPORT_FILE" << EOF

### Value Proposition

Claude Octopus provides:
- **Multi-perspective analysis**: Multiple agents review from different angles
- **Quality gates**: Consensus-based validation reduces errors
- **Comprehensive coverage**: Parallel research catches edge cases
- **Structured workflow**: Double Diamond methodology ensures thoroughness

The additional cost and time overhead is justified for:
- Critical security reviews
- Complex architectural decisions
- High-stakes code changes
- Comprehensive research tasks

For simple, straightforward tasks, Claude Native may be more appropriate.

---

*Benchmark ID: ${TIMESTAMP}*
EOF

echo -e "${GREEN}✓ Benchmark complete!${NC}"
echo ""
echo -e "${YELLOW}Report saved to:${NC}"
echo "$REPORT_FILE"
echo ""
echo "View the report:"
echo "  cat $REPORT_FILE"
echo ""

# Display summary
cat "$REPORT_FILE"
