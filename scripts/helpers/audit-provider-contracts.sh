#!/usr/bin/env bash
# Audit provider contracts that tend to drift as provider CLIs/plugins change.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

PASS=0
FAIL=0

pass() {
    PASS=$((PASS + 1))
    printf 'PASS %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n' "$1"
}

contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -Eq "$pattern" "$file" 2>/dev/null; then
        pass "$label"
    else
        fail "$label"
    fi
}

not_contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -Eq "$pattern" "$file" 2>/dev/null; then
        fail "$label"
    else
        pass "$label"
    fi
}

contains "${ROOT}/scripts/helpers/check-providers.sh" '^set -euo pipefail$' \
    "check-providers uses strict mode"
contains "${ROOT}/scripts/helpers/check-providers.sh" 'name:degraded' \
    "provider status contract documents degraded"
contains "${ROOT}/scripts/helpers/check-providers.sh" 'qwen_state="degraded"' \
    "qwen binary-with-bad-auth fails closed in provider banner"
contains "${ROOT}/scripts/helpers/check-providers.sh" 'octo_event_emit "provider\.status"' \
    "provider banner can emit opt-in lifecycle events"

contains "${ROOT}/scripts/lib/qwen.sh" 'oauth-unvalidated' \
    "qwen OAuth without validator is a non-dispatchable state"
contains "${ROOT}/scripts/lib/providers.sh" 'oauth-unvalidated' \
    "provider detection preserves unvalidated qwen OAuth state"
contains "${ROOT}/scripts/lib/providers.sh" 'configure Coding-Plan' \
    "qwen setup guidance points at API key or Coding-Plan auth"
not_contains "${ROOT}/scripts/lib/providers.sh" 'Qwen:.*free tier' \
    "qwen setup guidance does not advertise the retired free tier"

contains "${ROOT}/scripts/lib/provider-versions.sh" 'OCTO_GEMINI_MIN_VERSION="\$\{OCTO_GEMINI_MIN_VERSION:-0\.45\.0\}"' \
    "gemini version floor is current and env-overridable"
contains "${ROOT}/scripts/lib/provider-versions.sh" 'OCTO_QWEN_MIN_VERSION="\$\{OCTO_QWEN_MIN_VERSION:-0\.14\.0\}"' \
    "qwen version floor is current and env-overridable"
not_contains "${ROOT}/scripts/lib/auth.sh" 'grep -oE.*expiry_date' \
    "OAuth expiry parsing avoids brittle regex fallback"

if [[ -f "${ROOT}/scripts/lib/events.sh" ]] && bash -n "${ROOT}/scripts/lib/events.sh"; then
    pass "event stream helper exists and has valid syntax"
else
    fail "event stream helper exists and has valid syntax"
fi

if bash -n "${ROOT}/scripts/helpers/check-providers.sh" "${ROOT}/scripts/helpers/audit-provider-contracts.sh"; then
    pass "provider helper scripts have valid shell syntax"
else
    fail "provider helper scripts have valid shell syntax"
fi

printf 'SUMMARY pass=%s fail=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
