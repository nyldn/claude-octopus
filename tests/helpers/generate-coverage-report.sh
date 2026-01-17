#!/bin/bash
# tests/helpers/generate-coverage-report.sh
# Generates test coverage report for Claude Octopus functions

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"
TESTS_DIR="$PROJECT_ROOT/tests"

# Output files
REPORT_FILE="${1:-coverage-report.txt}"
HTML_REPORT="${2:-coverage-report.html}"

# Minimum coverage threshold
MIN_COVERAGE=${MIN_COVERAGE:-80}

echo -e "${BLUE}Generating Test Coverage Report...${NC}\n"

#==============================================================================
# Extract Functions from orchestrate.sh
#==============================================================================

extract_functions() {
    if [[ ! -f "$ORCHESTRATE" ]]; then
        echo -e "${RED}ERROR: orchestrate.sh not found at $ORCHESTRATE${NC}"
        exit 1
    fi

    # Extract function names (functions defined as "function_name()")
    grep -E "^[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$ORCHESTRATE" | sed 's/().*$//' | sort -u
}

#==============================================================================
# Find Tests for Functions
#==============================================================================

find_tests_for_function() {
    local func_name="$1"

    # Search all test files for references to this function
    if grep -r -q "$func_name" "$TESTS_DIR" --include="*.sh" 2>/dev/null; then
        return 0  # Function is tested
    else
        return 1  # Function is not tested
    fi
}

#==============================================================================
# Generate Coverage Statistics
#==============================================================================

