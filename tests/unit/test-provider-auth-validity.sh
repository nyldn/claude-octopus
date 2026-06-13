#!/bin/bash
set -euo pipefail

# tests/unit/test-provider-auth-validity.sh
# Behavioral coverage for the provider auth-validation gap (oco-dar):
#   1. octo_oauth_token_valid() honors expiry_date and fails closed.
#   2. qwen_auth_method()/qwen_is_usable() treat an expired OAuth token as
#      unusable ("oauth-expired"), not a usable "oauth"; API-key and
#      Coding-Plan env auth take precedence over stale OAuth.
#   3. check-providers.sh reports qwen:degraded (not :available) for an expired
#      token, and qwen:available for a valid one.
#   4. run_with_timeout escalates to SIGKILL so a SIGTERM-ignoring process dies
#      within the cap + kill-after grace (the qwen 10-min hang regression).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Provider auth validity (oco-dar)"

# Stub log() — qwen.sh/heartbeat.sh call it outside orchestrate.sh.
log() { :; }

# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/auth.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/qwen.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh" 2>/dev/null || true

for fn in octo_oauth_token_valid qwen_auth_method qwen_is_usable run_with_timeout; do
    if ! declare -f "$fn" >/dev/null 2>&1; then
        test_case "$fn() is defined"
        test_fail "$fn not sourced"
        test_summary
        exit 1
    fi
done

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

now="$(date +%s)"
echo '{"expiry_date": 1776902104264}'            > "$FIXTURE/past.json"      # 2026-04-22
echo "{\"expiry_date\": $(( (now + 7200) * 1000 ))}" > "$FIXTURE/future.json" # +2h
echo '{"access_token":"x"}'                       > "$FIXTURE/noexpiry.json"
echo 'not json at all'                            > "$FIXTURE/garbage.json"

# ── 1. octo_oauth_token_valid ────────────────────────────────────────────────
test_validator_past_invalid() {
    test_case "octo_oauth_token_valid: expired token is invalid"
    if ! octo_oauth_token_valid "$FIXTURE/past.json"; then test_pass
    else test_fail "expired token accepted as valid"; fi
}
test_validator_future_valid() {
    test_case "octo_oauth_token_valid: unexpired token is valid"
    if octo_oauth_token_valid "$FIXTURE/future.json"; then test_pass
    else test_fail "unexpired token rejected"; fi
}
test_validator_noexpiry_failclosed() {
    test_case "octo_oauth_token_valid: missing expiry_date fails closed"
    if ! octo_oauth_token_valid "$FIXTURE/noexpiry.json"; then test_pass
    else test_fail "token with no expiry_date accepted"; fi
}
test_validator_garbage_failclosed() {
    test_case "octo_oauth_token_valid: unparseable file fails closed"
    if ! octo_oauth_token_valid "$FIXTURE/garbage.json"; then test_pass
    else test_fail "garbage file accepted"; fi
}
test_validator_missing_failclosed() {
    test_case "octo_oauth_token_valid: missing file fails closed"
    if ! octo_oauth_token_valid "$FIXTURE/does-not-exist.json"; then test_pass
    else test_fail "missing file accepted"; fi
}

# ── 2. qwen_auth_method / qwen_is_usable ─────────────────────────────────────
# Run in a subshell with HOME pointed at a fixture so we don't touch ~/.qwen.
qwen_state_with() {  # $1 = fixture creds file (or "none"); echoes auth method
    local creds="$1"
    local home; home="$(mktemp -d)"
    mkdir -p "$home/.qwen"
    [[ "$creds" != "none" ]] && cp "$creds" "$home/.qwen/oauth_creds.json"
    HOME="$home" QWEN_API_KEY="" bash -c '
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/auth.sh"
        source "'"$PROJECT_ROOT"'/scripts/lib/qwen.sh"
        qwen_auth_method
    '
    rm -rf "$home"
}

qwen_state_with_env() {  # $1 = fixture creds file; $2 = shell env assignments
    local creds="$1" env_assignments="$2"
    local home; home="$(mktemp -d)"
    mkdir -p "$home/.qwen"
    cp "$creds" "$home/.qwen/oauth_creds.json"
    local got
    got="$(HOME="$home" bash -c '
        '"$env_assignments"'
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/auth.sh"
        source "'"$PROJECT_ROOT"'/scripts/lib/qwen.sh"
        qwen_auth_method
    ')"
    rm -rf "$home"
    printf '%s\n' "$got"
}

