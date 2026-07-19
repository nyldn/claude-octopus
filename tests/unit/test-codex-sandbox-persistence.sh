#!/usr/bin/env bash
# Regression coverage for issue #648: restricted Codex hosts must not let
# optional Octopus persistence block an otherwise healthy provider call.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="/tmp/octopus-tests-$$"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Codex sandbox persistence degradation"

prepare_cleanup() {
    chmod u+w "$TEST_TMP_DIR/home/.claude-octopus" "$TEST_TMP_DIR/home" 2>/dev/null || true
    chmod -R u+w "$TEST_TMP_DIR" 2>/dev/null || true
}

cleanup_fixture() {
    prepare_cleanup
    cleanup_test_environment
}

after_all prepare_cleanup
trap cleanup_fixture EXIT INT TERM

test_case "event logging fails open without stderr when its path is denied"
readonly_events="$TEST_TMP_DIR/readonly-events"
mkdir -p "$readonly_events"
chmod 500 "$readonly_events"

set +e
(
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/lib/events.sh"
    export OCTO_EVENT_LOG="$readonly_events/events.jsonl"
    octo_event_emit "sandbox.test" "host=codex"
) >"$TEST_TMP_DIR/event.stdout" 2>"$TEST_TMP_DIR/event.stderr"
event_rc=$?
set -e

if [[ "$event_rc" -eq 0 ]] && \
   [[ ! -s "$TEST_TMP_DIR/event.stdout" ]] && \
   [[ ! -s "$TEST_TMP_DIR/event.stderr" ]] && \
   [[ ! -e "$readonly_events/events.jsonl" ]]; then
    test_pass
else
    test_fail "optional event logging changed command behavior (rc=$event_rc, stderr=$(<"$TEST_TMP_DIR/event.stderr"))"
fi

test_case "debug mode emits one valid structured persistence diagnostic"
diagnostic_root="$TEST_TMP_DIR/state with spaces"
diagnostic_output=$( {
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/lib/utils.sh"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/lib/state-root.sh"
    export OCTOPUS_PERSISTENCE_AVAILABLE=false
    export OCTOPUS_DEBUG=true
    export WORKSPACE_DIR="$diagnostic_root"
    octopus_persistence_diagnostic
    octopus_persistence_diagnostic
} 2>&1 )

diagnostic_lines=$(printf '%s\n' "$diagnostic_output" | wc -l | tr -d ' ')
if [[ "$diagnostic_lines" -eq 1 ]] && \
   [[ "$(printf '%s' "$diagnostic_output" | jq -r '.event')" == "persistence.disabled" ]] && \
   [[ "$(printf '%s' "$diagnostic_output" | jq -r '.state_root')" == "$diagnostic_root" ]]; then
    test_pass
else
    test_fail "debug persistence diagnostic was not one valid JSON record: $diagnostic_output"
fi

test_case "Codex host streams provider output when legacy state root is denied"
fake_home="$TEST_TMP_DIR/home"
fake_bin="$TEST_TMP_DIR/bin"
project_dir="$TEST_TMP_DIR/project"
mkdir -p "$fake_home/.claude-octopus" "$fake_bin" "$project_dir"
ln -s "$PROJECT_ROOT" "$fake_home/.claude-octopus/plugin"

cat >"$fake_bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    --version)
        echo "2.1.214 (Claude Code)"
        exit 0
        ;;
    --help)
        echo "--setting-sources <sources>"
        exit 0
        ;;
esac

if [[ " $* " != *" --setting-sources project,local "* ]]; then
    echo "nested Claude did not exclude user/plugin settings" >&2
    exit 42
fi

cat >/dev/null
echo "SANDBOX_PROVIDER_OK"
FAKE_CLAUDE
chmod +x "$fake_bin/claude"

# Existing legacy layout, but denied by the outer host. The stable plugin link
# is created before permissions are removed so startup does not need to heal it.
chmod 500 "$fake_home" "$fake_home/.claude-octopus"

set +e
(
    cd "$project_dir"
    HOME="$fake_home" \
    PATH="$fake_bin:$PATH" \
    CI= \
    GITHUB_ACTIONS= \
    CODEX_SANDBOX=workspace-write \
    OCTOPUS_SKIP_PROVIDER_PROBES=true \
    OCTOPUS_DEBUG=false \
        bash "$PROJECT_ROOT/scripts/orchestrate.sh" spawn claude \
            "Reply exactly SANDBOX_PROVIDER_OK"
) >"$TEST_TMP_DIR/spawn.stdout" 2>"$TEST_TMP_DIR/spawn.stderr"
spawn_rc=$?
set -e

if [[ "$spawn_rc" -eq 0 ]] && \
   grep -q '^SANDBOX_PROVIDER_OK$' "$TEST_TMP_DIR/spawn.stdout" && \
   [[ ! -s "$TEST_TMP_DIR/spawn.stderr" ]]; then
    test_pass
else
    test_fail "restricted Codex dispatch failed (rc=$spawn_rc, stderr=$(<"$TEST_TMP_DIR/spawn.stderr"))"
fi

test_case "synchronous provider path also streams without persistent state"
set +e
sync_output=$(
    source "$PROJECT_ROOT/scripts/lib/state-root.sh"

    log() { :; }
    apply_persona() { printf '%s' "$2"; }
    get_persona_override() { return 1; }
    load_earned_skills() { :; }
    build_provider_context() { :; }
    sanitize_external_content() { printf '%s' "$1"; }
    enforce_context_budget() { printf '%s' "$1"; }
    get_agent_model() { echo "test-model"; }
    check_provider_health() { return 0; }
    get_agent_command() { echo "$fake_bin/claude --setting-sources project,local --print"; }
    build_provider_env() { PROVIDER_ENV_ARRAY=(); }
    run_with_timeout() { local _timeout="$1"; shift; "$@"; }

    export OCTOPUS_PERSISTENCE_AVAILABLE=false
    export OCTOPUS_DEBUG=false
    export RESULTS_DIR="$readonly_events"
    export WORKSPACE_DIR="$fake_home/.claude-octopus"

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
    run_agent_sync claude "Reply exactly SANDBOX_PROVIDER_OK" 30 reviewer review
) 2>"$TEST_TMP_DIR/sync.stderr"
sync_rc=$?
set -e

if [[ "$sync_rc" -eq 0 ]] && \
   [[ "$sync_output" == "SANDBOX_PROVIDER_OK" ]] && \
   [[ ! -s "$TEST_TMP_DIR/sync.stderr" ]]; then
    test_pass
else
    test_fail "restricted synchronous dispatch failed (rc=$sync_rc, output=$sync_output, stderr=$(<"$TEST_TMP_DIR/sync.stderr"))"
fi

test_summary
