#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/factory.sh"
test_suite "Factory holdout evidence"

log() { printf '%s\n' "$*" >&2; }
run_agent_sync() {
    touch "$case_dir/provider-called"
    printf '### Scenario 1: independent check\n**Verdict:** PASS\nScore: 1.00\n'
}

for input in missing empty unstructured header single; do
    test_case "holdout rejects $input evidence before calling a provider"
    case_dir="$TEST_TMP_DIR/$input"
    mkdir -p "$case_dir"
    case "$input" in
        empty) : > "$case_dir/scenarios-holdout.md" ;;
        unstructured) echo '# No structured scenarios to holdout' > "$case_dir/scenarios-holdout.md" ;;
        header) echo '# Factory Holdout Scenarios (0 of 1)' > "$case_dir/scenarios-holdout.md" ;;
        single)
            printf '### Scenario 1: the only case\nGiven valid input\n' > "$case_dir/scenarios-all.md"
            split_status=0
            split_holdout_scenarios "$case_dir/scenarios-all.md" "$case_dir" 0.20 || split_status=$?
            ;;
    esac
    rc=0
    result=$(run_holdout_tests "$case_dir" 2> "$case_dir/errors") || rc=$?
    if [[ "$rc" != 0 && -z "$result" && ! -e "$case_dir/provider-called" &&
          ! -e "$case_dir/holdout-results.md" ]] && [[ -s "$case_dir/errors" ]]; then
        test_pass
    else
        test_fail "missing evidence became a score or reached a provider: status=$rc score=$result"
    fi
done

test_case "single-scenario split keeps its only scenario visible"
if [[ "$split_status" == 1 ]] &&
   grep -q '^### Scenario 1:' "$TEST_TMP_DIR/single/scenarios-visible.md" &&
   ! grep -q '^### Scenario' "$TEST_TMP_DIR/single/scenarios-holdout.md"; then
    test_pass
else
    test_fail 'single scenario was withheld from implementation'
fi

test_case "multi-scenario holdout still receives independent evaluation"
case_dir="$TEST_TMP_DIR/valid"
mkdir -p "$case_dir"
printf '### Scenario 1: first\nGiven first input\n### Scenario 2: second\nGiven second input\n' > "$case_dir/scenarios-all.md"
split_holdout_scenarios "$case_dir/scenarios-all.md" "$case_dir" 0.20
if result=$(run_holdout_tests "$case_dir") && [[ "$result" == 1.00 ]] &&
   [[ -s "$case_dir/holdout-results.md" && -e "$case_dir/provider-called" ]]; then
    test_pass
else
    test_fail 'valid holdout evaluation changed'
fi

for pipeline_case in single unstructured visible-write-failure holdout-write-failure result-write-failure initial-failure retry-failure success; do
    test_case "factory handles $pipeline_case through an OR-list"
    if (
        case_dir="$TEST_TMP_DIR/pipeline-$pipeline_case"
        mkdir -p "$case_dir"
        cd "$case_dir"
        printf '# Fixture spec\n' > spec.md
        _BOX_TOP='' _BOX_MID='' _BOX_BOT='' MAGENTA='' CYAN=''
        OCTOPUS_FACTORY_HOLDOUT_RATIO=0.20
        OCTOPUS_FACTORY_MAX_RETRIES=1
        assess_spec_maturity() { echo 'Mature|6|{}'; }
        parse_factory_spec() { echo 0.90; }
        score_nlspec_quality() { echo '100|PASS'; }
        generate_factory_scenarios() {
            if [[ "$pipeline_case" == unstructured ]]; then
                echo '# No structured test cases'
            else
                printf '### Scenario 1: first\nGiven first input\n'
                [[ "$pipeline_case" == single ]] || printf '### Scenario 2: second\nGiven second input\n'
            fi | tee "$2/scenarios-all.md"
            case "$pipeline_case" in
                visible-write-failure) mkdir "$2/scenarios-visible.md" ;;
                holdout-write-failure) mkdir "$2/scenarios-holdout.md" ;;
                result-write-failure) mkdir "$2/holdout-results.md" ;;
            esac
        }
        embrace_full_workflow() { touch embraced; }
        score_satisfaction() {
            touch scored
            if [[ "$pipeline_case" == success ]]; then echo '1.00|PASS'; else echo '0.00|FAIL'; fi
        }
        generate_factory_report() { touch reported; }
        if [[ "$pipeline_case" == initial-failure || "$pipeline_case" == retry-failure ]]; then
            run_holdout_tests() {
                if [[ "$pipeline_case" == retry-failure && ! -e first-holdout ]]; then
                    touch first-holdout
                    echo 0.00
                    return 0
                fi
                return 42
            }
        fi
        rc=0
        factory_run spec.md 0.20 1 true > output 2>&1 || rc=$?
        if [[ "$pipeline_case" == success ]]; then
            [[ "$rc" == 0 && -e reported && -e scored && -e provider-called ]] &&
                grep -q 'FACTORY COMPLETE' output
        else
            [[ "$rc" != 0 && ! -e reported ]] && ! grep -q 'FACTORY COMPLETE' output &&
            if [[ "$pipeline_case" == single || "$pipeline_case" == unstructured || "$pipeline_case" == visible-write-failure || "$pipeline_case" == holdout-write-failure ]]; then
                [[ ! -e embraced && ! -e scored ]]
            elif [[ "$pipeline_case" == result-write-failure ]]; then
                [[ "$rc" == 1 && -e embraced && ! -e scored ]]
            else
                [[ "$rc" == 42 && -e embraced ]] &&
                    if [[ "$pipeline_case" == retry-failure ]]; then
                        [[ -e scored && -e first-holdout ]]
                    else
                        [[ ! -e scored ]]
                    fi
            fi
        fi
    ); then test_pass; else test_fail "factory continued past $pipeline_case"; fi
done

test_summary