qwen_usable_with() {  # $1 = fixture creds file; $2 = shell env assignments
    local creds="$1" env_assignments="$2"
    local home bin; home="$(mktemp -d)"; bin="$(mktemp -d)"
    mkdir -p "$home/.qwen"
    cp "$creds" "$home/.qwen/oauth_creds.json"
    printf '#!/bin/bash\nprintf "qwen stub\\n"\n' > "$bin/qwen"; chmod +x "$bin/qwen"
    local got
    got="$(HOME="$home" PATH="$bin:$PATH" bash -c '
        '"$env_assignments"'
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/auth.sh"
        source "'"$PROJECT_ROOT"'/scripts/lib/qwen.sh"
        if qwen_is_usable; then echo usable; else echo unusable; fi
    ')"
    rm -rf "$home" "$bin"
    printf '%s\n' "$got"
}

test_qwen_expired_is_oauth_expired() {
    test_case "qwen_auth_method: expired OAuth reports oauth-expired"
    local got; got="$(qwen_state_with "$FIXTURE/past.json")"
    if [[ "$got" == "oauth-expired" ]]; then test_pass
    else test_fail "expected oauth-expired, got: $got"; fi
}
test_qwen_valid_is_oauth() {
    test_case "qwen_auth_method: unexpired OAuth reports oauth"
    local got; got="$(qwen_state_with "$FIXTURE/future.json")"
    if [[ "$got" == "oauth" ]]; then test_pass
    else test_fail "expected oauth, got: $got"; fi
}
test_qwen_without_validator_fails_closed() {
    test_case "qwen_auth_method: OAuth without validator is not usable"
    local home; home="$(mktemp -d)"; mkdir -p "$home/.qwen"
    cp "$FIXTURE/future.json" "$home/.qwen/oauth_creds.json"
    local got
    got="$(HOME="$home" QWEN_API_KEY="" bash -c '
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/qwen.sh"
        qwen_auth_method')"
    rm -rf "$home"
    if [[ "$got" == "oauth-unvalidated" ]]; then test_pass
    else test_fail "expected oauth-unvalidated, got: $got"; fi
}
test_qwen_apikey_precedence() {
    test_case "qwen_auth_method: QWEN_API_KEY wins over expired OAuth"
    local home; home="$(mktemp -d)"; mkdir -p "$home/.qwen"
    cp "$FIXTURE/past.json" "$home/.qwen/oauth_creds.json"
    local got
    got="$(HOME="$home" QWEN_API_KEY="sk-test" bash -c '
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/auth.sh"
        source "'"$PROJECT_ROOT"'/scripts/lib/qwen.sh"
        qwen_auth_method')"
    rm -rf "$home"
    if [[ "$got" == "env:QWEN_API_KEY" ]]; then test_pass
    else test_fail "expected env:QWEN_API_KEY, got: $got"; fi
}
test_qwen_openai_compat_precedence() {
    test_case "qwen_auth_method: Coding-Plan env wins over expired OAuth"
    local got
    got="$(qwen_state_with_env "$FIXTURE/past.json" 'export QWEN_API_KEY=""; export OPENAI_API_KEY="sk-test"; export OPENAI_BASE_URL="https://dashscope-intl.aliyuncs.com/compatible-mode/v1"')"
    if [[ "$got" == "env:OPENAI_COMPAT" ]]; then test_pass
    else test_fail "expected env:OPENAI_COMPAT, got: $got"; fi
}
test_qwen_usable_rejects_expired() {
    test_case "qwen_is_usable: expired OAuth is unusable even when binary exists"
    local got
    got="$(qwen_usable_with "$FIXTURE/past.json" 'export QWEN_API_KEY=""; unset OPENAI_API_KEY OPENAI_BASE_URL')"
    if [[ "$got" == "unusable" ]]; then test_pass
    else test_fail "expected unusable, got: $got"; fi
}
test_qwen_usable_accepts_openai_compat() {
    test_case "qwen_is_usable: Coding-Plan env is usable over expired OAuth"
    local got
    got="$(qwen_usable_with "$FIXTURE/past.json" 'export QWEN_API_KEY=""; export OPENAI_API_KEY="sk-test"; export OPENAI_BASE_URL="https://dashscope-intl.aliyuncs.com/compatible-mode/v1"')"
    if [[ "$got" == "usable" ]]; then test_pass
    else test_fail "expected usable, got: $got"; fi
}

# ── 3. check-providers.sh banner state ───────────────────────────────────────
preflight_qwen_line() {  # $1 = fixture creds file
    local home; home="$(mktemp -d)"; mkdir -p "$home/.qwen"
    cp "$1" "$home/.qwen/oauth_creds.json"
    # Provide a fake qwen binary on PATH so the binary check passes.
    local bin; bin="$(mktemp -d)"; printf '#!/bin/bash\n' > "$bin/qwen"; chmod +x "$bin/qwen"
    HOME="$home" QWEN_API_KEY="" PATH="$bin:$PATH" \
        bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh" 2>/dev/null | grep '^qwen:'
    rm -rf "$home" "$bin"
}

