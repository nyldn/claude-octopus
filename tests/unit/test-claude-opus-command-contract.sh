#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Claude Opus command contract"

export HOME="$TEST_TMP_DIR/home"
export PLUGIN_DIR="$PROJECT_ROOT"
export OCTOPUS_PLATFORM=Linux
export OCTOPUS_DISPATCH_PREVIEW=true
export _BARE_OPT=""
mkdir -p "$HOME/.claude-octopus/config"

log() { :; }
source "$PROJECT_ROOT/scripts/lib/utils.sh"
source "$PROJECT_ROOT/scripts/lib/validation.sh"
source "$PROJECT_ROOT/scripts/lib/model-cache-path.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
source "$PROJECT_ROOT/scripts/lib/agents.sh"
source "$PROJECT_ROOT/scripts/lib/fable5.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

reset_command_env() {
    unset OCTOPUS_OPUS_MODEL OCTOPUS_EFFORT_OVERRIDE OCTOPUS_OPUS_MODE
    unset OCTOPUS_FABLE5_FALLBACK_MODEL OCTOPUS_CLAUDE_ALLOWED_MODELS
    export SUPPORTS_OPUS_5=true
    export SUPPORTS_OPUS_4_8=true
    export SUPPORTS_OPUS_4_7=true
    export SUPPORTS_SDK_MODEL_CAPS=true
    export SUPPORTS_EFFORT_COMMAND=true
    export SUPPORTS_EFFORT_CLI_FLAG=true
    export SUPPORTS_XHIGH_EFFORT=false
}

token_count() {
    local command="$1" wanted="$2" token count=0
    local -a tokens
    read -ra tokens <<< "$command"
    for token in "${tokens[@]}"; do
        [[ "$token" == "$wanted" ]] && count=$((count + 1))
    done
    printf '%s\n' "$count"
}

test_case "standard Opus uses supported effort flag and passes validation"
reset_command_env
standard_cmd="$(get_agent_command claude-opus discover reviewer 128)"
if [[ "$standard_cmd" == "claude --print --model claude-opus-5 --effort high "* ]] &&
   [[ "$standard_cmd" != env\ * ]] &&
   [[ "$standard_cmd" != *" --fast"* ]] &&
   validate_agent_command "$standard_cmd"; then
    test_pass
else
    test_fail "unsupported or rejected standard command: $standard_cmd"
fi

test_case "explicit Fable pin discards legacy fast modifier"
reset_command_env
export OCTOPUS_OPUS_MODEL=claude-fable-5
fable_cmd="$(get_agent_command claude-opus-fast ink architect 128)"
if [[ "$fable_cmd" == *"--model claude-fable-5"* ]] &&
   [[ "$fable_cmd" == *"--effort high"* ]] &&
   [[ "$fable_cmd" != *"--fast"* ]] &&
   validate_agent_command "$fable_cmd"; then
    test_pass
else
    test_fail "explicit Fable pin did not use validated standard dispatch: $fable_cmd"
fi

test_case "security role reroutes a legacy-fast Fable pin without --fast"
reset_command_env
export OCTOPUS_OPUS_MODEL=claude-fable-5
security_cmd="$(get_agent_command claude-opus-fast ink security-auditor 128)"
if [[ "$security_cmd" == *"--model claude-opus-5"* ]] &&
   [[ "$security_cmd" != *"--model claude-fable-5"* ]] &&
   [[ "$security_cmd" != *"--fast"* ]] &&
   validate_agent_command "$security_cmd"; then
    test_pass
else
    test_fail "security reroute did not preserve the standard command contract: $security_cmd"
fi

test_case "serialized Claude command has one executable model and print flag"
reset_command_env
shape_cmd="$(get_agent_command claude-opus develop implementer 128)"
if [[ "${shape_cmd%% *}" == "claude" ]] &&
   [[ "$(token_count "$shape_cmd" claude)" -eq 1 ]] &&
   [[ "$(token_count "$shape_cmd" --model)" -eq 1 ]] &&
   [[ "$(token_count "$shape_cmd" --print)" -eq 1 ]] &&
   [[ "$(token_count "$shape_cmd" --effort)" -eq 1 ]] &&
   [[ "$(token_count "$shape_cmd" --fast)" -eq 0 ]] &&
   validate_agent_command "$shape_cmd"; then
    test_pass
else
    test_fail "Claude argv shape is ambiguous: $shape_cmd"
fi

test_case "version-only effort support does not emit an unproven CLI flag"
reset_command_env
export SUPPORTS_EFFORT_CLI_FLAG=false
version_only_cmd="$(get_agent_command claude-opus discover reviewer 128)"
if [[ "$version_only_cmd" != *"--effort"* ]] && validate_agent_command "$version_only_cmd"; then
    test_pass
else
    test_fail "version-only support emitted an unproven effort argv flag: $version_only_cmd"
fi

test_case "xhigh clamps when the configured CLI lacks xhigh support"
reset_command_env
export OCTOPUS_EFFORT_OVERRIDE=xhigh SUPPORTS_XHIGH_EFFORT=false
xhigh_cmd="$(get_agent_command claude-opus develop reviewer 128)"
if [[ "$xhigh_cmd" == *"--effort high"* ]] && [[ "$xhigh_cmd" != *"--effort xhigh"* ]]; then
    test_pass
else
    test_fail "unsupported xhigh was not clamped: $xhigh_cmd"
fi

test_case "stub Claude receives only the validated argv contract"
reset_command_env
stub_bin="$TEST_TMP_DIR/claude-bin"
capture="$TEST_TMP_DIR/claude-argv"
mkdir -p "$stub_bin"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    ': > "$CLAUDE_ARGV_CAPTURE"' \
    'for arg in "$@"; do printf "%s\\n" "$arg" >> "$CLAUDE_ARGV_CAPTURE"; done' \
    'printf "%s\\n" "contract fixture result"' > "$stub_bin/claude"
chmod +x "$stub_bin/claude"
export CLAUDE_ARGV_CAPTURE="$capture"
stub_cmd="$(get_agent_command claude-opus discover reviewer 128)"
if validate_agent_command "$stub_cmd"; then
    read -ra stub_argv <<< "$stub_cmd"
    PATH="$stub_bin:$PATH" "${stub_argv[@]}" >/dev/null
fi
if [[ -f "$capture" ]] &&
   [[ "$(grep -cx -- '--print' "$capture")" -eq 1 ]] &&
   [[ "$(grep -cx -- '--model' "$capture")" -eq 1 ]] &&
   [[ "$(grep -cx -- '--effort' "$capture")" -eq 1 ]] &&
   ! grep -qx -- '--fast' "$capture"; then
    test_pass
else
    test_fail "validated command did not reach the Claude stub with the expected argv: $stub_cmd"
fi

test_summary
