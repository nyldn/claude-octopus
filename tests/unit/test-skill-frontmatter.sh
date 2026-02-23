#!/bin/bash
# Test Suite: YAML Frontmatter Validation
# Ensures all skills have proper YAML frontmatter for Claude Code recognition

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test result tracking
declare -a FAILURES

# Helper functions
pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASSED_TESTS=$((PASSED_TESTS + 1))
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

fail() {
  echo -e "${RED}✗${NC} $1"
  FAILURES+=("$1")
  FAILED_TESTS=$((FAILED_TESTS + 1))
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

info() {
  echo "$1"
}

# Check if yq is installed (for YAML parsing)
check_dependencies() {
  if ! command -v yq &> /dev/null; then
    warn "yq not installed - using grep-based validation (less accurate)"
    warn "Install yq for better validation: brew install yq"
    USE_YQ=false
  else
    USE_YQ=true
  fi
}

# Validate YAML frontmatter structure
validate_frontmatter() {
  local file="$1"
  local filename=$(basename "$file")

  info "\nValidating: $filename"

  # Check if file has YAML frontmatter
  if ! head -n 1 "$file" | grep -q "^---$"; then
    fail "$filename: Missing opening YAML frontmatter delimiter (---)"
    return 1
  fi

  # Check if frontmatter closes
  if ! tail -n +2 "$file" | grep -q "^---$"; then
    fail "$filename: Missing closing YAML frontmatter delimiter (---)"
    return 1
  fi

  pass "$filename: Has YAML frontmatter delimiters"

  # Extract frontmatter
  local frontmatter=$(awk '/^---$/{if(++count==2) exit} count==1' "$file")

  # Check required fields
  local has_name=false
  local has_description=false
  local has_trigger=false

  if echo "$frontmatter" | grep -q "^name:"; then
    has_name=true
    pass "$filename: Has 'name' field"
  else
    fail "$filename: Missing required 'name' field"
  fi

  if echo "$frontmatter" | grep -q "^description:"; then
    has_description=true
    pass "$filename: Has 'description' field"
  else
    fail "$filename: Missing required 'description' field"
  fi

  if echo "$frontmatter" | grep -q "^trigger:"; then
    has_trigger=true
    pass "$filename: Has 'trigger' field"
  else
    # Trigger is optional for some skills, just warn
    warn "$filename: No 'trigger' field (may be intentional)"
  fi

  # Validate 'name' is kebab-case
  if $has_name; then
    local name_value=$(echo "$frontmatter" | grep "^name:" | sed 's/name: *//' | tr -d '"' | tr -d "'")
    if [[ "$name_value" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
      pass "$filename: 'name' is properly kebab-cased: $name_value"
    else
      fail "$filename: 'name' should be kebab-case, got: $name_value"
    fi
  fi

  # Validate 'description' is not empty (v8.0: all descriptions are single-line)
  if $has_description; then
    local desc_line=$(echo "$frontmatter" | grep "^description:")
    local desc_value=$(echo "$desc_line" | sed 's/description: *//')
    if [ -n "$desc_value" ]; then
      pass "$filename: 'description' has value"
      # v8.0: Verify single-line format — check if description line itself ends with |
      if echo "$desc_line" | grep -qE "^description:[[:space:]]*\|[[:space:]]*$"; then
        fail "$filename: 'description' uses multi-line format (should be single-line per v8.0)"
      fi
    else
      fail "$filename: 'description' is empty"
    fi
  fi

  # Validate 'trigger' content if present
  if $has_trigger; then
    # Check if trigger uses multi-line format (|)
    if echo "$frontmatter" | grep -A 1 "^trigger:" | grep -q "|"; then
      pass "$filename: 'trigger' uses multi-line format"

      # Check for "AUTOMATICALLY ACTIVATE" pattern
      if echo "$frontmatter" | grep -q "AUTOMATICALLY ACTIVATE"; then
        pass "$filename: 'trigger' contains activation pattern"
      else
        warn "$filename: 'trigger' missing 'AUTOMATICALLY ACTIVATE' pattern"
      fi

      # Check for "DO NOT activate" pattern
      if echo "$frontmatter" | grep -q "DO NOT activate"; then
        pass "$filename: 'trigger' contains exclusion pattern"
      else
        warn "$filename: 'trigger' missing 'DO NOT activate' exclusion pattern"
      fi
    else
      warn "$filename: 'trigger' should use multi-line format for clarity"
    fi
  fi

  return 0
}

# Main test execution
main() {
  echo "================================================================"
  echo "  YAML Frontmatter Validation Test Suite"
  echo "================================================================"
  echo

  check_dependencies

  # Find all skill files
  local skills_dir=".claude/skills"
  if [ ! -d "$skills_dir" ]; then
    echo -e "${RED}ERROR:${NC} Skills directory not found: $skills_dir"
    echo "Run this script from the repository root"
    exit 1
  fi

  local skill_files=$(find "$skills_dir" -name "*.md" -type f)
  local skill_count=$(echo "$skill_files" | wc -l | tr -d ' ')

  info "Found $skill_count skill files to validate"
  echo

  # Validate each skill
  while IFS= read -r skill_file; do
    validate_frontmatter "$skill_file"
  done <<< "$skill_files"

  # Summary
  echo
  echo "================================================================"
  echo "  Test Results Summary"
  echo "================================================================"
  echo
  echo "Total Tests: $TOTAL_TESTS"
  echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
  echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
  echo

  if [ $FAILED_TESTS -gt 0 ]; then
    echo "================================================================"
    echo "  Failures:"
    echo "================================================================"
    for failure in "${FAILURES[@]}"; do
      echo -e "${RED}✗${NC} $failure"
    done
    echo
    exit 1
  else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  fi
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
