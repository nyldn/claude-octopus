#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"

test_suite "Provider registry consumer contracts"

test_case "health capability matches implemented health cases"
expected="codex commandcode claude claude-sdk agy perplexity openrouter orcarouter atlascloud cursor-agent grok qwen ollama copilot vibe"
actual="$(octo_provider_ids health)"
if [[ "$actual" == "$expected" ]]; then test_pass; else test_fail "health set drift: $actual"; fi

test_case "Council capability preserves current providers and adds commandcode"
expected="codex commandcode claude agy opencode openrouter orcarouter openai-compatible openai-tools qwen"
actual="$(octo_provider_ids council)"
if [[ "$actual" == "$expected" ]]; then test_pass; else test_fail "Council set drift: $actual"; fi

test_case "model-config capability unifies both former allowlists"
failed=false
for provider in codex commandcode claude claude-sdk agy perplexity opencode openrouter orcarouter atlascloud openai-compatible openai-tools openai-compatible-agent cursor-agent grok qwen ollama copilot vibe; do
    if ! octo_provider_has_capability "$provider" model-config; then test_fail "model-config missing $provider"; failed=true; break; fi
done
[[ "$failed" == true ]] || test_pass

test_case "every health provider has an explicit check_provider_health case"
body=$(sed -n '/^check_provider_health() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/providers.sh")
failed=false
for provider in $(octo_provider_ids health); do
    case "$provider" in agy) pattern='agy|antigravity)' ;; *) pattern="${provider})" ;; esac
    if ! grep -Fq "$pattern" <<< "$body"; then
        test_fail "health capability lacks implementation: $provider"
        failed=true
        break
    fi
done
[[ "$failed" == true ]] || test_pass

test_case "commandcode is exposed by provider detection"
if grep -q 'octo_provider_allowed commandcode' "$PROJECT_ROOT/scripts/lib/providers.sh" && grep -q 'result=.*commandcode:' "$PROJECT_ROOT/scripts/lib/providers.sh"; then test_pass; else test_fail "commandcode detection missing"; fi

test_case "public help reflects configurable Council default policy"
if grep -q 'octo_council_default_providers' "$PROJECT_ROOT/scripts/lib/usage-help.sh" &&    grep -q 'OCTOPUS_COUNCIL_DEFAULT_PROVIDERS' "$PROJECT_ROOT/scripts/lib/provider-policy.sh" &&    grep -q 'COMMAND_CODE_API_KEY' "$PROJECT_ROOT/scripts/lib/usage-help.sh"; then
    test_pass
else
    test_fail "Council help does not use shared configurable policy or expose Command Code auth"
fi

test_case "preflight exposes and caches authenticated and unauthenticated commandcode states"
preflight_fixture="$TEST_TMP_DIR/preflight-commandcode"
mkdir -p "$preflight_fixture"
commandcode_cache="$preflight_fixture/.provider-cache"
(
    WORKSPACE_DIR="$preflight_fixture"
    check_claude_version() {
        printf '%s\n' 'CLAUDE_CODE_VERSION=2.1.219' 'CLAUDE_CODE_STATUS=ok' 'CLAUDE_CODE_MINIMUM=2.1.14'
    }
    source "$PROJECT_ROOT/scripts/lib/preflight.sh"
    octo_provider_readiness_all() {
        printf '%s\n' '{"provider":"commandcode","status":"degraded","reason_code":"auth-missing","check_kind":"static","checked_at":"now","duration_ms":0,"remediation":"set key"}'
    }
    cmd_detect_providers >/dev/null
)
if grep -q '^COMMANDCODE_STATUS=unauthenticated$' "$commandcode_cache" &&
   grep -q '^COMMANDCODE_AUTH=none$' "$commandcode_cache" &&
   ! grep -q '_preflight_commandcode_auth_mode' "$PROJECT_ROOT/scripts/lib/preflight.sh"; then
    test_pass
else
    test_fail "preflight commandcode auth contract missing"
fi


