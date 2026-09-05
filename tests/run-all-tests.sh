#!/usr/bin/env bash
# Run all test suites for Claude Octopus plugin
# This is the main test entry point
#
# Usage:
#   ./run-all-tests.sh [OPTIONS] [--CATEGORY ...]
#
# Categories (combine multiple):
#   --smoke         Tests in smoke/
#   --unit          Tests in unit/
#   --integration   Tests in integration/
#   --root          Root-level test-*.sh and validate-*.sh
#   --live          Tests in live/ (requires real CLIs, opt-in)
#   --all           All categories except live (default)
#   --everything    All categories including live
#
# Options:
#   --fail-fast     Stop on first suite failure
#   --list          List discovered tests without running them
#   --suite=PATH    Run one explicit suite path relative to tests/ (repeatable)
#   --shard-index=N Zero-based deterministic shard index (default: 0)
#   --shard-count=N Number of deterministic shards (default: 1)
#   --shard-weights=PATH Duration weights (default: tests/shard-weights.tsv)
#   --symlink-sensitive  Keep only unit suites that exercise path indirection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Track overall results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0
FAIL_FAST=false
LIST_ONLY=false
SHARD_INDEX=0
SHARD_COUNT=1
SHARD_WEIGHTS_FILE="$SCRIPT_DIR/shard-weights.tsv"
SUITE_TIMINGS=()

print_usage() {
    cat <<'EOF'
Usage: ./tests/run-all-tests.sh [OPTIONS] [--CATEGORY ...]

Categories:
  --smoke              Tests in tests/smoke/
  --unit               Tests in tests/unit/
  --integration        Tests in tests/integration/
  --root               Legacy root-level suites
  --live               Opt-in tests that may call real providers
  --all                All categories except live (default)
  --everything         All categories, including live

Options:
  --suite=PATH         Run one suite relative to tests/; repeatable
  --fail-fast          Stop after the first failed suite
  --list               List selected suites without running them
  --shard-index=N      Zero-based deterministic shard index
  --shard-count=N      Number of deterministic shards
  --shard-weights=PATH Duration weights; missing files use alphabetical fallback
  --symlink-sensitive  Keep only path-indirection unit suites
  -h, --help           Show this help and exit
EOF
}

# Function to run a test suite
run_test_suite() {
    local test_file="$1"
    local test_name
    local suite_start suite_end suite_duration
    # Show relative path from tests/ for clarity
    test_name="${test_file#"$SCRIPT_DIR"/}"

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Running: ${test_name}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    suite_start="$(date +%s)"

    # Non-live suites must never launch real provider/auth probes. Besides
    # spending API quota, a CLI blocked on Keychain can stall the entire gate.
    local test_rc=0
    if [[ "$test_file" == "$SCRIPT_DIR/live/"* ]]; then
        bash "$test_file" || test_rc=$?
    else
        OCTOPUS_SKIP_PROVIDER_PROBES=true bash "$test_file" || test_rc=$?
    fi
    suite_end="$(date +%s)"
    suite_duration=$((suite_end - suite_start))
    SUITE_TIMINGS+=("${suite_duration}"$'\t'"${test_name}")

    if [[ "$test_rc" -eq 0 ]]; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo ""
        echo -e "${GREEN}  PASS: ${test_name}${NC}"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        echo ""
        echo -e "${RED}  FAIL: ${test_name}${NC}"
        if $FAIL_FAST; then
            echo ""
            echo -e "${YELLOW}--fail-fast: stopping after first failure${NC}"
            print_summary
            exit 1
        fi
    fi
}

# Discover test files in a directory (sorted by name for deterministic order)
discover_tests() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        local files=()
        while IFS= read -r -d '' f; do
            files+=("$f")
        done < <(find "$dir" -maxdepth 1 -name 'test-*.sh' -print0 | sort -z)
        # Also pick up validate-*.sh at root level
        if [[ "$dir" == "$SCRIPT_DIR" ]]; then
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(find "$dir" -maxdepth 1 -name 'validate-*.sh' -print0 | sort -z)
        fi
        printf '%s\n' "${files[@]}"
    fi
}

