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
    printf '%s\n' "$2" | awk '/^### Scenario [0-9]+:/ { print; print "**Verdict:** PASS" }'
    echo 'Score: 1.00'
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

for pipeline_case in single unstructured blank-visible blank-holdout wrapped-holdout visible-write-failure holdout-write-failure result-write-failure providers-empty providers-banner providers-malformed providers-score-range providers-negative providers-integer initial-failure retry-failure implementation-failure retry-implementation-failure success; do
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
        embrace_full_workflow() {
            touch embraced
            echo called >> implementation-calls
            if [[ "$pipeline_case" == implementation-failure ]]; then return 42; fi
            if [[ "$pipeline_case" == retry-implementation-failure && $(wc -l < implementation-calls) -eq 2 ]]; then return 43; fi
        }
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
            elif [[ "$pipeline_case" == implementation-failure ]]; then
                [[ "$rc" == 42 && -e embraced && ! -e provider-called && ! -e scored && -z ${OCTOPUS_FACTORY_MODE+x} && -z ${OCTOPUS_SKIP_PHASE_COST_PROMPT+x} ]]
            elif [[ "$pipeline_case" == retry-implementation-failure ]]; then
                [[ "$rc" == 43 && -e scored && -e provider-called && $(wc -l < implementation-calls) -eq 2 && -z ${OCTOPUS_FACTORY_MODE+x} && -z ${OCTOPUS_SKIP_PHASE_COST_PROMPT+x} ]]
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

for evaluation in verdicts rounded-score partial-verdict integer-zero integer-one markdown-score prompt-score; do
    test_case "holdout preserves valid $evaluation evaluation"
    if (
        case_dir="$TEST_TMP_DIR/score-$evaluation"
        mkdir -p "$case_dir"
        printf '### Scenario 1: independent check\nGiven valid input\n' > "$case_dir/scenarios-holdout.md"
        run_agent_sync() {
            case "$evaluation" in
                verdicts) printf '### Scenario 1: first\n**Verdict:** PASS\n### Scenario 2: second\n**Verdict:** FAIL\n' ;;
                partial-verdict) printf '%s\n' '- **Verdict:** **PARTIAL**' ;;
                rounded-score) printf '### Scenario 1: first\n**Verdict:** PASS\n### Scenario 2: second\n**Verdict:** FAIL\nScore: 0.504\n' ;;
                integer-zero) printf '**Verdict:** FAIL\nScore: 0\n' ;;
                integer-one) printf '**Verdict:** PASS\nScore: 1\n' ;;
                markdown-score) printf '**Score:** 0.75\n' ;;
                prompt-score) printf '%s\n' '- Score: 0.75 (PASS=1.0, PARTIAL=0.5, FAIL=0.0, averaged)' ;;
            esac
        }
        case "$evaluation" in verdicts|partial-verdict) expected=0.50 ;; rounded-score) expected=0.504 ;; integer-zero) expected=0 ;; integer-one) expected=1 ;; markdown-score|prompt-score) expected=0.75 ;; esac
        [[ "$evaluation" != verdicts && "$evaluation" != rounded-score ]] || printf '### Scenario 2: second\nGiven second input\n' >> "$case_dir/scenarios-holdout.md"
        result=$(run_holdout_tests "$case_dir") && [[ "$result" == "$expected" ]]
    ); then test_pass; else test_fail "valid $evaluation was rejected or used the wrong score"; fi
done

for consumer_case in integer-zero markdown-zero verdict-zero negated-verdict ambiguous-verdict mixed-negated mixed-ambiguous contradictory-score scored-incomplete-verdict incomplete-verdict duplicate-verdict wrong-verdict complete-verdict duplicate-score malformed-first-score signed-zero retry-score score-write-failure; do
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
                    contradictory-score) printf '**Verdict:** FAIL\nScore: 1.00\n' ;;
                    scored-incomplete-verdict) printf '### Scenario 3: check\n**Verdict:** PASS\nScore: 1.00\n' ;;
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
        if [[ "$consumer_case" == negated-verdict || "$consumer_case" == ambiguous-verdict || "$consumer_case" == mixed-negated || "$consumer_case" == mixed-ambiguous || "$consumer_case" == contradictory-score || "$consumer_case" == scored-incomplete-verdict || "$consumer_case" == incomplete-verdict || "$consumer_case" == duplicate-verdict || "$consumer_case" == wrong-verdict || "$consumer_case" == duplicate-score || "$consumer_case" == malformed-first-score ]]; then
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


