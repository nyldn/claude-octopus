#!/bin/bash
# tests/security/test-secret-disclosure.sh
# Security test for accidental API key/token disclosure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Security: Secret Disclosure Prevention"

# Patterns for common API keys and tokens
OPENAI_PATTERN="sk-[a-zA-Z0-9]{48}"
GEMINI_PATTERN="AIza[0-9A-Za-z_-]{35}"
GITHUB_TOKEN_PATTERN="gh[pousr]_[A-Za-z0-9]{36,255}"
AWS_ACCESS_KEY="AKIA[0-9A-Z]{16}"
GENERIC_API_KEY="['\"][a-zA-Z0-9_-]{32,}['\"]"

test_no_openai_keys_in_files() {
    test_case "No OpenAI API keys in current files"

    # Search current files for OpenAI key pattern
    local findings=$(grep -r -E "$OPENAI_PATTERN" "$PROJECT_ROOT" \
        --exclude-dir=".git" \
        --exclude-dir="node_modules" \
        --exclude-dir=".dependencies" \
        --exclude="*.log" \
        --exclude="test-secret-disclosure.sh" \
        2>/dev/null || true)

    if [[ -z "$findings" ]]; then
        test_pass
    else
        test_fail "Found potential OpenAI API keys in files:"
        echo "$findings"
        return 1
    fi
}

test_no_gemini_keys_in_files() {
    test_case "No Gemini API keys in current files"

    local findings=$(grep -r -E "$GEMINI_PATTERN" "$PROJECT_ROOT" \
        --exclude-dir=".git" \
        --exclude-dir="node_modules" \
        --exclude-dir=".dependencies" \
        --exclude="*.log" \
        --exclude="test-secret-disclosure.sh" \
        2>/dev/null || true)

    if [[ -z "$findings" ]]; then
        test_pass
    else
        test_fail "Found potential Gemini API keys in files:"
        echo "$findings"
        return 1
    fi
}

test_no_github_tokens_in_files() {
    test_case "No GitHub tokens in current files"

    local findings=$(grep -r -E "$GITHUB_TOKEN_PATTERN" "$PROJECT_ROOT" \
        --exclude-dir=".git" \
        --exclude-dir="node_modules" \
        --exclude-dir=".dependencies" \
        --exclude="*.log" \
        --exclude="test-secret-disclosure.sh" \
        2>/dev/null || true)

    if [[ -z "$findings" ]]; then
        test_pass
    else
        test_fail "Found potential GitHub tokens in files:"
        echo "$findings"
        return 1
    fi
}

test_no_aws_keys_in_files() {
    test_case "No AWS access keys in current files"

    local findings=$(grep -r -E "$AWS_ACCESS_KEY" "$PROJECT_ROOT" \
        --exclude-dir=".git" \
        --exclude-dir="node_modules" \
        --exclude-dir=".dependencies" \
        --exclude="*.log" \
        --exclude="test-secret-disclosure.sh" \
        2>/dev/null || true)

    if [[ -z "$findings" ]]; then
        test_pass
    else
        test_fail "Found potential AWS access keys in files:"
        echo "$findings"
        return 1
    fi
}

test_no_secrets_in_git_history() {
    test_case "No OpenAI keys in git history"

    cd "$PROJECT_ROOT"

    # Check git history for OpenAI keys (limited to last 100 commits for performance)
    local findings=$(git log -p --all -S "$OPENAI_PATTERN" --pickaxe-regex -100 2>/dev/null | \
        grep -E "$OPENAI_PATTERN" || true)

    if [[ -z "$findings" ]]; then
        test_pass
    else
        test_fail "Found potential OpenAI API keys in git history"
        echo "  First 200 chars: ${findings:0:200}"
        echo "  CRITICAL: Keys found in history must be rotated even if removed from current files"
        return 1
    fi
}

test_no_gemini_secrets_in_git_history() {
    test_case "No Gemini keys in git history"

    cd "$PROJECT_ROOT"

    local findings=$(git log -p --all -S "$GEMINI_PATTERN" --pickaxe-regex -100 2>/dev/null | \
        grep -E "$GEMINI_PATTERN" || true)

    if [[ -z "$findings" ]]; then
        test_pass
    else
        test_fail "Found potential Gemini API keys in git history"
        echo "  First 200 chars: ${findings:0:200}"
        echo "  CRITICAL: Keys found in history must be rotated even if removed from current files"
        return 1
    fi
}

test_no_env_files_committed() {
    test_case "No .env files committed to repository"

    cd "$PROJECT_ROOT"

    # Check if .env files exist in git (current files)
    local env_files=$(git ls-files | grep -E "^\.env$|\.env\.local$|\.env\.production$" || true)

    if [[ -z "$env_files" ]]; then
        test_pass
    else
        test_fail "Found .env files committed to repository:"
        echo "$env_files"
        echo "  .env files should be in .gitignore, not committed"
        return 1
    fi
}

test_env_files_in_gitignore() {
    test_case ".env files are in .gitignore"

    local gitignore="$PROJECT_ROOT/.gitignore"

    if [[ ! -f "$gitignore" ]]; then
        test_fail ".gitignore file not found"
        return 1
    fi

    if grep -q "^\.env" "$gitignore" || grep -q "^\*\.env" "$gitignore"; then
        test_pass
    else
        test_fail ".env pattern not found in .gitignore"
        echo "  Add: .env* to .gitignore to prevent accidental commits"
        return 1
    fi
}