test_case "every detect-capable provider has a detection path"
detect_body=$(sed -n '/^detect_providers() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/providers.sh")
failed=false
for provider in $(octo_provider_ids detect); do
    if ! grep -Fq "octo_provider_allowed $provider" <<< "$detect_body" && ! grep -Fq "${provider}:" <<< "$detect_body"; then
        test_fail "detect capability lacks implementation: $provider"
        failed=true
        break
    fi
done
[[ "$failed" == true ]] || test_pass

test_case "every dispatch-capable provider is represented by dispatch or helper routing"
failed=false
for provider in $(octo_provider_ids dispatch); do
    if ! grep -Rqi --exclude=provider-registry.sh "$provider" \
        "$PROJECT_ROOT/scripts/lib/dispatch.sh" \
        "$PROJECT_ROOT/scripts/lib/provider-routing.sh" \
        "$PROJECT_ROOT/scripts/helpers"; then
        test_fail "dispatch capability lacks implementation: $provider"
        failed=true
        break
    fi
done
[[ "$failed" == true ]] || test_pass

test_case "environment builder has a safe generic fallback"
env_body=$(sed -n '/^_octo_build_provider_env_impl() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/provider-routing.sh")
if grep -q 'Other providers: no isolation needed' <<< "$env_body" && grep -A2 'Other providers: no isolation needed' <<< "$env_body" | grep -q 'return 0'; then
    test_pass
else
    test_fail "generic provider environment fallback missing"
fi


test_case "detect capability matches the complete implemented detection inventory"
expected="codex commandcode claude claude-sdk agy perplexity opencode openrouter orcarouter atlascloud openai-compatible cursor-agent grok qwen ollama copilot vibe"
actual="$(octo_provider_ids detect)"
if [[ "$actual" == "$expected" ]]; then test_pass; else test_fail "detect set drift: $actual"; fi

test_case "canonical provider inventory is explicit and complete"
expected="codex commandcode claude claude-sdk agy perplexity opencode openrouter orcarouter atlascloud openai-compatible openai-tools openai-compatible-agent cursor-agent grok qwen ollama copilot vibe"
actual="$(octo_provider_ids)"
if [[ "$actual" == "$expected" ]]; then test_pass; else test_fail "canonical provider inventory drift: $actual"; fi

test_case "registry self-validation enforces baseline and documented omissions"
if octo_provider_validate_contracts; then test_pass; else test_fail "registry governance contract failed"; fi


test_case "Command Code detection requires authentication"
stub_dir=$(mktemp -d)
printf '#!/usr/bin/env bash\n[[ "$1" == status && "$2" == --json ]] && exit "${COMMAND_CODE_STATUS_RC:-1}"\nexit 1\n' > "$stub_dir/command-code"
chmod +x "$stub_dir/command-code"
set +e
unauth=$(env -u COMMAND_CODE_API_KEY "HOME=$stub_dir" "PATH=$stub_dir:$PATH" "OCTO_ALLOWED_PROVIDERS=commandcode" "COMMAND_CODE_STATUS_RC=1" bash -c 'log(){ :; }; source "'$PROJECT_ROOT'/scripts/lib/providers.sh"; detect_providers')
unauth_rc=$?
auth=$(env -u COMMAND_CODE_API_KEY "HOME=$stub_dir" "PATH=$stub_dir:$PATH" "OCTO_ALLOWED_PROVIDERS=commandcode" "COMMAND_CODE_STATUS_RC=0" bash -c 'log(){ :; }; source "'$PROJECT_ROOT'/scripts/lib/providers.sh"; detect_providers')
auth_rc=$?
api=$(env "HOME=$stub_dir" "PATH=$stub_dir:$PATH" "OCTO_ALLOWED_PROVIDERS=commandcode" "COMMAND_CODE_API_KEY=test" bash -c 'log(){ :; }; source "'$PROJECT_ROOT'/scripts/lib/providers.sh"; detect_providers')
api_rc=$?
set -e
rm -rf "$stub_dir"
if [[ "$unauth_rc" -ne 0 && "$unauth" != *"commandcode:"* && "$auth_rc" -eq 0 && "$auth" == *"commandcode:cli"* && "$api_rc" -eq 0 && "$api" == *"commandcode:api-key"* ]]; then test_pass; else test_fail "unexpected auth detection: unauth_rc=$unauth_rc unauth=$unauth auth_rc=$auth_rc auth=$auth api_rc=$api_rc api=$api"; fi

test_summary