print_summary() {
    echo ""
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    Final Summary                         ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Total test suites: ${BLUE}$TOTAL_SUITES${NC}"
    echo -e "Passed:            ${GREEN}$PASSED_SUITES${NC}"
    echo -e "Failed:            ${RED}$FAILED_SUITES${NC}"
    if [[ $SKIPPED_SUITES -gt 0 ]]; then
        echo -e "Skipped:           ${YELLOW}$SKIPPED_SUITES${NC}"
    fi
    echo ""

    echo "Slowest suites:"
    printf '%s\n' "${SUITE_TIMINGS[@]}" |
        LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 |
        awk 'NR <= 10' |
        while IFS=$'\t' read -r duration suite; do
            printf '  %ss %s\n' "$duration" "$suite"
        done
    echo ""

    if [[ $FAILED_SUITES -eq 0 ]]; then
        echo -e "${GREEN}  ALL TESTS PASSED  ${NC}"
    else
        echo -e "${RED}  SOME TESTS FAILED  ${NC}"
    fi
    echo ""
}

# Parse flags
declare -a CATEGORIES=()
declare -a EXPLICIT_SUITE_ARGS=()
SYMLINK_SENSITIVE=false
for arg in "$@"; do
    case "$arg" in
        --smoke)       CATEGORIES+=("smoke") ;;
        --unit)        CATEGORIES+=("unit") ;;
        --integration) CATEGORIES+=("integration") ;;
        --root)        CATEGORIES+=("root") ;;
        --live)        CATEGORIES+=("live") ;;
        # Removed compat aliases: --e2e ran "integration" and --performance ran
        # "live", so each category was reachable under two names. --e2e made
        # `make test-all` run the integration suites twice, and --performance
        # dispatched real provider sessions without the warning `test-live`
        # prints. --regression ran "root", which is now reachable as --root.
        --all)         CATEGORIES=("smoke" "unit" "integration" "root") ;;
        --everything)  CATEGORIES=("smoke" "unit" "integration" "root" "live") ;;
        -h|--help)      print_usage; exit 0 ;;
        --fail-fast)   FAIL_FAST=true ;;
        --list)        LIST_ONLY=true ;;
        --shard-index=*) SHARD_INDEX="${arg#--shard-index=}" ;;
        --shard-count=*) SHARD_COUNT="${arg#--shard-count=}" ;;
        --shard-weights=*) SHARD_WEIGHTS_FILE="${arg#--shard-weights=}" ;;
        --symlink-sensitive) SYMLINK_SENSITIVE=true ;;
        --suite=*)
            suite_arg="${arg#--suite=}"
            if [[ -z "$suite_arg" ]]; then
                echo -e "${RED}--suite requires a path relative to tests/${NC}" >&2
                exit 2
            fi
            EXPLICIT_SUITE_ARGS+=("$suite_arg")
            ;;
        *)
            echo -e "${YELLOW}Unknown flag '$arg', ignoring${NC}" ;;
    esac
done

