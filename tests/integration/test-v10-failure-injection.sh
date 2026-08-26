#!/usr/bin/env bash
# End-to-end v10 failure injection through scripts/orchestrate.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/v10-failure-fixtures.sh"
test_suite "v10 end-to-end failure injection"

ORACLES="$PROJECT_ROOT/tests/fixtures/v10-failure-oracles.tsv"
fixture_template="$TEST_TMP_DIR/v10-provider-template.sh"
v10_fixture_write_template "$fixture_template"

system_path="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

run_case() {
    local scenario="$1" target="$2"
    local root="$TEST_TMP_DIR/cases/$scenario"
    local home="$root/home" project="$root/project"
    local state="$root/workspace" runtime="$root/runtime"
    local fake_bin prompt="Exercise the $scenario end-to-end fixture."
    mkdir -p "$home" "$project" "$runtime"
    fake_bin="$(v10_fixture_install "$root" "$scenario")"

    if [[ "$scenario" == health-fail ]]; then
        rm -f "$fake_bin/agy"
    fi

    if [[ "$scenario" == persistence-fail ]]; then
        : > "$state"
    else
        mkdir -p "$state"
    fi
    if [[ "$scenario" == oversize ]]; then
        prompt="This prompt is intentionally longer than the injected thirty-two byte provider ceiling."
    fi

    local timeout=5 allowed=agy max_payload=1048576
    case "$scenario" in
        # Leave enough wall-clock headroom for preflight so these fixtures
        # deterministically enter provider dispatch before timing out.
        timeout|partial-then-timeout|child-tree) timeout=3 ;;
        oversize) max_payload=32 ;;
    esac

    set +e
    (
        cd "$project"
        env -i \
          HOME="$home" USER="octopus-e2e" SHELL="/bin/bash" TERM="dumb" \
          LANG="C" LC_ALL="C" TMPDIR="$runtime" \
          PATH="$fake_bin:$system_path" \
          CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" CLAUDE_PLUGIN_DATA="$state" \
          CLAUDE_CODE_SESSION_ID="v10-$scenario" OCTOPUS_RUN_ID="v10-$scenario" \
          OCTOPUS_PROJECT_DIR="$project" OCTO_ALLOWED_PROVIDERS="$allowed" \
          OCTOPUS_SKIP_PROVIDER_PROBES="true" OCTOPUS_DEBUG="false" \
          OCTOPUS_AGENT_TIMEOUT="$timeout" OCTOPUS_AGY_PRINT_TIMEOUT="${timeout}s" \
          OCTOPUS_AGY_MAX_PAYLOAD_BYTES="$max_payload" \
          OCTOPUS_AGY_FORCE_INLINE="0" OCTOPUS_AGY_NO_PTY_FALLBACK="1" \
          OCTOPUS_ALLOW_FULL_AGY_ENV="false" OCTO_EVENT_LOG="$state/events.jsonl" \
          OPENAI_API_KEY= CLAUDE_SDK_API_KEY= ANTHROPIC_API_KEY= GEMINI_API_KEY= \
          GOOGLE_API_KEY= QWEN_API_KEY= OPENROUTER_API_KEY= ORCAROUTER_API_KEY= \
          PERPLEXITY_API_KEY= XAI_API_KEY= CURSOR_API_KEY= MISTRAL_API_KEY= \
          /bin/bash "$PROJECT_ROOT/scripts/orchestrate.sh" spawn "$target" "$prompt"
    ) > "$root/stdout" 2> "$root/stderr"
    case_rc=$?
    set -e
    printf '%s\n' "$case_rc" > "$root/rc"
}

