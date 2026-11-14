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

for input in missing empty unstructured header headings single; do
    test_case "holdout rejects $input evidence before calling a provider"
    case_dir="$TEST_TMP_DIR/$input"
    mkdir -p "$case_dir"
    case "$input" in
        empty) : > "$case_dir/scenarios-holdout.md" ;;
        unstructured) echo '# No structured scenarios to holdout' > "$case_dir/scenarios-holdout.md" ;;
        header) echo '# Factory Holdout Scenarios (0 of 1)' > "$case_dir/scenarios-holdout.md" ;;
        headings) printf '### Scenario 1: empty\n\n### Scenario 2: also empty\n' > "$case_dir/scenarios-holdout.md" ;;
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

for pipeline_case in single unstructured blank-visible blank-holdout wrapped-holdout visible-write-failure holdout-write-failure result-write-failure providers-empty providers-banner providers-malformed providers-score-range providers-negative providers-integer initial-failure retry-failure success; do
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
                printf '### Scenario 1: first\n'
                [[ "$pipeline_case" == blank-visible ]] || printf 'Given first input\n'
                if [[ "$pipeline_case" != single ]]; then
                    printf '### Scenario 2: second\n'
                    [[ "$pipeline_case" == blank-holdout || "$pipeline_case" == wrapped-holdout ]] || printf 'Given second input\n'
                fi
                [[ "$pipeline_case" != wrapped-holdout ]] || printf '</external-cli-output>\n'
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
        if [[ "$pipeline_case" == providers-* ]]; then
            run_agent_sync() {
                echo "$1" >> providers-tried
                case "$pipeline_case" in
                    providers-banner) echo '[Provider unavailable: fixture] Score: 1.00' ;;
                    providers-malformed) echo 'The provider returned no evaluation'; return 0 ;;
                    providers-score-range) echo 'Score: 1.25'; return 0 ;;
                    providers-negative) printf '**Verdict:** PASS\nScore: -0.25\n'; return 0 ;;
                    providers-integer) printf '**Verdict:** PASS\nScore: 2\n'; return 0 ;;
                esac
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
            if [[ "$pipeline_case" == single || "$pipeline_case" == unstructured || "$pipeline_case" == blank-visible || "$pipeline_case" == blank-holdout || "$pipeline_case" == wrapped-holdout || "$pipeline_case" == visible-write-failure || "$pipeline_case" == holdout-write-failure ]]; then
                [[ ! -e embraced && ! -e scored ]]
            elif [[ "$pipeline_case" == providers-* ]]; then
                [[ "$rc" != 0 && -e embraced && ! -e scored ]] &&
                    if [[ "$pipeline_case" == providers-malformed || "$pipeline_case" == providers-score-range || "$pipeline_case" == providers-negative || "$pipeline_case" == providers-integer ]]; then
                        [[ "$(cat providers-tried)" == agy ]]
                    else
                        [[ "$(cat providers-tried)" == $'agy\ncodex\nclaude' ]]
                    fi
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

for fallback in codex claude empty-success whitespace-success; do
    test_case "holdout reaches $fallback fallback without accepting failed output"
    if (
        case_dir="$TEST_TMP_DIR/fallback-$fallback"
        mkdir -p "$case_dir"
        printf '### Scenario 1: independent check\nGiven valid input\n' > "$case_dir/scenarios-holdout.md"
        run_agent_sync() {
            echo "$1" >> "$case_dir/providers-tried"
            if [[ "$1" == "$fallback" || "$fallback:$1" == empty-success:codex || "$fallback:$1" == whitespace-success:codex ]]; then
                echo 'Score: 0.75'
                return 0
            fi
            [[ "$fallback" != empty-success ]] || return 0
            if [[ "$fallback" == whitespace-success ]]; then printf ' \n\t\n'; return 0; fi
            echo '[Provider unavailable: fixture] Score: 1.00'
            return 42
        }
        result=$(run_holdout_tests "$case_dir") && [[ "$result" == 0.75 ]] &&
            ! grep -c 'unavailable' "$case_dir/holdout-results.md" >/dev/null &&
            if [[ "$fallback" == claude ]]; then
                [[ "$(cat "$case_dir/providers-tried")" == $'agy\ncodex\nclaude' ]]
            else
                [[ "$(cat "$case_dir/providers-tried")" == $'agy\ncodex' ]]
            fi
    ); then test_pass; else test_fail "invalid provider output prevented $fallback fallback"; fi
done

for evaluation in verdicts partial-verdict integer-zero integer-one markdown-score prompt-score; do
    test_case "holdout preserves valid $evaluation evaluation"
    if (
        case_dir="$TEST_TMP_DIR/score-$evaluation"
        mkdir -p "$case_dir"
        printf '### Scenario 1: independent check\nGiven valid input\n' > "$case_dir/scenarios-holdout.md"
        run_agent_sync() {
            case "$evaluation" in
                verdicts) printf '### Scenario 1: first\n**Verdict:** PASS\n### Scenario 2: second\n**Verdict:** FAIL\n' ;;
                partial-verdict) printf '%s\n' '- **Verdict:** **PARTIAL**' ;;
                integer-zero) printf '**Verdict:** PASS\nScore: 0\n' ;;
                integer-one) printf '**Verdict:** FAIL\nScore: 1\n' ;;
                markdown-score) printf '**Score:** 0.75\n' ;;
                prompt-score) printf '%s\n' '- Score: 0.75 (PASS=1.0, PARTIAL=0.5, FAIL=0.0, averaged)' ;;
            esac
        }
        case "$evaluation" in verdicts|partial-verdict) expected=0.50 ;; integer-zero) expected=0 ;; integer-one) expected=1 ;; markdown-score|prompt-score) expected=0.75 ;; esac
        [[ "$evaluation" != verdicts ]] || printf '### Scenario 2: second\nGiven second input\n' >> "$case_dir/scenarios-holdout.md"
        result=$(run_holdout_tests "$case_dir") && [[ "$result" == "$expected" ]]
    ); then test_pass; else test_fail "valid $evaluation was rejected or used the wrong score"; fi