test_no_credentials_in_config_files() {
    test_case "No hardcoded credentials in config files"

    # Check common config file locations for credential keywords
    # Using simpler pattern to avoid grep "braces not balanced" error
    local suspicious_files=$(grep -r -i -l "password.*=\|secret.*=\|api_key.*=\|token.*=" \
        "$PROJECT_ROOT" \
        --include="*.json" \
        --include="*.yaml" \
        --include="*.yml" \
        --include="*.toml" \
        --include="*.ini" \
        --exclude-dir=".git" \
        --exclude-dir="node_modules" \
        --exclude-dir=".dependencies" \
        --exclude="package-lock.json" \
        --exclude="test-secret-disclosure.sh" \
        2>/dev/null | while read -r file; do
            # Check if file contains actual credential-like values (not just variable names)
            if grep -i -E "(password|secret|api_key|token).*=.*['\"][a-zA-Z0-9_-]{20,}['\"]" "$file" 2>/dev/null | \
               grep -v "YOUR_API_KEY\|your-api-key\|example\|placeholder\|description\|OPENAI_API_KEY\|GEMINI_API_KEY\|\${\|process.env" >/dev/null 2>&1; then
                echo "$file"
            fi
        done)

    if [[ -z "$suspicious_files" ]]; then
        test_pass
    else
        test_fail "Found potential hardcoded credentials in config files:"
        echo "$suspicious_files" | head -10
        return 1
    fi
}

test_no_private_keys_in_repo() {
    test_case "No private keys (.pem, .key) in repository"

    cd "$PROJECT_ROOT"

    # Check for private key files in git
    local key_files=$(git ls-files | grep -E "\.(pem|key)$" || true)

    if [[ -z "$key_files" ]]; then
        test_pass
    else
        test_fail "Found private key files in repository:"
        echo "$key_files"
        echo "  Private keys should NEVER be committed"
        return 1
    fi
}

test_sensitive_files_in_gitignore() {
    test_case "Sensitive file patterns in .gitignore"

    local gitignore="$PROJECT_ROOT/.gitignore"

    if [[ ! -f "$gitignore" ]]; then
        test_fail ".gitignore file not found"
        return 1
    fi

    local missing_patterns=()

    # Check for common sensitive patterns
    grep -q "\.env" "$gitignore" || missing_patterns+=(".env")
    grep -q "\.pem\|\.key" "$gitignore" || missing_patterns+=("*.pem, *.key")
    grep -q "credentials" "$gitignore" || missing_patterns+=("*credentials*")

    if [[ ${#missing_patterns[@]} -eq 0 ]]; then
        test_pass
    else
        test_fail "Missing sensitive file patterns in .gitignore:"
        printf "  - %s\n" "${missing_patterns[@]}"
        return 1
    fi
}

test_no_secrets_in_documentation() {
    test_case "No API keys in documentation files"

    # Check README, docs for accidentally pasted API keys
    local findings=$(grep -r -E "$OPENAI_PATTERN|$GEMINI_PATTERN|$GITHUB_TOKEN_PATTERN" \
        "$PROJECT_ROOT" \
        --include="*.md" \
        --include="*.txt" \
        --exclude-dir=".git" \
        --exclude="test-secret-disclosure.sh" \
        2>/dev/null || true)

    if [[ -z "$findings" ]]; then
        test_pass
    else
        test_fail "Found potential API keys in documentation:"
        echo "$findings" | head -5
        return 1
    fi
}

test_example_configs_use_placeholders() {
    test_case "Example configs use placeholders, not real keys"

    # Find example config files
    local example_configs=$(find "$PROJECT_ROOT" -type f \( -name "*.example" -o -name "example.*" -o -name "*sample*" \) 2>/dev/null || true)

    if [[ -z "$example_configs" ]]; then
        test_skip "No example config files found"
        return 0
    fi

    # Check if they contain real-looking API keys
    local bad_examples=$(echo "$example_configs" | while read -r file; do
        if grep -E "$OPENAI_PATTERN|$GEMINI_PATTERN|$GITHUB_TOKEN_PATTERN" "$file" 2>/dev/null; then
            echo "$file"
        fi
    done)

    if [[ -z "$bad_examples" ]]; then
        test_pass
    else
        test_fail "Example configs contain real-looking API keys:"
        echo "$bad_examples"
        return 1
    fi
}

test_no_leaked_secrets_in_logs() {
    test_case "No API keys in log files"

    # Check if any .log files exist and contain secrets
    local log_files=$(find "$PROJECT_ROOT" -name "*.log" -type f 2>/dev/null || true)

    if [[ -z "$log_files" ]]; then
        test_skip "No log files found"
        return 0
    fi

    local findings=$(echo "$log_files" | while read -r log; do
        grep -E "$OPENAI_PATTERN|$GEMINI_PATTERN|$GITHUB_TOKEN_PATTERN" "$log" 2>/dev/null || true
    done)

    if [[ -z "$findings" ]]; then
        test_pass
    else
        test_fail "Found potential API keys in log files"
        echo "  WARNING: Logs may contain secrets - review and clean"
        return 1
    fi
}

# Run all security tests
test_no_openai_keys_in_files
test_no_gemini_keys_in_files
test_no_github_tokens_in_files
test_no_aws_keys_in_files
test_no_secrets_in_git_history
test_no_gemini_secrets_in_git_history
test_no_env_files_committed
test_env_files_in_gitignore
test_no_credentials_in_config_files
test_no_private_keys_in_repo
test_sensitive_files_in_gitignore
test_no_secrets_in_documentation
test_example_configs_use_placeholders
test_no_leaked_secrets_in_logs

test_summary
