#!/bin/bash
# Test Suite: Security Functions (v7.9.0)
# Tests URL validation, content wrapping, and security framing functions

# Note: no set -e — test has its own pass/fail tracking,
# and set -e + grep pipes cause SIGPIPE exits


# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test result tracking
declare -a FAILURES

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Security Functions (v7.9.0)"

set +o pipefail  # restore: original did not use pipefail


# NOTE: orchestrate.sh has a main execution block that runs on source,
# so we use grep-based static analysis for function existence checks
# and extract individual functions for runtime tests.
# Functions decomposed to lib/ in v9.7.7+
ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
ORCHESTRATE_SH="$ALL_SRC"

# Helper functions
pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

warn() { echo "$1"; }

info() { echo "$1"; }

#==============================================================================
# Test: validate_external_url function exists
#==============================================================================
test_validate_url_function_exists() {
    info "\n=== Testing: validate_external_url function exists ==="
    
    if grep -q "validate_external_url()" "$ALL_SRC"; then
        pass "validate_external_url function defined"
    else
        fail "validate_external_url function NOT found"
    fi
}

#==============================================================================
# Test: URL validation rejects HTTP
#==============================================================================
test_url_rejects_http() {
    info "\n=== Testing: URL validation rejects HTTP ==="

    # Static analysis: verify the function checks for https
    if grep -A 20 'validate_external_url()' "$ORCHESTRATE_SH" | grep -qi 'https\|http.*reject\|http.*error'; then
        pass "HTTP URLs are rejected (HTTPS required)"
    else
        fail "HTTP URLs should be rejected"
    fi
}

#==============================================================================
# Test: URL validation rejects localhost
#==============================================================================
test_url_rejects_localhost() {
    info "\n=== Testing: URL validation rejects localhost ==="

    if grep -A 30 'validate_external_url()' "$ORCHESTRATE_SH" | grep -qi 'localhost'; then
        pass "localhost URLs are rejected"
    else
        fail "localhost URLs should be rejected"
    fi
}

#==============================================================================
# Test: URL validation rejects private IPs (127.0.0.1)
#==============================================================================
test_url_rejects_loopback() {
    info "\n=== Testing: URL validation rejects loopback IP ==="

    if grep -A 30 'validate_external_url()' "$ORCHESTRATE_SH" | grep -q '127\.0\.0\.1'; then
        pass "127.0.0.1 URLs are rejected"
    else
        fail "127.0.0.1 URLs should be rejected"
    fi
}

#==============================================================================
# Test: URL validation rejects private IPs (10.x.x.x)
#==============================================================================
test_url_rejects_private_10() {
    info "\n=== Testing: URL validation rejects 10.x.x.x private IPs ==="

    if grep -A 55 'validate_external_url()' "$ORCHESTRATE_SH" | grep -qF '^10\.'; then
        pass "10.x.x.x private IPs are rejected"
    else
        fail "10.x.x.x private IPs should be rejected"
    fi
}

#==============================================================================
# Test: URL validation rejects private IPs (192.168.x.x)
#==============================================================================
test_url_rejects_private_192() {
    info "\n=== Testing: URL validation rejects 192.168.x.x private IPs ==="

    if grep -A 55 'validate_external_url()' "$ORCHESTRATE_SH" | grep -qF '192'; then
        pass "192.168.x.x private IPs are rejected"
    else
        fail "192.168.x.x private IPs should be rejected"
    fi
}

#==============================================================================
# Test: URL validation rejects metadata endpoints
#==============================================================================
test_url_rejects_metadata() {
    info "\n=== Testing: URL validation rejects cloud metadata endpoints ==="

    if grep -A 55 'validate_external_url()' "$ORCHESTRATE_SH" | grep -q '169.*254'; then
        pass "Cloud metadata endpoints (169.254.169.254) are rejected"
    else
        fail "Cloud metadata endpoints should be rejected"
    fi
}

#==============================================================================
# Test: URL validation rejects overly long URLs
#==============================================================================
test_url_rejects_long_urls() {
    info "\n=== Testing: URL validation rejects URLs > 2000 chars ==="

    if grep -A 40 'validate_external_url()' "$ORCHESTRATE_SH" | grep -qi '2000\|length\|too long'; then
        pass "URLs exceeding 2000 characters are rejected"
    else
        fail "Overly long URLs should be rejected"
    fi
}

