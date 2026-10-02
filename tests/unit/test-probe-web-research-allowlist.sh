#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

log() { :; }

export OCTOPUS_CONFIG_DIR="$TEST_TMP_DIR/probe-web-research-allowlist-root"
unset CLAUDE_CODE_SESSION_ID OCTO_ALLOWED_PROVIDERS PERPLEXITY_API_KEY

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

test_suite "Probe web research seat honors the provider allowlist"

test_case "deep probe with a Perplexity key and no allowlist seats web research"
if PERPLEXITY_API_KEY="fixture-key" probe_web_research_seat_enabled deep; then
    test_pass
else
    test_fail "web research seat should be enabled when no allowlist is set"
fi

test_case "deep probe skips web research when the allowlist excludes perplexity"
if ! OCTO_ALLOWED_PROVIDERS="codex claude" PERPLEXITY_API_KEY="fixture-key" probe_web_research_seat_enabled deep; then
    test_pass
else
    test_fail "allowlist 'codex claude' must keep the perplexity seat out of probe"
fi

test_case "deep probe seats web research when the allowlist includes perplexity"
if OCTO_ALLOWED_PROVIDERS="codex perplexity" PERPLEXITY_API_KEY="fixture-key" probe_web_research_seat_enabled deep; then
    test_pass
else
    test_fail "allowlist naming perplexity should keep the web research seat"
fi

test_case "standard probe never seats web research"
if ! PERPLEXITY_API_KEY="fixture-key" probe_web_research_seat_enabled standard; then
    test_pass
else
    test_fail "web research seat is deep-only"
fi

test_case "deep probe without a Perplexity key never seats web research"
if ! probe_web_research_seat_enabled deep; then
    test_pass
else
    test_fail "web research seat requires PERPLEXITY_API_KEY"
fi

test_case "standalone workflow preserves the optional allowlist helper fallback"
if ( unset -f octo_provider_allowed; PERPLEXITY_API_KEY=fixture-key probe_web_research_seat_enabled deep ); then
    test_pass
else
    test_fail "standalone workflow should permit the keyed deep seat without the allowlist library"
fi