assert_case() {
    local scenario="$1" target="$2" expected_rc="$3" expected_calls="$4"
    local expected_transitions="$5" expected_terminal="$6"
    local expected_contribution="$7" expected_reason="$8" artifact_policy="$9"
    local root="$TEST_TMP_DIR/cases/$scenario" ledger
    local calls=0 transitions=- terminal=- contribution=- reason=- artifact=""
    local unexpected=0 synthesis=0 cache_messages=0 temp_files=0 descendants=dead

    run_case "$scenario" "$target"
    ledger="$root/workspace/runs/v10-$scenario/seats.jsonl"
    [[ -f "$root/provider-calls.tsv" ]] && calls="$(awk -F '\t' '$1 == "dispatch" {n++} END {print n + 0}' "$root/provider-calls.tsv")"
    [[ -f "$root/provider-calls.tsv" ]] && unexpected="$(awk -F '\t' '$1 == "unexpected" {n++} END {print n + 0}' "$root/provider-calls.tsv")"
    if [[ -s "$ledger" ]]; then
        transitions="$(jq -r '.transition' "$ledger" | paste -sd, -)"
        terminal="$(jq -r '.transition' "$ledger" | tail -1)"
        contribution="$(jq -r '.contribution' "$ledger" | tail -1)"
        reason="$(jq -r '.reason' "$ledger" | tail -1)"
        artifact="$(jq -r '.artifacts.output // ""' "$ledger" | tail -1)"
    fi
    synthesis="$(find "$root" -type f \( -name '*synthesis*' -o -name '*aggregate*' \) 2>/dev/null | wc -l | tr -d ' ')"
    cache_messages="$({ grep -Ehi '(^|[^[:alpha:]])cached([^[:alpha:]]|$)' "$root/stdout" "$root/stderr" 2>/dev/null || true; } | wc -l | tr -d ' ')"
    temp_files="$(find "$root" -type f \( -name '.tmp-agent-*' -o -name '*.tmp' -o -name 'octo-agy-*' \) 2>/dev/null | wc -l | tr -d ' ')"
    if [[ -s "$root/child.pid" ]]; then
        child_pid="$(cat "$root/child.pid")"
        if kill -0 "$child_pid" 2>/dev/null; then
            descendants=alive
            kill -KILL "$child_pid" 2>/dev/null || true
        fi
    fi

    local artifact_ok=false
    if [[ "$artifact_policy" == required && -n "$artifact" && -s "$artifact" ]]; then
        artifact_ok=true
    elif [[ "$artifact_policy" == forbidden && ( -z "$artifact" || ! -e "$artifact" ) ]]; then
        artifact_ok=true
    fi

    test_case "$scenario matches the end-to-end failure oracle"
    if [[ "$(cat "$root/rc")" == "$expected_rc" ]] &&
       [[ "$calls" == "$expected_calls" ]] &&
       [[ "$transitions" == "$expected_transitions" ]] &&
       [[ "$terminal" == "$expected_terminal" ]] &&
       [[ "$contribution" == "$expected_contribution" ]] &&
       [[ "$reason" == "$expected_reason" || ( "$expected_reason" == - && -z "$reason" ) ]] &&
       [[ "$unexpected" == 0 && "$synthesis" == 0 && "$cache_messages" == 0 ]] &&
       [[ "$temp_files" == 0 && "$descendants" == dead && "$artifact_ok" == true ]]; then
        test_pass
    else
        test_fail "rc=$(cat "$root/rc") calls=$calls transitions=$transitions terminal=$terminal contribution=$contribution reason=$reason artifact=$artifact_policy/$artifact unexpected=$unexpected synthesis=$synthesis cache=$cache_messages temp=$temp_files descendants=$descendants"
    fi
}

while IFS=$'\t' read -r scenario target rc calls transitions terminal contribution reason artifact; do
    [[ -n "$scenario" && "$scenario" != \#* ]] || continue
    assert_case "$scenario" "$target" "$rc" "$calls" "$transitions" "$terminal" "$contribution" "$reason" "$artifact"
done < "$ORACLES"

test_case "every checked-in failure oracle executed without skips"
oracle_count="$(awk -F '\t' '$1 !~ /^#/ && NF {n++} END {print n + 0}' "$ORACLES")"
if [[ "$TESTS_SKIPPED" -eq 0 && "$TESTS_TOTAL" -eq $((oracle_count + 1)) ]]; then
    test_pass
else
    test_fail "expected $oracle_count scenarios and zero skips; total=$TESTS_TOTAL skipped=$TESTS_SKIPPED"
fi

test_summary
