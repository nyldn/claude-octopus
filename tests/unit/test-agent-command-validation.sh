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

test_case "validate_agent_command allows constrained Claude effort prefix"
if validate_agent_command "env CLAUDE_CODE_EFFORT_LEVEL=high claude --print --model claude-fable-5 --allowed-tools Read,Glob,Grep"; then
    test_pass
else
    test_fail "expected allowlisted Claude effort prefix to be accepted"
fi

test_case "validate_agent_command allows constrained Fable model and effort prefixes"
if validate_agent_command "env OCTOPUS_OPUS_MODEL=claude-fable-5 CLAUDE_CODE_EFFORT_LEVEL=high claude --print --model claude-fable-5 --effort high --allowed-tools Read,Glob,Grep"; then
    test_pass
else
    test_fail "expected the dispatched Fable model/effort prefix to be accepted"
fi

test_case "validate_agent_command rejects unapproved Claude model prefix"
if validate_agent_command "env OCTOPUS_OPUS_MODEL=claude-fast CLAUDE_CODE_EFFORT_LEVEL=high claude --print --model claude-fast" >/dev/null 2>&1; then
    test_fail "expected an unapproved Claude model prefix to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects invalid Claude effort value"
if validate_agent_command "env CLAUDE_CODE_EFFORT_LEVEL=extreme claude --print --model claude-fable-5" >/dev/null 2>&1; then
    test_fail "expected invalid Claude effort value to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects extra environment assignments"
if validate_agent_command "env CLAUDE_CODE_EFFORT_LEVEL=high UNSAFE=1 claude --print --model claude-fable-5" >/dev/null 2>&1; then
    test_fail "expected extra environment assignment to be rejected"
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

test_case "validate_agent_command rejects unsafe command"
if validate_agent_command "rm -rf /" >/dev/null 2>&1; then
    test_fail "expected unsafe command to be rejected"
else
    test_pass
fi

test_summary