for production_case in dual-provider long-holdout oversize failed-primary failed-supplement failed-both failed-all whitespace-all scoring-failed scoring-empty scoring-whitespace scoring-malformed scoring-range scoring-negative scoring-duplicate scoring-bare-behavior scoring-bare-constraint scoring-bare-quality scoring-retry-malformed scoring-asterisk scoring-markdown scoring-fallback; do
    test_case "production generator and evaluator preserve $production_case evidence"
    if (
        source "$PROJECT_ROOT/scripts/lib/factory-spec.sh"
        case_dir="$TEST_TMP_DIR/production-$production_case"
        mkdir -p "$case_dir"
        cd "$case_dir"
        printf '# Fixture spec\n' > spec.md
        _BOX_TOP='' _BOX_MID='' _BOX_BOT='' MAGENTA='' CYAN=''
        OCTOPUS_FACTORY_HOLDOUT_RATIO=0.20 OCTOPUS_FACTORY_MAX_RETRIES=0
        assess_spec_maturity() { echo 'Mature|6|{}'; }
        parse_factory_spec() { echo 0.95; }
        score_nlspec_quality() { echo '100|PASS'; }
        embrace_full_workflow() {
            echo called >> implementation-calls
            if [[ "$production_case" == scoring-retry-malformed && -e implemented ]]; then
                [[ -z $(find .octo/factory -name satisfaction-scores.json -type f) ]] || touch stale-score
            fi
            touch implemented
        }
        generate_factory_report() { touch reported; }
        if [[ "$production_case" == oversize ]]; then
            source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
            get_provider_context_limit() { echo 100; }
            get_role_budget_proportion() { echo 100; }
            record_oversize_event() { :; }
            write_agent_status() { :; }
            octo_context_budget_warning() { :; }
            OCTOPUS_OVERSIZE_STRATEGY=truncate
        fi
        _satisfaction_reply() {
            echo "$1" >> scorers-tried
            case "$production_case" in
                scoring-failed) printf 'behavior_coverage: 1.00\nconstraint_adherence: 1.00\nquality: 1.00\n'; return 42 ;;
                scoring-empty) return 0 ;;
                scoring-whitespace) printf ' \n\t\n'; return 0 ;;
                scoring-malformed) echo 'No evaluation available'; return 0 ;;
                scoring-range) printf 'behavior_coverage: 9.00\nconstraint_adherence: 1.00\nquality: 1.00\n'; return 0 ;;
                scoring-negative) printf 'behavior_coverage: -0.25\nconstraint_adherence: 1.00\nquality: 1.00\n'; return 0 ;;
                scoring-duplicate) printf 'behavior_coverage: 0.00\nbehavior_coverage: 1.00\nconstraint_adherence: 1.00\nquality: 1.00\n'; return 0 ;;
                scoring-asterisk) printf 'behavior_coverage: 0*1\nconstraint_adherence: 0*1\nquality: 0*1\n'; return 0 ;;
                scoring-markdown) printf '**behavior_coverage**: **0.75**\n**constraint_adherence: 0.75**\n*quality*: *0.75*\n'; return 0 ;;
                scoring-bare-behavior) echo 'behavior_coverage' ;;
                scoring-bare-constraint) echo 'constraint_adherence' ;;
                scoring-bare-quality) echo 'quality' ;;
                scoring-retry-malformed)
                    if [[ $(wc -l < implementation-calls) -eq 1 ]]; then
                        printf 'behavior_coverage: 0.00\nconstraint_adherence: 0.00\nquality: 0.00\n'
                    else
                        echo 'No valid dimensions for this retry'
                    fi
                    return 0
                    ;;
                scoring-fallback)
                    if [[ "$1" == claude-sonnet ]]; then
                        printf 'behavior_coverage: 0.00\nconstraint_adherence: 0.00\nquality: 0.00\n'
                        return 42
                    fi
                    ;;
            esac
            printf 'behavior_coverage: 1.00\nconstraint_adherence: 1.00\nquality: 1.00\n'
        }
        run_agent_sync() {
            case "$4" in
                qa-engineer)
                    echo "$1" >> generators-tried
                    if [[ "$production_case" == whitespace-all && "$1" != claude ]]; then printf '   \n'; return 0; fi
                    if [[ "$production_case" == long-holdout && "$1" != codex ]]; then return 0; fi
                    python3 - "$production_case" "$1" <<'PYGENERATE'
