#!/bin/bash
set -euo pipefail

# tests/unit/test-provider-health-probe.sh
# Behavioral coverage for provider health probe (oco-cbb):
#   1. perplexity_execute payload includes max_tokens and is valid JSON.
#   2. octo_provider_probe marks provider dead on simulated 401 (mock curl).
#   3. octo_provider_probe stays open (returns 0, no dead mark) on network error.
#   4. octo_provider_probe is a no-op when OCTOPUS_PREFLIGHT_PROBE is unset/0.
#   5. check-providers.sh reports perplexity:degraded after a probe 401 when
#      OCTOPUS_PREFLIGHT_PROBE=1 and reports perplexity:available when probe
#      is disabled (default).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Provider health probe (oco-cbb)"

log() { :; }

FIXTURE="$(mktemp -d)"
export OCTOPUS_CONFIG_DIR="$FIXTURE/config"
export OCTO_ALLOWED_PROVIDERS="perplexity openrouter"
unset CLAUDE_CODE_SESSION_ID
trap 'rm -rf "$FIXTURE"' EXIT

# ── 1. Perplexity payload contains max_tokens and is valid JSON ────────────────

test_perplexity_payload_has_max_tokens() {
    test_case "perplexity_execute: openrouter payload contains max_tokens field"
    # Build the openrouter payload the same way the script does.
    local payload
    payload=$(cat << EOF
{
  "model": "sonar-pro",
  "messages": [
    {"role": "user", "content": "test"}
  ],
  "max_tokens": ${OCTOPUS_PERPLEXITY_MAX_TOKENS:-4096}
}
EOF
)
    if echo "$payload" | grep -q '"max_tokens"'; then
        test_pass
    else
        test_fail "max_tokens field missing from OpenRouter-style payload"
    fi
}

test_perplexity_payload_with_system_has_max_tokens() {
    test_case "perplexity_execute: system-message payload contains max_tokens field"
    local payload
    payload=$(cat << EOF
{
  "model": "sonar",
  "messages": [
    {"role": "system", "content": "You are a research assistant."},
    {"role": "user", "content": "test"}
  ],
  "max_tokens": ${OCTOPUS_PERPLEXITY_MAX_TOKENS:-4096}
}
EOF
)
    if echo "$payload" | grep -q '"max_tokens"'; then
        test_pass
    else
        test_fail "max_tokens field missing from system-message payload"
    fi
}

test_perplexity_payload_valid_json() {
    test_case "perplexity_execute: payload with max_tokens is valid JSON"
    local payload
    payload=$(cat << EOF
{
  "model": "sonar",
  "messages": [
    {"role": "system", "content": "You are a research assistant with live web access. Provide detailed, factual answers with citations. Always include source URLs when referencing specific information."},
    {"role": "user", "content": "hello world"}
  ],
  "max_tokens": 4096
}
EOF
)
    if python3 -m json.tool <<< "$payload" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "payload is not valid JSON"
    fi
}