done

for consumer_case in integer-zero markdown-zero verdict-zero negated-verdict ambiguous-verdict mixed-negated mixed-ambiguous incomplete-verdict duplicate-verdict wrong-verdict complete-verdict duplicate-score malformed-first-score signed-zero retry-score score-write-failure; do
    test_case "factory passes validated $consumer_case to the real satisfaction consumer"
    if (
        source "$PROJECT_ROOT/scripts/lib/factory-spec.sh"
        case_dir="$TEST_TMP_DIR/consumer-$consumer_case"
        mkdir -p "$case_dir"
        cd "$case_dir"
        printf '# Fixture spec\n' > spec.md
        _BOX_TOP='' _BOX_MID='' _BOX_BOT='' MAGENTA='' CYAN=''
        OCTOPUS_FACTORY_HOLDOUT_RATIO=0.20 OCTOPUS_FACTORY_MAX_RETRIES=1
        assess_spec_maturity() { echo 'Mature|6|{}'; }
        parse_factory_spec() { echo 0.85; }
        score_nlspec_quality() { echo '100|PASS'; }
        generate_factory_scenarios() {
            if [[ "$consumer_case" == *-verdict && "$consumer_case" != negated-verdict && "$consumer_case" != ambiguous-verdict ]]; then
                for scenario in {1..10}; do printf '### Scenario %s: check\nGiven input %s\n' "$scenario" "$scenario"; done
            else
                printf '### Scenario 1: first\nGiven first input\n### Scenario 2: second\nGiven second input\n'
            fi | tee "$2/scenarios-all.md"
            [[ "$consumer_case" != score-write-failure ]] || mkdir "$2/satisfaction-scores.json"
        }
        embrace_full_workflow() { :; }
        generate_factory_report() { touch reported; }
        run_agent_sync() {
            if [[ "$1" == claude-sonnet ]]; then
                echo scoring >> scoring-calls
                printf 'behavior_coverage: 1.00\nconstraint_adherence: 1.00\nquality: 1.00\n'
            elif [[ "$consumer_case" == retry-score && -e first-evaluation ]]; then
                echo 'Score: 1'
            else
                touch first-evaluation
                case "$consumer_case" in
                    markdown-zero) echo '**Score:** 0.00' ;;
                    verdict-zero) echo '**Verdict:** FAIL' ;;
                    negated-verdict) echo '**Verdict:** NOT PASS' ;;
                    ambiguous-verdict) echo '**Verdict:** PASS | PARTIAL | FAIL' ;;
                    mixed-negated) printf '**Verdict:** NOT PASS\nScore: 1.00\n' ;;
                    mixed-ambiguous) printf '**Verdict:** PASS | PARTIAL | FAIL\nScore: 1.00\n' ;;
                    incomplete-verdict) printf '### Scenario 3: check\n**Verdict:** PASS\n' ;;
                    complete-verdict) printf '### Scenario 3: check\n**Verdict:** PASS\n### Scenario 8: check\n**Verdict:** PASS\n' ;;
                    duplicate-verdict) printf '### Scenario 3: check\n**Verdict:** PASS\n### Scenario 3: check\n**Verdict:** PASS\n' ;;
                    wrong-verdict) printf '### Scenario 3: check\n**Verdict:** PASS\n### Scenario 9: check\n**Verdict:** PASS\n' ;;
                    duplicate-score) printf 'Score: 0.00\nScore: 1.00\n' ;;
                    malformed-first-score) printf 'Score: invalid\nScore: 1.00\n' ;;
                    signed-zero) echo 'Score: +0.00' ;;
                    *) echo 'Score: 0' ;;
                esac
            fi
        }
        retries=0
        [[ "$consumer_case" != retry-score ]] || retries=1
        rc=0
        factory_run spec.md 0.20 "$retries" true > output 2>&1 || rc=$?
        scores=$(find .octo/factory -name satisfaction-scores.json -type f)
        if [[ "$consumer_case" == negated-verdict || "$consumer_case" == ambiguous-verdict || "$consumer_case" == mixed-negated || "$consumer_case" == mixed-ambiguous || "$consumer_case" == incomplete-verdict || "$consumer_case" == duplicate-verdict || "$consumer_case" == wrong-verdict || "$consumer_case" == duplicate-score || "$consumer_case" == malformed-first-score ]]; then
            [[ "$rc" != 0 && ! -e reported && ! -e scoring-calls && -z "$scores" ]]
        elif [[ "$consumer_case" == score-write-failure ]]; then
            [[ "$rc" != 0 && ! -e reported ]]
        else
            [[ -n "$scores" && -e reported ]] &&
            python3 - "$scores" "$consumer_case" "$rc" <<'PYCONSUMER'
import json, sys
score = json.load(open(sys.argv[1]))
retry = sys.argv[2] == "retry-score"
perfect = retry or sys.argv[2] == "complete-verdict"
assert score["holdout_pass_rate"] == (1 if perfect else 0), score
assert score["verdict"] == ("PASS" if perfect else "FAIL"), score
assert int(sys.argv[3]) == 0, sys.argv[3]
assert len(open("scoring-calls").readlines()) == (2 if retry else 1)
PYCONSUMER
        fi
    ); then test_pass; else test_fail "validated score was lost in $consumer_case"; fi
done

test_summary