import sys
for n in range(1, 11):
    body = "Given valid input " + ("x" * 4500 if sys.argv[1] == "long-holdout" else "and expected output")
    print(f"### Scenario {n}: {sys.argv[2]} check\n{body}\nEND-CASE-{sys.argv[2]}-{n}\n")
PYGENERATE
                    case "$production_case:$1" in
                        failed-all:*|failed-both:codex|failed-both:agy|failed-primary:codex|failed-supplement:agy) return 42 ;;
                    esac
                    ;;
                qa-reviewer)
                    if [[ "$production_case" == oversize ]]; then
                        enforce_context_budget "$2" "$4" "$1" factory fixture-seat >/dev/null || return $?
                        touch transport-accepted
                        echo 'Score: 1.00'
                        return 0
                    fi
                    printf '%s\n' "$2" > evaluator-prompt
                    if [[ "$production_case" == scoring-retry-malformed && $(wc -l < implementation-calls) -eq 2 ]]; then
                        printf '%s\n' "$2" | awk '/^### Scenario [0-9]+:/ { print; print "**Verdict:** FAIL" }'
                    else
                        printf '%s\n' "$2" | awk '/^### Scenario [0-9]+:/ { print; print "**Verdict:** PASS" }'
                    fi
                    ;;
                evaluator) _satisfaction_reply "$1" ;;
                *) return 42 ;;
            esac
        }
        rc=0
        target=0.20 retries=0
        [[ "$production_case" != scoring-retry-malformed ]] || { target=0.90; retries=1; }
        factory_run spec.md "$target" "$retries" true > output 2>&1 || rc=$?
        if [[ "$production_case" == failed-all ]]; then
            [[ "$rc" != 0 && ! -e implemented && ! -e reported && ! -e evaluator-prompt ]] || exit 1
            [[ "$(cat generators-tried)" == $'codex\nagy\nclaude' ]] || exit 1
            exit 0
        fi
        if [[ "$production_case" == oversize ]]; then
            [[ "$rc" != 0 && -e implemented && ! -e reported && ! -e transport-accepted && "$OCTOPUS_OVERSIZE_STRATEGY" == truncate ]] || exit 1
            exit 0
        fi
        if [[ "$production_case" == scoring-* && "$production_case" != scoring-fallback && "$production_case" != scoring-markdown ]]; then
            [[ "$rc" != 0 && -e implemented && -e evaluator-prompt && ! -e reported ]] || exit 1
            [[ -z $(find .octo/factory -name satisfaction-scores.json -type f) ]] || exit 1
            case "$production_case" in
                scoring-failed|scoring-empty|scoring-whitespace) [[ "$(cat scorers-tried)" == $'claude-sonnet\nclaude' ]] ;;
                scoring-retry-malformed)
                    [[ "$(cat scorers-tried)" == $'claude-sonnet\nclaude-sonnet' && ! -e stale-score && $(wc -l < implementation-calls) -eq 2 ]]
                    ;;
                *) [[ "$(cat scorers-tried)" == claude-sonnet ]] ;;
            esac || exit 1
            exit 0
        fi
        if [[ "$production_case" == scoring-fallback ]]; then
            [[ "$(cat scorers-tried)" == $'claude-sonnet\nclaude' ]] || exit 1
        fi
        [[ "$rc" == 0 && -e implemented && -e reported ]] || exit 1
        scores=$(find .octo/factory -name satisfaction-scores.json -type f)
        python3 - "$scores" "$production_case" <<'PYPRODUCTION'
