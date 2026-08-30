#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Shared provider readiness contract"

export HOME="$TEST_TMP_DIR/home"
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
export OCTOPUS_STATE_DIR="$TEST_TMP_DIR/state"
mkdir -p "$HOME" "$WORKSPACE_DIR" "$OCTOPUS_STATE_DIR"

log() { :; }
source "$PROJECT_ROOT/scripts/lib/preflight.sh"

test_case "readiness evaluator entry points are defined"
if declare -f octo_provider_readiness_result >/dev/null 2>&1 &&
   declare -f octo_provider_readiness_all >/dev/null 2>&1 &&
   declare -f octo_provider_readiness_legacy >/dev/null 2>&1; then
    test_pass
else
    test_fail "shared readiness evaluator functions are missing"
fi

test_case "registry metadata is consulted by the evaluator"
if grep -q 'octo_provider_auth_mode' "$PROJECT_ROOT/scripts/lib/preflight.sh" &&
   grep -q 'octo_provider_health_handler' "$PROJECT_ROOT/scripts/lib/preflight.sh" &&
   grep -q 'octo_provider_detect_handler' "$PROJECT_ROOT/scripts/lib/preflight.sh"; then
    test_pass
else
    test_fail "readiness evaluator bypasses Provider Registry 2.0 metadata"
fi

fake_bin="$TEST_TMP_DIR/bin"
network_sentinel="$TEST_TMP_DIR/network-called"
mkdir -p "$fake_bin" "$HOME/.codex"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/codex"
printf '#!/usr/bin/env bash\nprintf called > "%s"\nexit 99\n' "$network_sentinel" > "$fake_bin/curl"
chmod +x "$fake_bin/codex" "$fake_bin/curl"
printf '{}\n' > "$HOME/.codex/auth.json"

test_case "static readiness is structured and performs no network call"
static_result=""
if declare -f octo_provider_readiness_result >/dev/null 2>&1; then
    static_result="$(PATH="$fake_bin:/usr/bin:/bin" octo_provider_readiness_result codex static)"
fi
if [[ -n "$static_result" ]] &&
   jq -e 'select(.provider == "codex" and .status == "available" and
      .reason_code == "ready" and .check_kind == "static" and
      (.checked_at | type == "string") and (.duration_ms | type == "number") and
      (.remediation | type == "string"))' <<< "$static_result" >/dev/null &&
   [[ ! -e "$network_sentinel" ]]; then
    test_pass
else
    test_fail "static result was malformed, incorrect, or performed a network call: $static_result"
fi

test_case "quota-dead state centrally degrades an otherwise ready provider"
quota_result=""
if declare -f octo_provider_readiness_result >/dev/null 2>&1; then
    octo_quota_is_dead() { [[ "$1" == "codex" ]]; }
    quota_result="$(PATH="$fake_bin:/usr/bin:/bin" octo_provider_readiness_result codex static)"
    unset -f octo_quota_is_dead
fi
if jq -e 'select(.provider == "codex" and .status == "degraded" and .reason_code == "quota")' \
    <<< "${quota_result:-'{}'}" >/dev/null 2>&1; then
    test_pass
else
    test_fail "quota-dead provider did not degrade centrally: $quota_result"
fi

test_case "live readiness explicitly runs a bounded registry health handler"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/ollama"
printf '#!/usr/bin/env bash\nprintf called > "%s"\nexit 0\n' "$network_sentinel" > "$fake_bin/curl"
chmod +x "$fake_bin/ollama" "$fake_bin/curl"
rm -f "$network_sentinel"
live_result="$(PATH="$fake_bin:/usr/bin:/bin" OCTOPUS_PROVIDER_LIVE_TIMEOUT=2 \
    octo_provider_readiness_result ollama live 2>/dev/null)"
if [[ -e "$network_sentinel" ]] &&
   jq -e 'select(.provider == "ollama" and .status == "available" and
      .reason_code == "ready" and .check_kind == "live")' <<<"$live_result" >/dev/null; then
    test_pass
else
    test_fail "explicit live readiness did not run or normalize the registry health result: $live_result"
fi

test_case "readiness output never contains credential values"
secret_value="task4-secret-value"
secret_output=""
if declare -f octo_provider_readiness_result >/dev/null 2>&1; then
    secret_output="$(PERPLEXITY_API_KEY="$secret_value" octo_provider_readiness_result perplexity static)"
fi
if [[ -n "$secret_output" ]] && [[ "$secret_output" != *"$secret_value"* ]] &&
   jq -e 'select(.provider == "perplexity" and .status == "available")' <<< "$secret_output" >/dev/null; then
    test_pass
else
    test_fail "readiness output was missing or leaked a credential"
fi

test_case "documented checker renders the shared readiness evaluator"
if grep -q 'octo_provider_readiness_legacy' "$PROJECT_ROOT/scripts/helpers/check-providers.sh"; then
    test_pass
