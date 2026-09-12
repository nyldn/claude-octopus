#!/bin/bash
# Hermetic lifecycle checks for the current plugin candidate.
# Native Claude CLI installation is opt-in and still uses an isolated host home.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Plugin lifecycle isolation"

candidate_command() (
    local home="$1"
    local host="$2"
    local root="$3"
    shift 3
    cd "$home" || return 1

    case "$host" in
        claude)
            env -i HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" \
                TMPDIR="$home/tmp" PATH="$PATH" \
                OCTOPUS_HOST=claude CLAUDE_PLUGIN_ROOT="$root" \
                OCTOPUS_INSTALL_SCOPE=user "$PROJECT_ROOT/bin/octopus" "$@"
            ;;
        codex)
            env -i HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" TMPDIR="$home/tmp" \
                CODEX_HOME="$home/.codex" PATH="$PATH" OCTOPUS_HOST=codex \
                CODEX_PLUGIN_ROOT="$root" OCTOPUS_INSTALL_SCOPE=user \
                "$PROJECT_ROOT/bin/octopus" "$@"
            ;;
        *)
            printf 'Unsupported test host: %s\n' "$host" >&2
            return 2
            ;;
    esac
)

isolated_claude() {
    local home="$1"
    shift
    (
        cd "$home" || return 1
        env -i HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" \
            TMPDIR="$home/tmp" PATH="$PATH" \
            DISABLE_TELEMETRY=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
            claude "$@"
    )
}

test_legacy_safety_regression() {
    test_case "lifecycle suite cannot target a real host or remote marketplace"
    local unsafe=""
    local legacy_home_delete="rm -""rf ~/"
    local legacy_remote="https""://"
    local legacy_status="local output=\$""(claude"
    local match
    for match in "$legacy_home_delete" "$legacy_remote" "$legacy_status"; do
        if grep -Fn -- "$match" "$SCRIPT_PATH" >/dev/null 2>&1; then
            unsafe="${unsafe}${unsafe:+; }$match"
        fi
    done
    if [[ -z "$unsafe" ]] && grep -Fq 'CLAUDE_CONFIG_DIR=' "$SCRIPT_PATH"; then
        test_pass
    else
        test_fail "unsafe lifecycle pattern found: ${unsafe:-missing CLAUDE_CONFIG_DIR isolation}"
    fi
}

test_claude_failure_status_is_preserved() {
    test_case "Claude command failures retain their original status"
    local stub_bin="$TEST_TMP_DIR/status-bin"
    local home="$TEST_TMP_DIR/status-home"
    local output rc=0
    mkdir -p "$stub_bin" "$home/.claude" "$home/tmp"
    {
        printf '%s\n' '#!/bin/bash'
        printf '%s\n' 'printf "stub failure\\n" >&2'
        printf '%s\n' 'exit 23'
    } > "$stub_bin/claude"
    chmod +x "$stub_bin/claude"

    if output="$(PATH="$stub_bin:$PATH" isolated_claude "$home" plugin list 2>&1)"; then
        rc=0
    else
        rc=$?
    fi
    if [[ "$rc" -eq 23 && "$output" == "stub failure" ]]; then
        test_pass
    else
        test_fail "Claude failure was swallowed (exit=$rc output=${output:-<empty>})"
    fi
}

test_candidate_lifecycle_is_hermetic() {
    test_case "candidate health commands preserve isolated host and user state"
    local home="$TEST_TMP_DIR/candidate-home"
    local state="$home/.claude-octopus/install-state.json"
    local sentinel="$home/.claude-octopus/results/user-result.txt"
    local before after repair_json missing_rc=0 failures=0
    mkdir -p "$(dirname "$sentinel")" "$home/.claude" "$home/.codex" "$home/tmp"
    printf '%s\n' 'keep-user-result' > "$sentinel"

    candidate_command "$home" claude "$PROJECT_ROOT" install-state record \
        > "$TEST_TMP_DIR/claude-record.log" 2>&1 || failures=$((failures + 1))
    candidate_command "$home" codex "$PROJECT_ROOT" install-state record \
        > "$TEST_TMP_DIR/codex-record.log" 2>&1 || failures=$((failures + 1))
    candidate_command "$home" claude "$PROJECT_ROOT" install-state record \
        > "$TEST_TMP_DIR/claude-rerecord.log" 2>&1 || failures=$((failures + 1))

    before="$(cksum "$state" 2>/dev/null || true)"
    if candidate_command "$home" claude "$home/missing-candidate" install-state record \
        > "$TEST_TMP_DIR/missing-root.log" 2>&1; then
        missing_rc=0
    else
        missing_rc=$?
    fi
    after="$(cksum "$state" 2>/dev/null || true)"

    repair_json="$(candidate_command "$home" claude "$PROJECT_ROOT" \
        repair --dry-run --json 2>/dev/null || true)"

    if [[ "$failures" -eq 0 && "$missing_rc" -ne 0 && "$before" == "$after" ]] &&
       [[ ! -e "$home/.claude-octopus/plugin" ]] &&
       [[ "$(cat "$sentinel" 2>/dev/null || true)" == "keep-user-result" ]] &&
       jq -e --arg root "$PROJECT_ROOT" '
           .schema == 2 and (.hosts | keys | sort) == ["claude","codex"] and
           .hosts.claude.plugin_root == $root and
           .hosts.codex.plugin_root == $root
       ' "$state" >/dev/null 2>&1 &&
       jq -e '.mode == "dry-run" and .status == "missing" and .result == "ready"' \
           <<<"$repair_json" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "candidate lifecycle isolation failed (commands=$failures missing-exit=$missing_rc)"
    fi
}