import json, pathlib, re, sys
scores_path = pathlib.Path(sys.argv[1])
score = json.loads(scores_path.read_text())
assert score["holdout_pass_rate"] == 1 and score["verdict"] == ("FAIL" if sys.argv[2] == "scoring-markdown" else "PASS"), score
if sys.argv[2] == "scoring-markdown":
    assert all(score[key] == 0.75 for key in ("behavior_coverage", "constraint_adherence", "quality")), score
    assert score["composite"] == 0.81, score
run = scores_path.parent
ids = lambda s: re.findall(r"^### Scenario (\d+):", s, re.M)
all_ids = ids((run / "scenarios-all.md").read_text())
count = 20 if sys.argv[2] in ("dual-provider", "scoring-fallback", "scoring-markdown") else 10
assert all_ids == list(map(str, range(1, count + 1))), all_ids
if sys.argv[2] in ("failed-primary", "failed-supplement", "failed-both", "whitespace-all"):
    scenarios = (run / "scenarios-all.md").read_text()
    accepted = {"failed-primary": "agy", "failed-supplement": "codex", "failed-both": "claude", "whitespace-all": "claude"}[sys.argv[2]]
    assert set(re.findall(r"END-CASE-([a-z]+)-", scenarios)) == {accepted}, scenarios
    expected_calls = "codex\nagy\n" + ("claude\n" if accepted == "claude" else "")
    assert pathlib.Path("generators-tried").read_text() == expected_calls
holdout = (run / "scenarios-holdout.md").read_text()
prompt = pathlib.Path("evaluator-prompt").read_text()
assert ids(holdout) == ids(prompt), (ids(holdout), ids(prompt))
assert holdout.strip() in prompt
if sys.argv[2] == "long-holdout":
    assert "END-CASE-codex-8" in prompt
PYPRODUCTION
    ); then test_pass; else test_fail "$production_case lost scenario identity or evaluator input"; fi
done

test_case "scenario generator fails without output when evidence cannot be saved"
if (
    source "$PROJECT_ROOT/scripts/lib/factory-spec.sh"
    case_dir="$TEST_TMP_DIR/generator-write-failure"
    mkdir -p "$case_dir/scenarios-all.md"
    printf '# Fixture spec\n' > "$case_dir/spec.md"
    run_agent_sync() { printf '### Scenario 1: first\nGiven first input\n### Scenario 2: second\nGiven second input\n'; }
    rc=0
    result=$(generate_factory_scenarios "$case_dir/spec.md" "$case_dir" 2> "$case_dir/errors") || rc=$?
    [[ "$rc" == 1 && -z "$result" ]]
); then test_pass; else test_fail 'generator reported unsaved scenario evidence'; fi


for absent_score in missing empty; do
    test_case "satisfaction scorer returns for $absent_score validated score"
    if (
        source "$PROJECT_ROOT/scripts/lib/factory-spec.sh"
        case_dir="$TEST_TMP_DIR/scorer-$absent_score"
        mkdir -p "$case_dir"
        run_agent_sync() { touch "$case_dir/provider-called"; }
        rc=0
        if [[ "$absent_score" == missing ]]; then
            score_satisfaction "$case_dir" 0.90 > "$case_dir/output" 2>&1 || rc=$?
        else
            score_satisfaction "$case_dir" 0.90 '' > "$case_dir/output" 2>&1 || rc=$?
        fi
        [[ "$rc" == 1 && ! -e "$case_dir/provider-called" && ! -e "$case_dir/satisfaction-scores.json" ]]
    ); then test_pass; else test_fail "scorer terminated its caller for $absent_score input"; fi
done

test_summary
