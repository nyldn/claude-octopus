#!/bin/bash
# Test: Cron Expression Parser
# Unit tests for scripts/scheduler/cron.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "${PROJECT_ROOT}/scripts/scheduler/cron.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================================"
echo "  Cron Expression Parser - Unit Tests"
echo "================================================================"
echo ""

FAILED=0
PASSED=0

# Helper: assert cron matches
assert_match() {
    local desc="$1" expr="$2" min="$3" hour="$4" day="$5" month="$6" wday="$7"
    if cron_matches "$expr" "$min" "$hour" "$day" "$month" "$wday" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} MATCH: $desc ($expr @ $min:$hour d=$day m=$month w=$wday)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} EXPECTED MATCH: $desc ($expr @ $min:$hour d=$day m=$month w=$wday)"
        FAILED=$((FAILED + 1))
    fi
}

# Helper: assert cron does NOT match
assert_no_match() {
    local desc="$1" expr="$2" min="$3" hour="$4" day="$5" month="$6" wday="$7"
    if cron_matches "$expr" "$min" "$hour" "$day" "$month" "$wday" 2>/dev/null; then
        echo -e "${RED}✗${NC} EXPECTED NO MATCH: $desc ($expr @ $min:$hour d=$day m=$month w=$wday)"
        FAILED=$((FAILED + 1))
    else
        echo -e "${GREEN}✓${NC} NO MATCH: $desc ($expr @ $min:$hour d=$day m=$month w=$wday)"
        PASSED=$((PASSED + 1))
    fi
}

# Helper: assert validation result
assert_valid() {
    local desc="$1" expr="$2"
    if cron_validate "$expr" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} VALID: $desc ($expr)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} EXPECTED VALID: $desc ($expr)"
        FAILED=$((FAILED + 1))
    fi
}

assert_invalid() {
    local desc="$1" expr="$2"
    if cron_validate "$expr" 2>/dev/null; then
        echo -e "${RED}✗${NC} EXPECTED INVALID: $desc ($expr)"
        FAILED=$((FAILED + 1))
    else
        echo -e "${GREEN}✓${NC} INVALID: $desc ($expr)"
        PASSED=$((PASSED + 1))
    fi
}

echo "--- Wildcard Tests ---"
assert_match    "all wildcards"         "* * * * *"   0  0  1  1  1
assert_match    "all wildcards midday"  "* * * * *"   30 12 15 6  3

echo ""
echo "--- Exact Match Tests ---"
assert_match    "exact minute"          "30 * * * *"  30 12 15 6  3
assert_no_match "wrong minute"          "30 * * * *"  0  12 15 6  3
assert_match    "exact hour"            "* 14 * * *"  0  14 15 6  3
assert_no_match "wrong hour"            "* 14 * * *"  0  12 15 6  3
assert_match    "exact min+hour"        "0 2 * * *"   0  2  15 6  3
assert_no_match "wrong min, right hour" "30 2 * * *"  0  2  15 6  3

echo ""
echo "--- Range Tests ---"
assert_match    "minute in range"       "0-30 * * * *"  15 12 15 6  3
assert_match    "minute at range start" "0-30 * * * *"  0  12 15 6  3
assert_match    "minute at range end"   "0-30 * * * *"  30 12 15 6  3
assert_no_match "minute outside range"  "0-30 * * * *"  45 12 15 6  3
assert_match    "weekday range Mon-Fri" "* * * * 1-5"   0  12 15 6  3
assert_no_match "weekday outside range" "* * * * 1-5"   0  12 15 6  0

echo ""
echo "--- Step Tests ---"
assert_match    "every 15 min (0)"      "*/15 * * * *"  0  12 15 6  3
assert_match    "every 15 min (15)"     "*/15 * * * *"  15 12 15 6  3
assert_match    "every 15 min (30)"     "*/15 * * * *"  30 12 15 6  3
assert_match    "every 15 min (45)"     "*/15 * * * *"  45 12 15 6  3
assert_no_match "every 15 min (7)"      "*/15 * * * *"  7  12 15 6  3
assert_match    "every 2 hours (0)"     "0 */2 * * *"   0  0  15 6  3
assert_match    "every 2 hours (4)"     "0 */2 * * *"   0  4  15 6  3
assert_no_match "every 2 hours (3)"     "0 */2 * * *"   0  3  15 6  3

echo ""
echo "--- Range+Step Tests ---"
assert_match    "1-30/5 at 5"           "1-30/5 * * * *"  6  12 15 6  3
assert_match    "1-30/5 at 1"           "1-30/5 * * * *"  1  12 15 6  3
assert_no_match "1-30/5 at 3"           "1-30/5 * * * *"  3  12 15 6  3
assert_no_match "1-30/5 at 35"          "1-30/5 * * * *"  35 12 15 6  3

echo ""
echo "--- List Tests ---"
assert_match    "list (1)"              "1,15,30 * * * *" 1  12 15 6  3
assert_match    "list (15)"             "1,15,30 * * * *" 15 12 15 6  3
assert_match    "list (30)"             "1,15,30 * * * *" 30 12 15 6  3
assert_no_match "list (7)"              "1,15,30 * * * *" 7  12 15 6  3

echo ""
echo "--- Shortcut Tests ---"
assert_match    "@hourly at :00"        "@hourly"     0  12 15 6  3
assert_no_match "@hourly at :30"        "@hourly"     30 12 15 6  3
assert_match    "@daily at midnight"    "@daily"      0  0  15 6  3
assert_no_match "@daily at noon"        "@daily"      0  12 15 6  3
assert_match    "@weekly on Sunday"     "@weekly"     0  0  15 6  0
assert_no_match "@weekly on Monday"     "@weekly"     0  0  15 6  1
assert_match    "@monthly on 1st"       "@monthly"    0  0  1  6  3
assert_no_match "@monthly on 15th"      "@monthly"    0  0  15 6  3

echo ""
echo "--- Day-of-month + Day-of-week OR Logic ---"
# When both day and weekday are specified, standard cron uses OR
assert_match    "day=15 OR wday=1 (day matches)"   "0 0 15 * 1"  0  0  15 6  3
assert_match    "day=15 OR wday=1 (wday matches)"  "0 0 15 * 1"  0  0  10 6  1
assert_no_match "day=15 OR wday=1 (neither match)" "0 0 15 * 1"  0  0  10 6  3

echo ""
echo "--- Validation Tests ---"
assert_valid    "standard 5-field"      "0 2 * * *"
assert_valid    "all wildcards"         "* * * * *"
assert_valid    "complex expression"    "*/15 0-6 1,15 * 1-5"
assert_invalid  "3 fields only"         "0 2 *"
assert_invalid  "6 fields"             "0 2 * * * *"

echo ""
echo "--- Real-World Cron Patterns ---"
assert_match    "nightly 2am"           "0 2 * * *"       0  2  16 2  1
assert_no_match "nightly 2am at 3am"    "0 2 * * *"       0  3  16 2  1
assert_match    "weekday 9am"           "0 9 * * 1-5"     0  9  17 2  2
assert_no_match "weekday 9am on Sat"    "0 9 * * 1-5"     0  9  21 2  6
assert_match    "quarterly 1st Jan"     "0 0 1 1,4,7,10 *" 0 0  1  1  4

echo ""
echo "================================================================"
echo "  Test Results Summary"
echo "================================================================"
echo ""
echo "Total Tests: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"

exit $([[ $FAILED -eq 0 ]] && echo 0 || echo 1)
