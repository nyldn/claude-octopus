#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Documented orchestrate.sh examples pass only options orchestrate.sh parses"

KW_DOC="$PROJECT_ROOT/docs/KNOWLEDGE-WORKERS.md"
AUDIT_SKILL="$PROJECT_ROOT/.claude/skills/skill-security-audit/SKILL.md"
PARALLEL_SKILL="$PROJECT_ROOT/.claude/skills/skill-parallel-agents/SKILL.md"

example_home="$TEST_TMP_DIR/documented-examples-home"
example_project="$TEST_TMP_DIR/documented-examples-project"
mkdir -p "$example_home" "$example_project"

extract_examples() {
    python3 - "$@" <<'PY'
import re
import shlex
import sys

commands = sys.argv[1]
call = re.compile(r"orchestrate\.sh\"?\s+((?:" + commands + r")\b.*)")
for path in sys.argv[2:]:
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    number = 0
    while number < len(lines):
        start = number
        line = lines[number]
        while line.rstrip().endswith("\\") and number + 1 < len(lines):
            number += 1
            line = line.rstrip()[:-1] + " " + lines[number]
        number += 1
        for span in re.split(r"`", line):
            match = call.search(span)
            if not match:
                continue
            try:
                args = shlex.split(match.group(1))
            except ValueError:
                args = ["!unparsable", match.group(1)]
            print("\x1f".join([f"{path}:{start + 1}"] + args))
PY
}

dry_run_marker() {
    case "$1" in
        advise) printf '%s' "[DRY-RUN] Would advise: " ;;
        synthesize) printf '%s' "[DRY-RUN] Would synthesize: " ;;
        empathize) printf '%s' "[DRY-RUN] Would empathize: " ;;
        grapple) printf '%s' "[DRY-RUN] Would grapple on: " ;;
        squeeze) printf '%s' "[DRY-RUN] Would squeeze test: " ;;
    esac
}

run_documented_dry_run() {
    (
        unset OCTOPUS_RESEARCH_INTENSITY
        cd "$example_project"
        env "HOME=$example_home" "OCTOPUS_NON_INTERACTIVE=1" "OCTOPUS_HOST=standalone" \
            "OCTOPUS_SKIP_PROVIDER_PROBES=true" \
            bash "$ORCHESTRATE" --dry-run "$@" 2>&1
    )
}

logged_prompt_is() {
    local output="$1" expected="$2" line
    while IFS= read -r line; do
        [[ "$line" == *"$expected" ]] && return 0
    done <<< "$output"
    return 1
}

check_dry_run_examples() {
    local label="$1" required="$2" doc="$3"
    local -a seen=() parts=()
    local record location subcommand prompt marker output rc
    while IFS= read -r record; do
        IFS=$'\x1f' read -r -a parts <<< "$record"
        location="${parts[0]#"$PROJECT_ROOT"/}"
        subcommand="${parts[1]}"
        prompt="${parts[${#parts[@]}-1]}"
        if [[ "$subcommand" == "!unparsable" ]]; then
            test_case "$location: documented example parses as shell words"
            test_fail "unbalanced quoting: ${parts[2]}"
            continue
        fi
        marker="$(dry_run_marker "$subcommand")"
        seen+=("$subcommand")

        test_case "$location: documented '$subcommand' example runs with its whole prompt"
        rc=0
        output="$(run_documented_dry_run "${parts[@]:1}")" || rc=$?
        if [[ "$rc" -ne 0 ]]; then
            test_fail "exit $rc: $(tail -3 <<< "$output")"
        elif [[ "${#parts[@]}" -ne 3 ]]; then
            test_fail "expected <subcommand> <prompt>, got ${#parts[@]} fields: ${parts[*]:1}"
        elif ! logged_prompt_is "$output" "$marker$prompt"; then
            test_fail "dry run did not log exactly '$marker$prompt': $(grep -a 'DRY-RUN' <<< "$output" | head -3)"
        elif [[ "$subcommand" == grapple ]] && ! logged_prompt_is "$output" "[DRY-RUN] Principles: general"; then
            test_fail "grapple read a documented token as its principles: $(grep -a 'Principles' <<< "$output")"
        else
            test_pass
        fi
    done < <(extract_examples "$required" "$doc")

    local wanted
    for wanted in ${required//|/ }; do
        test_case "$label documents at least one runnable '$wanted' example"
        if [[ " ${seen[*]:-} " == *" $wanted "* ]]; then
            test_pass
        else
            test_fail "no quoted-prompt '$wanted' example extracted from ${doc#$PROJECT_ROOT/}"
        fi
    done
}

check_dry_run_examples "KNOWLEDGE-WORKERS.md" "advise|synthesize|empathize|grapple" "$KW_DOC"
check_dry_run_examples "skill-security-audit" "squeeze" "$AUDIT_SKILL"

prior_phase_output() {
    case "$1" in
        grasp|define) printf '%s' probe-synthesis ;;
        tangle|develop) printf '%s' grasp-consensus ;;
        ink|deliver) printf '%s' tangle-validation ;;
    esac
}

names_output() {
    [[ "$(printf '%s' "$1" | tr '[:upper:]_' '[:lower:]-')" == *"$2"* ]]
}

phase_records="$(extract_examples "grasp|tangle|ink|define|develop|deliver" "$PARALLEL_SKILL")"

test_case "skill-parallel-agents phase examples pass only <prompt> [previous phase's results file]"
phase_problems=""
while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    IFS=$'\x1f' read -r -a parts <<< "$record"
    location="${parts[0]#"$PROJECT_ROOT"/}"
    if [[ "${parts[1]}" == "!unparsable" ]]; then
        phase_problems+="$location: unbalanced quoting: ${parts[2]}"$'\n'
        continue
    fi
    for arg in "${parts[@]:2}"; do
        if [[ "$arg" == -* ]]; then
            phase_problems+="$location: passes an option: ${parts[*]:1}"$'\n'
        fi
    done
    if [[ "${#parts[@]}" -lt 3 ]]; then
        phase_problems+="$location: missing the prompt: ${parts[*]:1}"$'\n'
    elif [[ "${#parts[@]}" -gt 4 ]]; then
        phase_problems+="$location: passes more than two arguments: ${parts[*]:1}"$'\n'
    elif [[ "${#parts[@]}" -eq 4 ]] && ! names_output "${parts[3]}" "$(prior_phase_output "${parts[1]}")"; then
        phase_problems+="$location: results file '${parts[3]}' is not the $(prior_phase_output "${parts[1]}") output"$'\n'
    fi
done <<< "$phase_records"
if [[ -z "$phase_problems" ]]; then
    test_pass
else
    test_fail "$phase_problems"
fi

for phase in grasp tangle ink; do
    expected_output="$(prior_phase_output "$phase")"
    test_case "skill-parallel-agents shows $phase chained from the $expected_output file"
    phase_chained=false
    while IFS= read -r record; do
        [[ -n "$record" ]] || continue
        IFS=$'\x1f' read -r -a parts <<< "$record"
        if [[ "${#parts[@]}" -eq 4 && "${parts[1]}" == "$phase" ]] \
            && names_output "${parts[3]}" "$expected_output"; then
            phase_chained=true
        fi
    done <<< "$phase_records"
    if [[ "$phase_chained" == true ]]; then
        test_pass
    else
        test_fail "no $phase example passes the $expected_output results file"
    fi
done

test_summary
