#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

log() { :; }
source "$PROJECT_ROOT/scripts/lib/utils.sh"

test_suite "Agent Command Validation"

test_case "validate_agent_command allows vibe-exec shim path"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/vibe-exec.sh --output text"; then
    test_pass
else
    test_fail "expected vibe-exec shim path to be accepted"
fi

test_case "validate_agent_command allows vibe-exec shim path without args"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/vibe-exec.sh"; then
    test_pass
else
    test_fail "expected bare vibe-exec shim path to be accepted"
fi

test_case "validate_agent_command rejects embedded vibe-exec shim path"
if validate_agent_command "echo $PROJECT_ROOT/scripts/helpers/vibe-exec.sh --output text" >/dev/null 2>&1; then
    test_fail "expected embedded vibe-exec shim path to be rejected"
else
    test_pass
fi

test_case "validate_agent_command allows agy-exec shim path"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/agy-exec.sh"; then
    test_pass
else
    test_fail "expected agy-exec shim path to be accepted"
fi

test_case "validate_agent_command rejects embedded agy-exec shim path"
if validate_agent_command "echo $PROJECT_ROOT/scripts/helpers/agy-exec.sh" >/dev/null 2>&1; then
    test_fail "expected embedded agy-exec shim path to be rejected"
else
    test_pass
fi

test_case "validate_agent_command allows copilot-exec shim path"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/copilot-exec.sh"; then
    test_pass
else
    test_fail "expected copilot-exec shim path to be accepted"
fi

test_case "validate_agent_command allows copilot-exec shim path with model env prefix"
if validate_agent_command "env OCTOPUS_COPILOT_MODEL=auto $PROJECT_ROOT/scripts/helpers/copilot-exec.sh"; then
    test_pass
else
    test_fail "expected env-prefixed copilot-exec shim path to be accepted"
fi

test_case "validate_agent_command rejects embedded copilot-exec shim path"
if validate_agent_command "echo $PROJECT_ROOT/scripts/helpers/copilot-exec.sh" >/dev/null 2>&1; then
    test_fail "expected embedded copilot-exec shim path to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects env-prefixed copilot command with wrong executable"
if validate_agent_command "env OCTOPUS_COPILOT_MODEL=auto echo pwned" >/dev/null 2>&1; then
    test_fail "expected env-prefixed command without the copilot-exec shim to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects copilot command with wrong executable trailed by the shim path"
if validate_agent_command "env OCTOPUS_COPILOT_MODEL=auto echo pwned $PROJECT_ROOT/scripts/helpers/copilot-exec.sh" >/dev/null 2>&1; then
    test_fail "expected wrong-executable-then-shim-path to be rejected"
else
    test_pass
fi

# get_agent_command returns the commandcode shim WITH arguments (model and
# permission mode), so the shim must be allowed via the executable-token check
# rather than an exact-string case arm.
test_case "validate_agent_command allows commandcode-exec shim path with args"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/commandcode-exec.sh deepseek/deepseek-v4-pro plan"; then
    test_pass
else
    test_fail "expected commandcode-exec shim path to be accepted"
fi

test_case "validate_agent_command rejects embedded commandcode-exec shim path"
if validate_agent_command "echo $PROJECT_ROOT/scripts/helpers/commandcode-exec.sh" >/dev/null 2>&1; then
    test_fail "expected embedded commandcode-exec shim path to be rejected"
else
    test_pass
fi


test_case "validate_agent_command allows openai-compatible helper path"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --cwd /tmp/test"; then
    test_pass
else
    test_fail "expected openai-compatible helper path to be accepted"
fi

test_case "validate_agent_command rejects non-project openai-compatible helper path"
if validate_agent_command "/tmp/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected non-project openai-compatible helper path to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects openai-compatible helper model metacharacters"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model bad;touch --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected openai-compatible helper model metacharacters to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects openai-compatible helper absolute model path"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model /tmp/model --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected openai-compatible helper absolute model path to be rejected"
else
    test_pass
fi

test_case "validate_agent_command allows OrcaRouter dispatch functions"
if validate_agent_command "orcarouter_execute" &&
        validate_agent_command "orcarouter_execute_model anthropic/claude-sonnet-4.5"; then
    test_pass
else
    test_fail "expected OrcaRouter dispatch functions to be accepted"
fi

test_case "validate_agent_command rejects OrcaRouter lookalike function names"
if validate_agent_command "orcarouter_execute_attacker payload" >/dev/null 2>&1; then
    test_fail "expected an OrcaRouter lookalike function name to be rejected"
else
    test_pass
fi

test_case "validate_agent_command allows reasoning flags before cwd"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --reasoning-effort medium --reasoning-policy best_effort --cwd /tmp/test"; then
    test_pass
else
    test_fail "expected dispatch argument order to be accepted"
fi

test_case "validate_agent_command allows openai-compatible reasoning flags"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --cwd /tmp/test --reasoning-effort medium --reasoning-policy best_effort"; then
    test_pass