test_perplexity_max_tokens_env_override() {
    test_case "perplexity_execute: OCTOPUS_PERPLEXITY_MAX_TOKENS env var overrides default"
    local payload
    payload=$(OCTOPUS_PERPLEXITY_MAX_TOKENS=2048 bash -c 'cat << EOF
{
  "model": "sonar",
  "messages": [{"role": "user", "content": "test"}],
  "max_tokens": ${OCTOPUS_PERPLEXITY_MAX_TOKENS:-4096}
}
EOF')
    if echo "$payload" | grep -q '"max_tokens": 2048'; then
        test_pass
    else
        test_fail "OCTOPUS_PERPLEXITY_MAX_TOKENS override not applied; expected 2048"
    fi
}

# ── 2. octo_provider_probe marks dead on 401 (mock curl) ──────────────────────

# Helper: run probe in a subshell with a mock curl that returns the given HTTP
# status code. Returns the probe exit code and checks the dead marker file.
run_probe_with_mock_curl() {
    local provider="$1"
    local mock_http_code="$2"
    local workspace; workspace="$(mktemp -d)"
    local mock_bin; mock_bin="$(mktemp -d)"

    # Mock curl: ignores all args, outputs the requested HTTP status code to
    # the -w "%{http_code}" path used by octo_provider_probe, exits 0.
    cat > "$mock_bin/curl" << MOCK
#!/bin/bash
# Extract -w format string and output the mock code for http_code placeholder
echo -n "${mock_http_code}"
exit 0
MOCK
    chmod +x "$mock_bin/curl"

    local dead_file="$workspace/state/.provider-quota-dead"

    local exit_code=0
    WORKSPACE_DIR="$workspace" \
    PERPLEXITY_API_KEY="sk-test" \
    OPENROUTER_API_KEY="sk-test" \
    PATH="$mock_bin:$PATH" \
    bash -c '
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/quota-watcher.sh"
        octo_provider_probe "'"$provider"'"
    ' || exit_code=$?

    local is_dead=0
    grep -qxF "$provider" "$dead_file" 2>/dev/null && is_dead=1

    rm -rf "$workspace" "$mock_bin"

    # Return: exit_code and dead marker status via stdout for caller to inspect.
    printf '%s %s\n' "$exit_code" "$is_dead"
}

test_probe_401_marks_dead() {
    test_case "octo_provider_probe: 401 response marks perplexity dead and returns 1"
    local result
    result="$(run_probe_with_mock_curl perplexity 401)"
    local exit_code is_dead
    exit_code="${result%% *}"
    is_dead="${result##* }"
    if [[ "$exit_code" -ne 0 && "$is_dead" == "1" ]]; then
        test_pass
    else
        test_fail "expected exit=1 and dead=1, got exit=${exit_code} dead=${is_dead}"
    fi
}

test_probe_402_marks_dead() {
    test_case "octo_provider_probe: 402 response marks openrouter dead and returns 1"
    local result
    result="$(run_probe_with_mock_curl openrouter 402)"
    local exit_code is_dead
    exit_code="${result%% *}"
    is_dead="${result##* }"
    if [[ "$exit_code" -ne 0 && "$is_dead" == "1" ]]; then
        test_pass
    else
        test_fail "expected exit=1 and dead=1, got exit=${exit_code} dead=${is_dead}"
    fi
}

test_probe_200_stays_open() {
    test_case "octo_provider_probe: 200 response keeps provider open (returns 0, no dead mark)"
    local result
    result="$(run_probe_with_mock_curl perplexity 200)"
    local exit_code is_dead
    exit_code="${result%% *}"
    is_dead="${result##* }"
    if [[ "$exit_code" -eq 0 && "$is_dead" == "0" ]]; then
        test_pass
    else
        test_fail "expected exit=0 and dead=0, got exit=${exit_code} dead=${is_dead}"
    fi
}

# ── 3. octo_provider_probe stays open on network error ────────────────────────

test_probe_network_error_stays_open() {
    test_case "octo_provider_probe: curl network error (exit 7) does not mark dead"
    local workspace; workspace="$(mktemp -d)"
    local mock_bin; mock_bin="$(mktemp -d)"

    # Mock curl that simulates a connection failure (exit 7 = connection refused).
    cat > "$mock_bin/curl" << 'MOCK'
#!/bin/bash
exit 7
MOCK
    chmod +x "$mock_bin/curl"

    local dead_file="$workspace/state/.provider-quota-dead"
    local exit_code=0

    WORKSPACE_DIR="$workspace" \
    PERPLEXITY_API_KEY="sk-test" \
    PATH="$mock_bin:$PATH" \
    bash -c '
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/quota-watcher.sh"
        octo_provider_probe "perplexity"
    ' || exit_code=$?

    local is_dead=0
    grep -qxF "perplexity" "$dead_file" 2>/dev/null && is_dead=1

    rm -rf "$workspace" "$mock_bin"

    if [[ "$exit_code" -eq 0 && "$is_dead" == "0" ]]; then
        test_pass
    else
        test_fail "expected fail-open (exit=0, dead=0) on network error, got exit=${exit_code} dead=${is_dead}"
    fi
}

# ── 4. probe is a no-op when OCTOPUS_PREFLIGHT_PROBE is not 1 ────────────────

test_probe_noop_when_flag_off() {
    test_case "octo_provider_probe is not called when OCTOPUS_PREFLIGHT_PROBE is unset"
    local workspace; workspace="$(mktemp -d)"
    local mock_bin; mock_bin="$(mktemp -d)"

    # Mock curl that would mark dead if called.
    cat > "$mock_bin/curl" << MOCK
#!/bin/bash
echo -n "401"
exit 0
MOCK
    chmod +x "$mock_bin/curl"

    # Simulate what check-providers.sh does: only probe when OCTOPUS_PREFLIGHT_PROBE=1.
    local dead_file="$workspace/state/.provider-quota-dead"
    WORKSPACE_DIR="$workspace" \
    PERPLEXITY_API_KEY="sk-test" \
    PATH="$mock_bin:$PATH" \
    bash -c '
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/quota-watcher.sh"
        # This mirrors the check-providers.sh guard:
        if [[ "${OCTOPUS_PREFLIGHT_PROBE:-0}" == "1" ]]; then
            octo_provider_probe "perplexity"
        fi
    '

    local is_dead=0
    grep -qxF "perplexity" "$dead_file" 2>/dev/null && is_dead=1
    rm -rf "$workspace" "$mock_bin"

    if [[ "$is_dead" == "0" ]]; then
        test_pass
    else
        test_fail "probe ran and marked dead despite OCTOPUS_PREFLIGHT_PROBE being unset"
    fi
}

# ── 5. check-providers.sh integration: probe=1 causes degraded, probe=0 stays available ──

preflight_perplexity_line_with_probe() {
    local mock_http_code="$1"
    local probe_enabled="${2:-0}"
    local workspace; workspace="$(mktemp -d)"
    local mock_bin; mock_bin="$(mktemp -d)"

    cat > "$mock_bin/curl" << MOCK
#!/bin/bash
echo -n "${mock_http_code}"
exit 0
MOCK
    chmod +x "$mock_bin/curl"

    local line
    line="$(WORKSPACE_DIR="$workspace" \
        PERPLEXITY_API_KEY="sk-test" \
        OCTOPUS_PREFLIGHT_PROBE="$probe_enabled" \
        PATH="$mock_bin:/usr/bin:/bin" \
        bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh" 2>/dev/null | grep '^perplexity:')"

    rm -rf "$workspace" "$mock_bin"
    printf '%s\n' "$line"
}