fleet_qwen_lines() {  # $1 = fixture creds file; $2 = shell env assignments
    local home bin; home="$(mktemp -d)"; bin="$(mktemp -d)"
    mkdir -p "$home/.qwen"
    cp "$1" "$home/.qwen/oauth_creds.json"
    printf '#!/bin/bash\nprintf "qwen stub\\n"\n' > "$bin/qwen"; chmod +x "$bin/qwen"
    HOME="$home" PATH="$bin:/usr/bin:/bin" OCTO_ALLOWED_PROVIDERS="qwen" bash -c '
        '"$2"'
        "'"$PROJECT_ROOT"'/scripts/helpers/build-fleet.sh" research standard "auth test"
    ' 2>/dev/null | grep '^qwen|' || true
    rm -rf "$home" "$bin"
}

test_preflight_expired_degraded() {
    test_case "check-providers.sh: expired qwen reports degraded (not available)"
    local line; line="$(preflight_qwen_line "$FIXTURE/past.json")"
    if [[ "$line" == "qwen:degraded" ]]; then test_pass
    else test_fail "expected qwen:degraded, got: $line"; fi
}
test_preflight_valid_available() {
    test_case "check-providers.sh: valid qwen reports available"
    local line; line="$(preflight_qwen_line "$FIXTURE/future.json")"
    if [[ "$line" == "qwen:available" ]]; then test_pass
    else test_fail "expected qwen:available, got: $line"; fi
}
test_fleet_excludes_expired_qwen() {
    test_case "build-fleet.sh: expired qwen is excluded from fleets"
    local lines
    lines="$(fleet_qwen_lines "$FIXTURE/past.json" 'export QWEN_API_KEY=""; unset OPENAI_API_KEY OPENAI_BASE_URL')"
    if [[ -z "$lines" ]]; then test_pass
    else test_fail "expected no qwen fleet entries, got: $lines"; fi
}
test_fleet_includes_openai_compat_qwen() {
    test_case "build-fleet.sh: Coding-Plan qwen is included in fleets"
    local lines
    lines="$(fleet_qwen_lines "$FIXTURE/past.json" 'export QWEN_API_KEY=""; export OPENAI_API_KEY="sk-test"; export OPENAI_BASE_URL="https://dashscope-intl.aliyuncs.com/compatible-mode/v1"')"
    if printf '%s\n' "$lines" | grep -c '^qwen|' >/dev/null; then test_pass
    else test_fail "expected qwen fleet entry, got: $lines"; fi
}

# ── 4. run_with_timeout SIGKILL escalation ───────────────────────────────────
# A process that traps & ignores SIGTERM must still die via the kill-after
# SIGKILL backstop. Cap=2s, kill-after=10s → must complete well under 20s and
# return a non-zero (timeout) exit code.
test_timeout_kills_term_ignorer() {
    test_case "run_with_timeout: SIGTERM-ignoring process is SIGKILLed"
    local stubborn="$FIXTURE/stubborn.sh"
    cat > "$stubborn" <<'EOF'
#!/bin/bash
trap '' TERM        # ignore SIGTERM — only SIGKILL can stop us
sleep 600
EOF
    chmod +x "$stubborn"

    local start end dur ec
    start="$(date +%s)"
    set +e
    run_with_timeout 2 "$stubborn" >/dev/null 2>&1
    ec=$?
    set -e
    end="$(date +%s)"
    dur=$(( end - start ))

    if [[ "$ec" -ne 0 && "$dur" -lt 20 ]]; then
        test_pass
    else
        test_fail "stubborn process not killed promptly (exit=$ec, dur=${dur}s; expected non-zero exit, <20s)"
    fi
}

test_validator_past_invalid
test_validator_future_valid
test_validator_noexpiry_failclosed
test_validator_garbage_failclosed
test_validator_missing_failclosed
test_qwen_expired_is_oauth_expired
test_qwen_valid_is_oauth
test_qwen_without_validator_fails_closed
test_qwen_apikey_precedence
test_qwen_openai_compat_precedence
test_qwen_usable_rejects_expired
test_qwen_usable_accepts_openai_compat
test_preflight_expired_degraded
test_preflight_valid_available
test_fleet_excludes_expired_qwen
test_fleet_includes_openai_compat_qwen
test_timeout_kills_term_ignorer

test_summary