else
    test_fail "expected allowlisted reasoning flags to be accepted"
fi

test_case "validate_agent_command allows no-tools review policy"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --tool-policy none --cwd /tmp/test"; then
    test_pass
else
    test_fail "expected allowlisted no-tools policy to be accepted"
fi

test_case "validate_agent_command rejects invalid tool policy"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --cwd /tmp/test --tool-policy unrestricted" >/dev/null 2>&1; then
    test_fail "expected invalid tool policy to be rejected"
else
    test_pass
fi

test_case "validate_agent_command allows env-configured base-url and api-key-env"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https://ark.cn-beijing.volces.com/api/coding/v3 --api-key-env VOLCANO_API_KEY --model deepseek-v4-pro --cwd /tmp/test"; then
    test_pass
else
    test_fail "expected dispatch.sh's env-configured base-url/api-key-env command to be accepted"
fi

test_case "validate_agent_command rejects unsafe base-url"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https://example.com/\$(whoami) --api-key-env MY_KEY --model deepseek-v4-pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected unsafe base-url to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects base-url without a host"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https:/// --api-key-env MY_KEY --model deepseek-v4-pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected hostless base-url to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects unsafe api-key-env"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https://example.com/v1 --api-key-env MY-KEY --model deepseek-v4-pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected unsafe api-key-env to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects invalid reasoning effort"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --cwd /tmp/test --reasoning-effort extreme" >/dev/null 2>&1; then
    test_fail "expected invalid reasoning effort to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects invalid reasoning policy"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --cwd /tmp/test --reasoning-policy permissive" >/dev/null 2>&1; then
    test_fail "expected invalid reasoning policy to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects openai-compatible helper extra args"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --cwd /tmp/test --unexpected flag" >/dev/null 2>&1; then
    test_fail "expected openai-compatible helper extra args to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects openai-compatible helper backslash model"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model bad\ --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected openai-compatible helper backslash model to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects openai-compatible helper in-token backslash model"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model bad\\model --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected openai-compatible helper in-token backslash model to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects embedded openai-compatible helper path"
if validate_agent_command "echo $PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic" >/dev/null 2>&1; then
    test_fail "expected embedded openai-compatible helper path to be rejected"
else
    test_pass
fi

# get_agent_command emits these two shapes for grok (v9.10.0) and claude-sdk
# (v9.50.0) — a bare shim path when no model override is set, or an
# `env OCTOPUS_*_MODEL=<model> <shim>` prefix when one is. Neither shape was in
# validate_agent_command's allowlist, so every grok/claude-sdk dispatch aborted
# with "Invalid agent command" before the CLI ever ran — the same failure mode
# as #697 (copilot-exec.sh) and #705 (agy-exec.sh), predicted by #750.
test_case "validate_agent_command allows grok-exec shim path"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/grok-exec.sh"; then
    test_pass
else
    test_fail "expected bare grok-exec shim path to be accepted"
fi

test_case "validate_agent_command allows grok-exec shim path with model env prefix"
if validate_agent_command "env OCTOPUS_GROK_MODEL=grok-4-fast $PROJECT_ROOT/scripts/helpers/grok-exec.sh"; then
    test_pass
else
    test_fail "expected env-prefixed grok-exec shim path to be accepted"
fi

test_case "validate_agent_command rejects embedded grok-exec shim path"
if validate_agent_command "echo $PROJECT_ROOT/scripts/helpers/grok-exec.sh" >/dev/null 2>&1; then
    test_fail "expected embedded grok-exec shim path to be rejected"
else
    test_pass
fi

# CodeRabbit (#769): the OCTOPUS_GROK_MODEL/OCTOPUS_CLAUDE_SDK_MODEL env-prefix
# arms must bind to their matching shim, or any executable can ride along
# after the prefix — e.g. `env OCTOPUS_GROK_MODEL=x echo pwned` would pass.
test_case "validate_agent_command rejects env-prefixed grok command with wrong executable"
if validate_agent_command "env OCTOPUS_GROK_MODEL=x echo pwned" >/dev/null 2>&1; then
    test_fail "expected env-prefixed command without the grok-exec shim to be rejected"
else
    test_pass
fi

# CodeRabbit (#769, round 2): binding on prefix+suffix alone still let a wrong
# executable ride along as long as the shim path trailed it somewhere in the
# string — the shim must be the *next token*, not merely present later.
test_case "validate_agent_command rejects grok command with wrong executable trailed by the shim path"
if validate_agent_command "env OCTOPUS_GROK_MODEL=x echo pwned $PROJECT_ROOT/scripts/helpers/grok-exec.sh" >/dev/null 2>&1; then
    test_fail "expected wrong-executable-then-shim-path to be rejected"
else
    test_pass
fi

test_case "validate_agent_command allows claude-sdk-exec shim path"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh"; then
    test_pass
else
    test_fail "expected bare claude-sdk-exec shim path to be accepted"