generate_report() {
    local functions=($(extract_functions))
    local total_functions=${#functions[@]}
    local tested_functions=0
    local untested_functions=()

    echo "Analyzing $total_functions functions..."

    for func in "${functions[@]}"; do
        if find_tests_for_function "$func"; then
            tested_functions=$((tested_functions + 1))
        else
            untested_functions+=("$func")
        fi
    done

    local coverage_percent=$((tested_functions * 100 / total_functions))

    # Generate text report
    {
        echo "Claude Octopus Test Coverage Report"
        echo "===================================="
        echo ""
        echo "Generated: $(date)"
        echo ""
        echo "Summary:"
        echo "--------"
        echo "Total functions:      $total_functions"
        echo "Tested functions:     $tested_functions"
        echo "Untested functions:   ${#untested_functions[@]}"
        echo "Coverage:             ${coverage_percent}%"
        echo ""

        if [[ ${#untested_functions[@]} -gt 0 ]]; then
            echo "Untested Functions:"
            echo "-------------------"
            for func in "${untested_functions[@]}"; do
                echo "  - $func"
            done
            echo ""
        fi

        echo "Test Files:"
        echo "-----------"
        find "$TESTS_DIR" -name "test-*.sh" -type f | sed 's|.*tests/|  - |' | sort
        echo ""

        echo "Coverage by Category:"
        echo "--------------------"
        local smoke_count=$(find "$TESTS_DIR/smoke" -name "test-*.sh" 2>/dev/null | wc -l)
        local unit_count=$(find "$TESTS_DIR/unit" -name "test-*.sh" 2>/dev/null | wc -l)
        local integration_count=$(find "$TESTS_DIR/integration" -name "test-*.sh" 2>/dev/null | wc -l)
        local e2e_count=$(find "$TESTS_DIR/e2e" -name "test-*.sh" 2>/dev/null | wc -l)

        echo "  Smoke tests:        $smoke_count"
        echo "  Unit tests:         $unit_count"
        echo "  Integration tests:  $integration_count"
        echo "  E2E tests:          $e2e_count"
        echo ""

    } > "$REPORT_FILE"

    # Generate HTML report
    generate_html_report "$total_functions" "$tested_functions" "$coverage_percent" "${untested_functions[@]}"

    # Print summary to console
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Coverage Report${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Total functions:      $total_functions"
    echo -e "Tested functions:     ${GREEN}$tested_functions${NC}"
    echo -e "Untested functions:   ${RED}${#untested_functions[@]}${NC}"

    if [[ $coverage_percent -ge $MIN_COVERAGE ]]; then
        echo -e "Coverage:             ${GREEN}${coverage_percent}%${NC} (≥${MIN_COVERAGE}%)"
    else
        echo -e "Coverage:             ${RED}${coverage_percent}%${NC} (<${MIN_COVERAGE}%)"
    fi

    echo ""
    echo -e "Reports generated:"
    echo -e "  Text: $REPORT_FILE"
    echo -e "  HTML: $HTML_REPORT"
    echo ""

    # Check threshold
    if [[ $coverage_percent -lt $MIN_COVERAGE ]]; then
        echo -e "${RED}WARNING: Coverage below ${MIN_COVERAGE}% threshold${NC}"
        echo -e "${YELLOW}Add tests for untested functions to improve coverage${NC}"
        return 1
    else
        echo -e "${GREEN}✓ Coverage meets ${MIN_COVERAGE}% threshold${NC}"
        return 0
    fi
}

#==============================================================================
# HTML Report Generation
#==============================================================================

generate_html_report() {
    local total="$1"
    local tested="$2"
    local percent="$3"
    shift 3
    local untested=("$@")

    local color
    if [[ $percent -ge 90 ]]; then
        color="#4caf50"  # Green
    elif [[ $percent -ge 75 ]]; then
        color="#ff9800"  # Orange
    else
        color="#f44336"  # Red
    fi

    cat > "$HTML_REPORT" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Claude Octopus - Test Coverage Report</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            max-width: 1200px;
            margin: 40px auto;
            padding: 0 20px;
            background: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
        }
        .header .subtitle {
            opacity: 0.9;
            margin-top: 5px;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .stat-card h3 {
            margin: 0 0 10px 0;
            color: #666;
            font-size: 0.9em;
            text-transform: uppercase;
        }
        .stat-card .value {
            font-size: 2em;
            font-weight: bold;
            color: #333;
        }
        .progress {
            background: #e0e0e0;
            height: 30px;
            border-radius: 15px;
            overflow: hidden;
            margin: 20px 0;
        }
        .progress-bar {
            height: 100%;
            background: $color;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            transition: width 0.3s ease;
        }
        .section {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        .section h2 {
            margin-top: 0;
            color: #333;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        .function-list {
            list-style: none;
            padding: 0;
        }
        .function-list li {
            padding: 8px 12px;
            margin: 4px 0;
            background: #f9f9f9;
            border-left: 3px solid #f44336;
            font-family: monospace;
        }
        .test-file {
            padding: 8px 12px;
            margin: 4px 0;
            background: #f0f7ff;
            border-left: 3px solid #2196f3;
            font-family: monospace;
        }
        .timestamp {
            color: #999;
            font-size: 0.9em;
            text-align: center;
            margin-top: 30px;
            padding: 20px;
        }
        .badge {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 0.85em;
            font-weight: bold;
        }
        .badge-success { background: #4caf50; color: white; }
        .badge-warning { background: #ff9800; color: white; }
        .badge-danger { background: #f44336; color: white; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🐙 Claude Octopus</h1>
        <div class="subtitle">Test Coverage Report</div>
    </div>

    <div class="stats">
        <div class="stat-card">
            <h3>Total Functions</h3>
            <div class="value">$total</div>
        </div>
        <div class="stat-card">
            <h3>Tested</h3>
            <div class="value" style="color: #4caf50;">$tested</div>
        </div>
        <div class="stat-card">
            <h3>Untested</h3>
            <div class="value" style="color: #f44336;">${#untested[@]}</div>
        </div>
        <div class="stat-card">
            <h3>Coverage</h3>
            <div class="value" style="color: $color;">$percent%</div>
        </div>
    </div>

    <div class="progress">
        <div class="progress-bar" style="width: $percent%; background: $color;">
            $percent%
        </div>
    </div>

    <div class="section">
        <h2>Coverage Status</h2>
        <p>
            <span class="badge badge-$(if [[ $percent -ge 90 ]]; then echo "success"; elif [[ $percent -ge 75 ]]; then echo "warning"; else echo "danger"; fi)">
                $percent% Coverage
            </span>
            Threshold: ${MIN_COVERAGE}%
        </p>
    </div>
EOF

    if [[ ${#untested[@]} -gt 0 ]]; then
        cat >> "$HTML_REPORT" <<EOF
    <div class="section">
        <h2>Untested Functions (${#untested[@]})</h2>
        <ul class="function-list">
EOF
        for func in "${untested[@]}"; do
            echo "            <li>$func</li>" >> "$HTML_REPORT"
        done
        echo "        </ul>" >> "$HTML_REPORT"
        echo "    </div>" >> "$HTML_REPORT"
    fi

    cat >> "$HTML_REPORT" <<EOF
    <div class="section">
        <h2>Test Files</h2>
        <div class="test-file">Smoke: $(find "$TESTS_DIR/smoke" -name "test-*.sh" 2>/dev/null | wc -l) files</div>
        <div class="test-file">Unit: $(find "$TESTS_DIR/unit" -name "test-*.sh" 2>/dev/null | wc -l) files</div>
        <div class="test-file">Integration: $(find "$TESTS_DIR/integration" -name "test-*.sh" 2>/dev/null | wc -l) files</div>
        <div class="test-file">E2E: $(find "$TESTS_DIR/e2e" -name "test-*.sh" 2>/dev/null | wc -l) files</div>
    </div>

    <div class="timestamp">
        Generated: $(date)<br>
        Claude Octopus v4.9.0
    </div>
</body>
</html>
EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
