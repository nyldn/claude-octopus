#!/bin/bash
# tests/unit/test-ollama-provider.sh
# Tests Ollama local LLM provider configuration and integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Ollama Provider Configuration"

test_ollama_config_exists() {
    test_case "Provider config file exists at config/providers/ollama/CLAUDE.md"

    local config="$PROJECT_ROOT/config/providers/ollama/CLAUDE.md"

    if [[ -f "$config" ]]; then
        test_pass
    else
        test_fail "Config file not found: $config"
        return 1
    fi
}

test_ollama_detection_method() {
    test_case "Config mentions detection method (command -v ollama)"

    local config="$PROJECT_ROOT/config/providers/ollama/CLAUDE.md"

    if grep -q "command -v ollama" "$config"; then
        test_pass
    else
        test_fail "Detection method 'command -v ollama' not found in config"
        return 1
    fi
}

test_ollama_server_health() {
    test_case "Config mentions localhost:11434 for server health"

    local config="$PROJECT_ROOT/config/providers/ollama/CLAUDE.md"

    if grep -q "localhost:11434" "$config"; then
        test_pass
    else
        test_fail "Server health endpoint localhost:11434 not found in config"
        return 1
    fi
}

test_ollama_model_selection() {
    test_case "Config mentions model selection via ollama list"

    local config="$PROJECT_ROOT/config/providers/ollama/CLAUDE.md"

    if grep -q "ollama list" "$config"; then
        test_pass
    else
        test_fail "Model selection 'ollama list' not found in config"
        return 1
    fi
}

test_ollama_dispatch_pattern() {
    test_case "Config specifies dispatch pattern"

    local config="$PROJECT_ROOT/config/providers/ollama/CLAUDE.md"

    if grep -q 'ollama run <model>' "$config"; then
        test_pass
    else
        test_fail "Dispatch pattern 'ollama run <model>' not found in config"
        return 1
    fi
}

test_ollama_zero_cost() {
    test_case "Config mentions zero cost"

    local config="$PROJECT_ROOT/config/providers/ollama/CLAUDE.md"

    if grep -qi "zero" "$config" && grep -qi "no API keys" "$config"; then
        test_pass
    else
        test_fail "Zero cost / no API keys mention not found in config"
        return 1
    fi
}

test_ollama_model_preferences() {
    test_case "Config lists preferred models (llama3, codellama, mistral)"

    local config="$PROJECT_ROOT/config/providers/ollama/CLAUDE.md"

    if grep -q "llama3" "$config" && \
       grep -q "codellama" "$config" && \
       grep -q "mistral" "$config"; then
        test_pass
    else
        test_fail "One or more preferred models not listed in config"
        return 1
    fi
}

test_skill_doctor_mentions_ollama() {
    test_case "skill-doctor.md mentions Ollama"

    local doctor="$(resolve_claude_skill_path "skill-doctor")"

    if grep -qi "ollama" "$doctor"; then
        test_pass
    else
        test_fail "Ollama not mentioned in skill-doctor.md"
        return 1
    fi
}

test_ollama_limitations_documented() {
    test_case "Config documents limitations"

    local config="$PROJECT_ROOT/config/providers/ollama/CLAUDE.md"

    if grep -q "## Limitations" "$config" && \
       grep -q "context window" "$config"; then
        test_pass
    else
        test_fail "Limitations section missing or incomplete"
        return 1
    fi
}

test_no_attribution_references() {
    test_case "No attribution references to strategic-audit or source repos"

    local config="$PROJECT_ROOT/config/providers/ollama/CLAUDE.md"
    local doctor="$(resolve_claude_skill_path "skill-doctor")"

    local found=0
    for f in "$config" "$doctor"; do
        if grep -qi "strategic.audit" "$f" 2>/dev/null; then
            found=1
        fi
    done

    if [[ "$found" -eq 0 ]]; then
        test_pass
    else
        test_fail "Found prohibited attribution references"
        return 1
    fi
}

# Run all tests
test_ollama_config_exists
test_ollama_detection_method
test_ollama_server_health
test_ollama_model_selection
test_ollama_dispatch_pattern
test_ollama_zero_cost
test_ollama_model_preferences
test_skill_doctor_mentions_ollama
test_ollama_limitations_documented
test_no_attribution_references

test_summary