fi

test_case "validate_agent_command allows claude-sdk-exec shim path with model env prefix"
if validate_agent_command "env OCTOPUS_CLAUDE_SDK_MODEL=claude-opus-5 $PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh"; then
    test_pass
else
    test_fail "expected env-prefixed claude-sdk-exec shim path to be accepted"
fi

test_case "validate_agent_command rejects embedded claude-sdk-exec shim path"
if validate_agent_command "echo $PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh" >/dev/null 2>&1; then
    test_fail "expected embedded claude-sdk-exec shim path to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects env-prefixed claude-sdk command with wrong executable"
if validate_agent_command "env OCTOPUS_CLAUDE_SDK_MODEL=x echo pwned" >/dev/null 2>&1; then
    test_fail "expected env-prefixed command without the claude-sdk-exec shim to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects claude-sdk command with wrong executable trailed by the shim path"
if validate_agent_command "env OCTOPUS_CLAUDE_SDK_MODEL=x echo pwned $PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh" >/dev/null 2>&1; then
    test_fail "expected wrong-executable-then-shim-path to be rejected"
else
    test_pass
fi

# End-to-end: exercise the real get_agent_command output, not just hand-written
# literals, so a future change to the grok/claude-sdk command shape is caught
# here instead of shipping silently broken (the actual #750 failure mode).
test_case "get_agent_command dispatch commands for grok and claude-sdk pass validate_agent_command"
(
    FIXTURE_HOME="$TEST_TMP_DIR/agent-command-validation-home"
    mkdir -p "$FIXTURE_HOME/.claude-octopus/config"
    export PLUGIN_DIR="$PROJECT_ROOT" OCTOPUS_PLATFORM=Linux HOME="$FIXTURE_HOME"
    export OCTOPUS_GROK_MODEL=grok-4-fast OCTOPUS_CLAUDE_SDK_MODEL=claude-opus-5
    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/validation.sh"
    source "$PROJECT_ROOT/scripts/lib/model-cache-path.sh"
    source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
    source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
    grok_cmd="$(get_agent_command grok tangle implementer)" || exit 1
    sdk_cmd="$(get_agent_command claude-sdk tangle implementer)" || exit 1
    validate_agent_command "$grok_cmd" >/dev/null 2>&1 || exit 1
    validate_agent_command "$sdk_cmd" >/dev/null 2>&1 || exit 1
)
if [[ $? -eq 0 ]]; then
    test_pass
else
    test_fail "get_agent_command output for grok/claude-sdk rejected by validate_agent_command"
fi

test_case "generated standard Claude command passes validate_agent_command"
if (
    FIXTURE_HOME="$TEST_TMP_DIR/claude-command-validation-home"
    mkdir -p "$FIXTURE_HOME/.claude-octopus/config"
    export PLUGIN_DIR="$PROJECT_ROOT" OCTOPUS_PLATFORM=Linux HOME="$FIXTURE_HOME"
    export _BARE_OPT="" SUPPORTS_OPUS_5=true SUPPORTS_OPUS_4_8=true
    export SUPPORTS_OPUS_4_7=true SUPPORTS_SDK_MODEL_CAPS=true
    export SUPPORTS_EFFORT_COMMAND=true SUPPORTS_XHIGH_EFFORT=false
    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/validation.sh"
    source "$PROJECT_ROOT/scripts/lib/model-cache-path.sh"
    source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
    source "$PROJECT_ROOT/scripts/lib/agents.sh"
    source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
    claude_cmd="$(get_agent_command claude-opus discover reviewer 128)" || exit 1
    validate_agent_command "$claude_cmd" >/dev/null 2>&1 || exit 1
); then
    test_pass
else
    test_fail "generated standard Claude command was rejected by validate_agent_command"
fi

test_case "validate_agent_command rejects Claude command separators"
if validate_agent_command "claude --print --model claude-opus-5; touch /tmp/pwned" >/dev/null 2>&1; then
    test_fail "expected a command separator to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects Claude command substitutions"
if validate_agent_command 'claude --print --model $(touch /tmp/pwned)' >/dev/null 2>&1; then
    test_fail "expected command substitution to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects unapproved Claude flags"
if validate_agent_command "claude --print --model claude-opus-5 --dangerously-skip-permissions" >/dev/null 2>&1; then
    test_fail "expected an unapproved Claude flag to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects extra Claude executables"
if validate_agent_command "claude --print --model claude-opus-5 echo pwned" >/dev/null 2>&1; then
    test_fail "expected an extra executable token to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects arbitrary Claude env assignments"
if validate_agent_command "env ATTACKER_VALUE=x claude --print --model claude-opus-5" >/dev/null 2>&1; then
    test_fail "expected an arbitrary env assignment to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects unsafe command"
if validate_agent_command "rm -rf /" >/dev/null 2>&1; then
    test_fail "expected unsafe command to be rejected"
else
    test_pass
fi

test_summary