else
    test_fail "check-providers.sh still owns independent provider detection"
fi

test_case "preflight JSON exposes shared result objects"
preflight_json="$(PATH="$fake_bin:/usr/bin:/bin" HOME="$HOME" \
    bash "$PROJECT_ROOT/scripts/helpers/preflight.sh" --json 2>/dev/null || true)"
if jq -e '.results | length > 0 and all(.[];
      has("provider") and has("status") and has("reason_code") and
      has("check_kind") and has("checked_at") and has("duration_ms") and
      has("remediation"))' <<< "$preflight_json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "preflight JSON does not consume the shared readiness schema"
fi

test_case "plan renders its retained readiness snapshot without raw probes"
plan_command="$PROJECT_ROOT/commands/plan.md"
if grep -Fq 'PROVIDER_STATUS' "$plan_command" &&
   grep -Fq 'OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"' "$plan_command" &&
   grep -Fq 'if [[ ! -x "$provider_helper" ]]' "$plan_command" &&
   ! grep -Fq 'command -v' "$plan_command" &&
   ! grep -Fq '11434/api/tags' "$plan_command"; then
    test_pass
else
    test_fail "plan.md must render PROVIDER_STATUS without binary, env, or Ollama probes"
fi

test_case "multi and extract accept every ready non-Claude provider dynamically"
provider_commands=("$PROJECT_ROOT/commands/multi.md" "$PROJECT_ROOT/commands/extract.md")
dynamic_commands=0
for provider_command in "${provider_commands[@]}"; do
    if grep -Fq 'scripts/helpers/check-providers.sh' "$provider_command" &&
       grep -Fq 'OCTOPUS_PREFLIGHT_PROBE=1' "$provider_command" &&
       grep -Fqi 'shared live readiness' "$provider_command" &&
       grep -Fq '$1 !~ /^claude($|-)/ && $2 == "available"' "$provider_command" &&
       ! grep -Fq 'codex|agy|copilot|qwen|opencode|ollama' "$provider_command"; then
        dynamic_commands=$((dynamic_commands + 1))
    fi
done
if [[ "$dynamic_commands" -eq 2 ]]; then
    test_pass
else
    test_fail "multi.md and extract.md must use live shared readiness without a provider allowlist"
fi

test_case "legacy readiness output works without jq when Python is available"
no_jq_bin="$TEST_TMP_DIR/no-jq-bin"
mkdir -p "$no_jq_bin"
ln -s "$(command -v python3)" "$no_jq_bin/python3"
octo_provider_readiness_all() {
    printf '%s\n' '{"provider":"codex","status":"available","reason_code":"ready","check_kind":"static","checked_at":"now","duration_ms":0,"remediation":""}'
}
unset -f octo_event_emit 2>/dev/null || true
legacy_no_jq="$(PATH="$no_jq_bin" octo_provider_readiness_legacy static || true)"
if [[ "$legacy_no_jq" == $'PROVIDER_CHECK_START\ncodex:available\nPROVIDER_CHECK_END' ]]; then
    test_pass
else
    test_fail "jq-less legacy output was truncated or malformed: $legacy_no_jq"
fi

test_case "detect-providers cache works without jq when Python is available"
for command_name in date mkdir tee tr; do
    ln -s "$(command -v "$command_name")" "$no_jq_bin/$command_name"
done
check_claude_version() {
    printf '%s\n' 'CLAUDE_CODE_VERSION=2.1.219' 'CLAUDE_CODE_STATUS=ok' 'CLAUDE_CODE_MINIMUM=2.1.14'
}
no_jq_workspace="$TEST_TMP_DIR/no-jq-workspace"
no_jq_detect="$(PATH="$no_jq_bin" WORKSPACE_DIR="$no_jq_workspace" cmd_detect_providers || true)"
if grep -q '^CODEX_STATUS=ok$' <<<"$no_jq_detect" &&
   grep -q '^CLAUDE_CODE_STATUS=ok$' "$no_jq_workspace/.provider-cache" 2>/dev/null; then
    test_pass
else
    test_fail "jq-less provider cache was not complete: $no_jq_detect"
fi

test_case "parallel-agents skill documents the current cache contract"
parallel_skill="$PROJECT_ROOT/skills/skill-parallel-agents/SKILL.md"
if grep -q 'CLAUDE_CODE_MINIMUM=2.1.14' "$parallel_skill" &&
   grep -q 'CODEX_STATUS=ok' "$parallel_skill" &&
   grep -q 'AGY_STATUS=unauthenticated' "$parallel_skill" &&
   ! grep -q 'CODEX_AUTH=' "$parallel_skill" &&
   ! grep -q 'PERPLEXITY_AUTH=' "$parallel_skill"; then
    test_pass
else
    test_fail "parallel-agents still documents removed provider-cache keys"
fi

test_summary