if ! [[ "$SHARD_COUNT" =~ ^[1-9][0-9]*$ ]] ||
   ! [[ "$SHARD_INDEX" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Shard count must be positive and shard index must be non-negative.${NC}" >&2
    exit 2
fi
SHARD_COUNT=$((10#$SHARD_COUNT))
SHARD_INDEX=$((10#$SHARD_INDEX))
if [[ "$SHARD_INDEX" -ge "$SHARD_COUNT" ]]; then
    echo -e "${RED}Shard index $SHARD_INDEX is outside shard count $SHARD_COUNT.${NC}" >&2
    exit 2
fi

# A standalone selector scans unit tests. When combined with --suite, it filters
# only those explicit suites instead of silently adding the entire unit tree.
if [[ "$SYMLINK_SENSITIVE" == true && ${#CATEGORIES[@]} -eq 0 && ${#EXPLICIT_SUITE_ARGS[@]} -eq 0 ]]; then
    CATEGORIES=("unit")
fi

# Default to --all only when no category, selector, or explicit suite was requested.
if [[ "$SYMLINK_SENSITIVE" == false && ${#CATEGORIES[@]} -eq 0 && ${#EXPLICIT_SUITE_ARGS[@]} -eq 0 ]]; then
    CATEGORIES=("smoke" "unit" "integration" "root")
fi

# Deduplicate categories while preserving order
declare -a UNIQUE_CATS=()
for cat in ${CATEGORIES[@]+"${CATEGORIES[@]}"}; do
    local_dup=false
    for seen in "${UNIQUE_CATS[@]+"${UNIQUE_CATS[@]}"}"; do
        if [[ "$seen" == "$cat" ]]; then
            local_dup=true
            break
        fi
    done
    if ! $local_dup; then
        UNIQUE_CATS+=("$cat")
    fi
done
CATEGORIES=()
for seen in ${UNIQUE_CATS[@]+"${UNIQUE_CATS[@]}"}; do
    CATEGORIES+=("$seen")
done

# Build test list from categories via auto-discovery
declare -a TEST_SUITES=()
for cat in ${CATEGORIES[@]+"${CATEGORIES[@]}"}; do
    case "$cat" in
        smoke)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR/smoke")
            ;;
        unit)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR/unit")
            ;;
        integration)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR/integration")
            ;;
        root)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR")
            ;;
        live)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR/live")
            ;;
    esac
done

# Add explicitly requested suites after category discovery. Paths are confined
# to tests/ and must name existing files; invalid input fails instead of
# silently expanding to the default matrix.
for suite_arg in ${EXPLICIT_SUITE_ARGS[@]+"${EXPLICIT_SUITE_ARGS[@]}"}; do
    case "$suite_arg" in
        /*|../*|*/../*|*/..)
            echo -e "${RED}Invalid --suite path outside tests/: $suite_arg${NC}" >&2
            exit 2
            ;;
        tests/*) suite_path="$SCRIPT_DIR/${suite_arg#tests/}" ;;
        *)       suite_path="$SCRIPT_DIR/$suite_arg" ;;
    esac
    suite_name="${suite_path##*/}"
    case "$suite_name" in
        test-*.sh|validate-*.sh) ;;
        *)
            echo -e "${RED}Explicit suite must be test-*.sh or validate-*.sh: $suite_arg${NC}" >&2
            exit 2
            ;;
    esac
    if [[ ! -f "$suite_path" ]]; then
        echo -e "${RED}Explicit suite not found: $suite_arg${NC}" >&2
        exit 2
    fi
    TEST_SUITES+=("$suite_path")
done

# Deduplicate explicit/category overlap while preserving deterministic order.
declare -a UNIQUE_SUITES=()
for suite in "${TEST_SUITES[@]}"; do
    suite_seen=false
    for seen in ${UNIQUE_SUITES[@]+"${UNIQUE_SUITES[@]}"}; do
        if [[ "$seen" == "$suite" ]]; then
            suite_seen=true
            break
        fi
    done
    if ! $suite_seen; then
        UNIQUE_SUITES+=("$suite")
    fi
done
TEST_SUITES=()
for suite in ${UNIQUE_SUITES[@]+"${UNIQUE_SUITES[@]}"}; do
    TEST_SUITES+=("$suite")
done

if [[ "$SYMLINK_SENSITIVE" == true ]]; then
    declare -a SYMLINK_SUITES=()
    SYMLINK_SUITE_FILE="${OCTOPUS_SYMLINK_SUITE_FILE:-$SCRIPT_DIR/symlink-sensitive.txt}"
    if [[ ! -r "$SYMLINK_SUITE_FILE" ]]; then
        echo -e "${RED}Symlink-sensitive suite list is missing: $SYMLINK_SUITE_FILE${NC}" >&2
        exit 1
    fi
    while IFS= read -r suite_relative || [[ -n "$suite_relative" ]]; do
        case "$suite_relative" in
            ''|'#'*) continue ;;
        esac
        if [[ "$suite_relative" != unit/test-*.sh || ! -f "$SCRIPT_DIR/$suite_relative" ]]; then
            echo -e "${RED}Stale symlink-sensitive suite entry: $suite_relative${NC}" >&2
            exit 1
        fi
    done < "$SYMLINK_SUITE_FILE"
    for suite in ${TEST_SUITES[@]+"${TEST_SUITES[@]}"}; do
        suite_relative="${suite#"$SCRIPT_DIR"/}"
        if grep -Fxq "$suite_relative" "$SYMLINK_SUITE_FILE"; then
            SYMLINK_SUITES+=("$suite")
        fi
    done
    TEST_SUITES=("${SYMLINK_SUITES[@]+"${SYMLINK_SUITES[@]}"}")
    if [[ -z "${TEST_SUITES[*]-}" ]]; then
        echo -e "${RED}Symlink-sensitive selection produced no test suites.${NC}" >&2
        exit 1
    fi
fi

if [[ "$SHARD_COUNT" -gt 1 ]]; then
    declare -a SHARDED_SUITES=()
    if [[ -r "$SHARD_WEIGHTS_FILE" ]]; then
        while IFS=$'\t' read -r assigned_shard suite_relative; do
            if [[ "$assigned_shard" == "$SHARD_INDEX" && -n "$suite_relative" ]]; then
                SHARDED_SUITES+=("$SCRIPT_DIR/$suite_relative")
            fi
        done < <(
            printf '%s\n' ${TEST_SUITES[@]+"${TEST_SUITES[@]}"} |
                awk -v prefix="$SCRIPT_DIR/" '
                    index($0, prefix) == 1 { print substr($0, length(prefix) + 1); next }
                    { print }
                ' |
                awk -v weights_file="$SHARD_WEIGHTS_FILE" '
                    BEGIN {
                        while ((getline line < weights_file) > 0) {
                            if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
                            split(line, fields, "\t")
                            if (fields[1] != "" && fields[2] ~ /^[0-9]+$/) weight[fields[1]] = fields[2]
                        }
                        close(weights_file)
                    }
                    { print (($0 in weight) ? weight[$0] : 1) "\t" $0 }
                ' |
                LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 |
                awk -F '\t' -v shard_count="$SHARD_COUNT" '
                    {
                        target = 0
                        for (i = 1; i < shard_count; i++) {
                            if (load[i] < load[target]) target = i
                        }
                        print target "\t" $2
                        load[target] += $1
                    }
                '
        )
    else
        # A source archive may omit the optional timing profile. Preserve a
        # stable complete partition using the previous alphabetical strategy.
        suite_index=0
        while IFS= read -r suite; do
            if [[ $((suite_index % SHARD_COUNT)) -eq "$SHARD_INDEX" ]]; then
                SHARDED_SUITES+=("$suite")
            fi
            suite_index=$((suite_index + 1))
        done < <(printf '%s\n' ${TEST_SUITES[@]+"${TEST_SUITES[@]}"} | LC_ALL=C sort)
    fi
    TEST_SUITES=("${SHARDED_SUITES[@]+"${SHARDED_SUITES[@]}"}")
    if [[ -z "${TEST_SUITES[*]-}" ]]; then
        echo -e "${RED}Shard $SHARD_INDEX of $SHARD_COUNT produced no test suites.${NC}" >&2
        exit 1
    fi
fi

if [[ -z "${TEST_SUITES[*]-}" ]]; then
    echo -e "${YELLOW}No test files discovered for categories: ${CATEGORIES[*]-}${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Claude Octopus Test Suite                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
if [[ -n "${CATEGORIES[*]-}" ]]; then
    echo -e "${BLUE}Categories:${NC} ${CATEGORIES[*]}"
else
    echo -e "${BLUE}Categories:${NC} explicit suites"
fi
echo -e "${BLUE}Discovered:${NC} ${#TEST_SUITES[@]} test suites"
if [[ "$SHARD_COUNT" -gt 1 ]]; then
    echo -e "${BLUE}Shard:${NC} $((SHARD_INDEX + 1))/${SHARD_COUNT}"
fi
if $FAIL_FAST; then
    echo -e "${BLUE}Fail-fast:${NC} enabled"
fi
echo ""
echo -e "${BLUE}Suites:${NC}"
for suite in "${TEST_SUITES[@]}"; do
    echo "  - ${suite#"$SCRIPT_DIR"/}"
done

if $LIST_ONLY; then
    echo ""
    echo -e "${BLUE}(--list mode: not executing)${NC}"
    exit 0
fi

# Make discovered test scripts executable
for suite in "${TEST_SUITES[@]}"; do
    chmod +x "$suite"
done

for suite in "${TEST_SUITES[@]}"; do
    run_test_suite "$suite"
done

print_summary

if [[ $FAILED_SUITES -gt 0 ]]; then
    exit 1
fi