run_native_claude_acceptance() {
    test_case "opt-in Claude lifecycle installs the local candidate"
    if [[ "${OCTOPUS_RUN_CLAUDE_LIFECYCLE_ACCEPTANCE:-0}" != "1" ]]; then
        test_skip "set OCTOPUS_RUN_CLAUDE_LIFECYCLE_ACCEPTANCE=1 to run isolated native acceptance"
        return 0
    fi
    if ! command -v claude >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        test_skip "Claude CLI and jq are required for native acceptance"
        return 0
    fi

    local home="$TEST_TMP_DIR/native-home"
    local marketplace="$TEST_TMP_DIR/local-marketplace"
    local sentinel="$home/.claude-octopus/results/user-result.txt"
    local candidate_version output rc=0 failures=0
    mkdir -p "$home/.claude" "$home/tmp" "$(dirname "$sentinel")" \
        "$marketplace/.claude-plugin" "$marketplace/plugins"
    printf '%s\n' 'keep-user-result' > "$sentinel"
    ln -s "$PROJECT_ROOT" "$marketplace/plugins/candidate"
    candidate_version="$(jq -r '.version' "$PROJECT_ROOT/.claude-plugin/plugin.json")"
    jq -n --arg version "$candidate_version" '{
        name:"octopus-candidate",
        owner:{name:"acceptance"},
        plugins:[{name:"octo",source:"./plugins/candidate",version:$version}]
    }' > "$marketplace/.claude-plugin/marketplace.json"

    if output="$(isolated_claude "$home" plugin marketplace add "$marketplace" 2>&1)"; then
        rc=0
    else
        rc=$?
    fi
    [[ "$rc" -eq 0 ]] || { printf '%s\n' "$output" >&2; failures=$((failures + 1)); }

    if output="$(isolated_claude "$home" plugin install octo@octopus-candidate --scope user 2>&1)"; then
        rc=0
    else
        rc=$?
    fi
    [[ "$rc" -eq 0 ]] || { printf '%s\n' "$output" >&2; failures=$((failures + 1)); }

    if output="$(isolated_claude "$home" plugin list 2>&1)"; then
        rc=0
    else
        rc=$?
    fi
    [[ "$rc" -eq 0 && "$output" == *"octo"* ]] || failures=$((failures + 1))

    if output="$(isolated_claude "$home" plugin update octo --scope user 2>&1)"; then
        rc=0
    else
        rc=$?
    fi
    [[ "$rc" -eq 0 ]] || { printf '%s\n' "$output" >&2; failures=$((failures + 1)); }

    if output="$(isolated_claude "$home" plugin uninstall octo --scope user 2>&1)"; then
        rc=0
    else
        rc=$?
    fi
    [[ "$rc" -eq 0 ]] || { printf '%s\n' "$output" >&2; failures=$((failures + 1)); }

    if output="$(isolated_claude "$home" plugin list 2>&1)"; then
        rc=0
    else
        rc=$?
    fi
    [[ "$rc" -eq 0 && "$output" != *"octo@octopus-candidate"* ]] || \
        failures=$((failures + 1))

    if [[ "$failures" -eq 0 ]] &&
       [[ "$(cat "$sentinel" 2>/dev/null || true)" == "keep-user-result" ]]; then
        test_pass
    else
        test_fail "isolated native lifecycle had $failures failure(s) or changed user data"
    fi
}

test_legacy_safety_regression
test_claude_failure_status_is_preserved
test_candidate_lifecycle_is_hermetic
run_native_claude_acceptance

test_summary