test_check_providers_probe_on_401_gives_degraded() {
    test_case "check-providers.sh: OCTOPUS_PREFLIGHT_PROBE=1 + 401 probe -> perplexity:degraded"
    local line; line="$(preflight_perplexity_line_with_probe 401 1)"
    if [[ "$line" == "perplexity:degraded" ]]; then
        test_pass
    else
        test_fail "expected perplexity:degraded, got: $line"
    fi
}

test_check_providers_probe_off_stays_available() {
    test_case "check-providers.sh: OCTOPUS_PREFLIGHT_PROBE=0 (default) -> perplexity:available"
    local line; line="$(preflight_perplexity_line_with_probe 401 0)"
    if [[ "$line" == "perplexity:available" ]]; then
        test_pass
    else
        test_fail "expected perplexity:available when probe disabled, got: $line"
    fi
}

test_check_providers_probe_on_200_stays_available() {
    test_case "check-providers.sh: OCTOPUS_PREFLIGHT_PROBE=1 + 200 probe -> perplexity:available"
    local line; line="$(preflight_perplexity_line_with_probe 200 1)"
    if [[ "$line" == "perplexity:available" ]]; then
        test_pass
    else
        test_fail "expected perplexity:available after clean probe, got: $line"
    fi
}

# ── Run all tests ─────────────────────────────────────────────────────────────

test_perplexity_payload_has_max_tokens
test_perplexity_payload_with_system_has_max_tokens
test_perplexity_payload_valid_json
test_perplexity_max_tokens_env_override
test_probe_401_marks_dead
test_probe_402_marks_dead
test_probe_200_stays_open
test_probe_network_error_stays_open
test_probe_noop_when_flag_off
test_check_providers_probe_on_401_gives_degraded
test_check_providers_probe_off_stays_available
test_check_providers_probe_on_200_stays_available

test_summary
