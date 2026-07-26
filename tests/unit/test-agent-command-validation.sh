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


test_case "validate_agent_command allows openai-compatible helper path"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --model minimax/minimax-m3 --cwd /tmp/test"; then
    test_pass
else
    test_fail "expected openai-compatible helper path to be accepted"
fi


test_case "validate_agent_command allows configured OpenAI-compatible runtime args"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https://api.pioneer.ai/v1 --api-key-env PIONEER_API_KEY --model deepseek-ai/DeepSeek-V4-Pro --cwd /tmp/test"; then
    test_pass
else
    test_fail "expected configured OpenAI-compatible runtime args to be accepted"
fi

test_case "validate_agent_command rejects non-http OpenAI-compatible base URL"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url file:///tmp/api --api-key-env PIONEER_API_KEY --model deepseek-ai/DeepSeek-V4-Pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected non-http base URL to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects http URL without host"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url http:// --api-key-env PIONEER_API_KEY --model deepseek-ai/DeepSeek-V4-Pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected http URL without host to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects https URL without host"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https:// --api-key-env PIONEER_API_KEY --model deepseek-ai/DeepSeek-V4-Pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected https URL without host to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects unsafe OpenAI-compatible base URL"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https://api.example/v1;touch --api-key-env PIONEER_API_KEY --model deepseek-ai/DeepSeek-V4-Pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected unsafe base URL to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects invalid credential env name"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https://api.pioneer.ai/v1 --api-key-env BAD-NAME --model deepseek-ai/DeepSeek-V4-Pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected invalid credential env name to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects duplicate OpenAI-compatible runtime args"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https://api.pioneer.ai/v1 --base-url https://api.example/v1 --api-key-env PIONEER_API_KEY --model deepseek-ai/DeepSeek-V4-Pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected duplicate runtime args to be rejected"
else
    test_pass
fi

test_case "validate_agent_command rejects duplicate credential env args"
if validate_agent_command "$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py --provider generic --base-url https://api.pioneer.ai/v1 --api-key-env PIONEER_API_KEY --api-key-env OPENAI_API_KEY --model deepseek-ai/DeepSeek-V4-Pro --cwd /tmp/test" >/dev/null 2>&1; then
    test_fail "expected duplicate credential env args to be rejected"
else
    test_pass
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