#==============================================================================
# Test: transform_twitter_url function exists
#==============================================================================
test_transform_twitter_function_exists() {
    info "\n=== Testing: transform_twitter_url function exists ==="
    
    if grep -q "transform_twitter_url()" "$ALL_SRC"; then
        pass "transform_twitter_url function defined"
    else
        fail "transform_twitter_url function NOT found"
    fi
}

#==============================================================================
# Test: wrap_untrusted_content function exists
#==============================================================================
test_wrap_content_function_exists() {
    info "\n=== Testing: wrap_untrusted_content function exists ==="
    
    if grep -q "wrap_untrusted_content()" "$ALL_SRC"; then
        pass "wrap_untrusted_content function defined"
    else
        fail "wrap_untrusted_content function NOT found"
    fi
}

#==============================================================================
# Test: Security framing skill file exists
#==============================================================================
test_security_skill_exists() {
    info "\n=== Testing: skill-security-framing.md exists ==="
    
    if [[ -f "$PROJECT_ROOT/.claude/skills/skill-security-framing.md" ]]; then
        pass "skill-security-framing.md exists"
    else
        fail "skill-security-framing.md NOT found"
    fi
}

#==============================================================================
# Test: Security skill has proper frontmatter
#==============================================================================
test_security_skill_frontmatter() {
    info "\n=== Testing: skill-security-framing.md has valid frontmatter ==="
    
    local skill_file="$PROJECT_ROOT/.claude/skills/skill-security-framing.md"
    
    if [[ ! -f "$skill_file" ]]; then
        fail "skill-security-framing.md not found - skipping frontmatter test"
        return
    fi
    
    # Check opening delimiter
    if head -n 1 "$skill_file" | grep -q "^---$"; then
        pass "Has opening YAML delimiter"
    else
        fail "Missing opening YAML delimiter"
    fi
    
    # Check for name field
    if grep -q "^name:" "$skill_file"; then
        pass "Has 'name' field"
    else
        fail "Missing 'name' field"
    fi
    
    # Check for description field
    if grep -q "^description:" "$skill_file"; then
        pass "Has 'description' field"
    else
        fail "Missing 'description' field"
    fi
}

#==============================================================================
# Test: Security skill documents URL validation
#==============================================================================
test_security_skill_url_docs() {
    info "\n=== Testing: Security skill documents URL validation ==="
    
    local skill_file="$PROJECT_ROOT/.claude/skills/skill-security-framing.md"
    
    if [[ ! -f "$skill_file" ]]; then
        fail "skill-security-framing.md not found"
        return
    fi
    
    if grep -qi "validate.*url\|url.*validation" "$skill_file"; then
        pass "Documents URL validation"
    else
        fail "Should document URL validation"
    fi
}

#==============================================================================
# Test: Security skill documents content wrapping
#==============================================================================
test_security_skill_wrapping_docs() {
    info "\n=== Testing: Security skill documents content wrapping ==="
    
    local skill_file="$PROJECT_ROOT/.claude/skills/skill-security-framing.md"
    
    if [[ ! -f "$skill_file" ]]; then
        fail "skill-security-framing.md not found"
        return
    fi
    
    if grep -qi "untrusted.*content\|security.*frame\|wrap" "$skill_file"; then
        pass "Documents content wrapping/security framing"
    else
        fail "Should document content wrapping"
    fi
}

#==============================================================================
# Main test execution
#==============================================================================
echo "================================================================"
echo "  Security Functions Test Suite (v7.9.0)"
echo "================================================================"
echo

cd "$PROJECT_ROOT"

# Function existence tests
test_validate_url_function_exists
test_transform_twitter_function_exists
test_wrap_content_function_exists

# URL validation tests
test_url_rejects_http
test_url_rejects_localhost
test_url_rejects_loopback
test_url_rejects_private_10
test_url_rejects_private_192
test_url_rejects_metadata
test_url_rejects_long_urls

# Security skill tests
test_security_skill_exists
test_security_skill_frontmatter
test_security_skill_url_docs
test_security_skill_wrapping_docs

# Summary
echo
echo "================================================================"
echo "  Test Results Summary"
echo "================================================================"
echo
test_summary