# Run the real chooser, launch loop, result classification, and finalization.
# Only provider I/O and display boundaries use inert fixtures.
probe_workflow_fixture() (
    local name="$1" allowlist="$2" intensity="$3" key="$4" expected="$5" fail_at="${6:-}"
    local fixture="$TEST_TMP_DIR/$name"
    mkdir -p "$fixture/config" "$fixture/results" "$fixture/logs"
    cd "$fixture" || return 1
    export OCTOPUS_CONFIG_DIR="$fixture/config" OCTOPUS_RESEARCH_INTENSITY="$intensity"
    export OCTO_ALLOWED_PROVIDERS="$allowlist" PERPLEXITY_API_KEY="$key"
    if [[ "$allowlist" == global ]]; then
        unset OCTO_ALLOWED_PROVIDERS
        printf 'codex\n' > "$OCTOPUS_CONFIG_DIR/provider-allowlist"
    fi
    unset FORCE_TIER CLAUDE_CODE_SESSION_ID RESEARCH_RUN_DIR
    RESULTS_DIR="$fixture/results"; LOGS_DIR="$fixture/logs"
    DRY_RUN=false; TMUX_MODE=false; ENABLE_PROGRESSIVE_SYNTHESIS=false
    SUPPORTS_AGENT_MEMORY_GC=false; OCTOPUS_RESEARCH_EVIDENCE=false
    MAGENTA=; CYAN=; GREEN=; YELLOW=; RED=; NC=
    preflight_check() { return 0; }
    octopus_phase_banner() { :; }
    display_workflow_cost_estimate() { return 0; }
    get_cache_key() { printf 'fixture\n'; }
    check_cache() { return 1; }
    cleanup_cache() { :; }
    get_dispatch_strategy() { printf 'standard:codex\n'; }
    load_blind_spot_checklist() { :; }
    init_progress_tracking() { printf '%s\n' "$2" > "$fixture/progress-count"; }
    fleet_dispatch_begin() { printf 'begin\n' >> "$fixture/fleet"; }
    fleet_dispatch_end() { printf 'end\n' >> "$fixture/fleet"; }
    display_rich_progress() { :; }
    display_progress_summary() { return 0; }
    _ucfirst() { printf '%s' "$1"; }
    synthesize_probe_results() { printf '%s\n' "$3" > "$fixture/synthesis"; }
    spawn_agent_capture_pid() {
        printf '%s\n' "$1" >> "$fixture/attempts"
        octo_provider_allowed "$1" || return 23
        [[ -z "$fail_at" || "$3" != *"-$fail_at" ]] || return 23
        cat > "$RESULTS_DIR/$1-$3.md" <<'RESULT'
# Agent: fixture
# Prompt-Format: octopus-length-v1
# Prompt-Bytes: 7
fixture
# Started: fixture
<!-- BEGIN-UNTRUSTED:provider=fixture:nonce=0123456789abcdef0123456789abcdef -->
## Output
A substantive inert research result.
<!-- END-UNTRUSTED:provider=fixture:nonce=0123456789abcdef0123456789abcdef -->
## Status: SUCCESS
RESULT
        printf '99999999\n'
    }
    # Fake PIDs never reach process signaling. The cancellation cleanup suite
    # separately exercises the real process ownership and signaling path.
    octopus_probe_cancel_active() {
        printf '%s %s\n' "$1" "${#OCTOPUS_ACTIVE_PROBE_PIDS[@]}" > "$fixture/cancel"
        octopus_probe_clear_active
    }
    local rc=0 count web_count
    probe_discover "Inert allowlist workflow fixture" > "$fixture/output" 2>&1 || rc=$?
    count=$(wc -l < "$fixture/attempts" | tr -d ' ')
    web_count=$(grep -c '^perplexity$' "$fixture/attempts" || true)
    if [[ -n "$fail_at" ]]; then
        [[ "$rc" == 23 && "$count" == 3 && ! -e "$fixture/synthesis" ]] || return 1
        [[ "$(cat "$fixture/cancel")" == 'TERM 2' ]] || return 1
    else
        if [[ "$rc" != 0 || "$count" != "$expected" || -e "$fixture/cancel" ]]; then
            printf 'workflow rc=%s attempts=%s web=%s expected=%s cancel=%s\n' \
                "$rc" "$count" "$web_count" "$expected" "$(cat "$fixture/cancel" 2>/dev/null || true)" >&2
            return 1
        fi
        [[ "$(cat "$fixture/progress-count")" == "$expected" ]] || return 1
        [[ "$(cat "$fixture/synthesis")" == "$expected" ]] || return 1
        if [[ "$expected" == 6 ]]; then [[ "$web_count" == 1 ]] || return 1
        else [[ "$web_count" == 0 ]] || return 1
        fi
    fi
    [[ "$(cat "$fixture/fleet")" == $'begin\nend' ]] || return 1
    [[ -z "${OCTOPUS_ACTIVE_PROBE_TASK_GROUP:-}" ]] || return 1
    [[ -z "$(trap -p INT)$(trap -p TERM)" ]] || return 1
)

for fixture_case in excluded included normalized variant no-allowlist global standard no-key fail-fast; do
    test_case "actual probe workflow: $fixture_case"
    case "$fixture_case" in
        excluded) arguments=(codex deep fixture-key 5) ;;
        included) arguments=('codex perplexity' deep fixture-key 6) ;;
        normalized) arguments=('CODEX,PERPLEXITY' deep fixture-key 6) ;;
        variant) arguments=('codex perplexity-fast' deep fixture-key 6) ;;
        no-allowlist) arguments=('' deep fixture-key 6) ;;
        global) arguments=(global deep fixture-key 5) ;;
        standard) arguments=('codex perplexity' standard fixture-key 5) ;;
        no-key) arguments=('codex perplexity' deep '' 5) ;;
        fail-fast) arguments=('codex perplexity' deep fixture-key 6 2) ;;
    esac
    if probe_workflow_fixture "$fixture_case" "${arguments[@]}"; then
        test_pass
    else
        test_fail "actual workflow fixture failed for $fixture_case"
    fi
done

test_summary
