#!/usr/bin/env bash
# Test suite for /co:extract command
# Tests the extraction pipeline components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_test() {
  echo -e "${BLUE}TEST:${NC} $*"
  ((TESTS_RUN++))
}

log_pass() {
  echo -e "${GREEN}✓ PASS:${NC} $*"
  ((TESTS_PASSED++))
}

log_fail() {
  echo -e "${RED}✗ FAIL:${NC} $*"
  ((TESTS_FAILED++))
}

log_skip() {
  echo -e "${YELLOW}⊘ SKIP:${NC} $*"
}

# Test 1: Command file exists
test_command_exists() {
  log_test "Command file exists"

  if [[ -f "${PLUGIN_ROOT}/.claude/commands/extract.md" ]]; then
    log_pass "extract.md exists"
  else
    log_fail "extract.md not found"
    return 1
  fi
}

# Test 2: Skill file exists
test_skill_exists() {
  log_test "Skill file exists"

  if [[ -f "${PLUGIN_ROOT}/.claude/skills/extract-skill.md" ]]; then
    log_pass "extract-skill.md exists"
  else
    log_fail "extract-skill.md not found"
    return 1
  fi
}

# Test 3: Core extractor script exists and is executable
test_core_extractor() {
  log_test "Core extractor script"

  local script="${PLUGIN_ROOT}/scripts/extract/core-extractor.sh"

  if [[ ! -f "${script}" ]]; then
    log_fail "core-extractor.sh not found"
    return 1
  fi

  if [[ ! -x "${script}" ]]; then
    log_fail "core-extractor.sh not executable"
    return 1
  fi

  # Test help output
  if bash "${script}" --help 2>&1 | grep -q "Usage:"; then
    log_pass "Help command works"
  else
    log_fail "Help command failed"
    return 1
  fi
}

# Test 4: Token extraction files exist
test_token_extraction_files() {
  log_test "Token extraction implementation"

  local token_dir="${PLUGIN_ROOT}/scripts/token-extraction"
  local required_files=(
    "types.ts"
    "pipeline.ts"
    "cli.ts"
    "utils.ts"
    "merger.ts"
    "package.json"
  )

  local missing=0
  for file in "${required_files[@]}"; do
    if [[ ! -f "${token_dir}/${file}" ]]; then
      log_fail "Missing: ${file}"
      ((missing++))
    fi
  done

  if [[ ${missing} -eq 0 ]]; then
    log_pass "All token extraction files present"
  else
    log_fail "${missing} token extraction files missing"
    return 1
  fi
}

# Test 5: Token extractors exist
test_token_extractors() {
  log_test "Token extractors"

  local extractors_dir="${PLUGIN_ROOT}/scripts/token-extraction/extractors"
  local extractors=(
    "tailwind.ts"
    "css-variables.ts"
    "theme-file.ts"
    "styled-components.ts"
  )

  local missing=0
  for extractor in "${extractors[@]}"; do
    if [[ ! -f "${extractors_dir}/${extractor}" ]]; then
      log_fail "Missing extractor: ${extractor}"
      ((missing++))
    fi
  done

  if [[ ${missing} -eq 0 ]]; then
    log_pass "All 4 extractors present"
  else
    log_fail "${missing} extractors missing"
    return 1
  fi
}

# Test 6: Token output generators exist
test_token_outputs() {
  log_test "Token output generators"

  local outputs_dir="${PLUGIN_ROOT}/scripts/token-extraction/outputs"
  local outputs=(
    "json.ts"
    "css.ts"
    "markdown.ts"
  )

  local missing=0
  for output in "${outputs[@]}"; do
    if [[ ! -f "${outputs_dir}/${output}" ]]; then
      log_fail "Missing output generator: ${output}"
      ((missing++))
    fi
  done

  if [[ ${missing} -eq 0 ]]; then
    log_pass "All 3 output generators present"
  else
    log_fail "${missing} output generators missing"
    return 1
  fi
}

# Test 7: Component analyzer files exist
test_component_analyzer_files() {
  log_test "Component analyzer implementation"

  local analyzer_dir="${PLUGIN_ROOT}/component-analyzer/src"
  local required_files=(
    "types.ts"
    "engine.ts"
    "cli.ts"
    "index.ts"
  )

  local missing=0
  for file in "${required_files[@]}"; do
    if [[ ! -f "${analyzer_dir}/${file}" ]]; then
      log_fail "Missing: ${file}"
      ((missing++))
    fi
  done

  if [[ ${missing} -eq 0 ]]; then
    log_pass "All component analyzer files present"
  else
    log_fail "${missing} component analyzer files missing"
    return 1
  fi
}

# Test 8: Component analyzers exist
test_component_analyzers() {
  log_test "Component analyzers"

  local analyzers_dir="${PLUGIN_ROOT}/component-analyzer/src/analyzers"
  local analyzers=(
    "typescript-analyzer.ts"
    "prop-extractor.ts"
    "variant-detector.ts"
    "usage-tracker.ts"
  )

  local missing=0
  for analyzer in "${analyzers[@]}"; do
    if [[ ! -f "${analyzers_dir}/${analyzer}" ]]; then
      log_fail "Missing analyzer: ${analyzer}"
      ((missing++))
    fi
  done

  if [[ ${missing} -eq 0 ]]; then
    log_pass "All 4 analyzers present"
  else
    log_fail "${missing} analyzers missing"
    return 1
  fi
}

# Test 9: Auto-detection types exist
test_auto_detection() {
  log_test "Auto-detection types"

  if [[ -f "${PLUGIN_ROOT}/src/types/auto-detection.ts" ]]; then
    log_pass "Auto-detection types present"
  else
    log_fail "Auto-detection types missing"
    return 1
  fi
}

# Test 10: Documentation exists
test_documentation() {
  log_test "Documentation files"

  local docs=(
    "scripts/token-extraction/README.md"
    "scripts/token-extraction/ARCHITECTURE.md"
    "component-analyzer/README.md"
    "component-analyzer/ARCHITECTURE.md"
    "docs/architecture/auto-detection-engine.md"
  )

  local missing=0
  for doc in "${docs[@]}"; do
    if [[ ! -f "${PLUGIN_ROOT}/${doc}" ]]; then
      log_fail "Missing: ${doc}"
      ((missing++))
    fi
  done

  if [[ ${missing} -eq 0 ]]; then
    log_pass "All documentation files present"
  else
    log_fail "${missing} documentation files missing"
    return 1
  fi
}

# Test 11: Package.json files are valid
test_package_json_validity() {
  log_test "package.json validity"

  local packages=(
    "scripts/token-extraction/package.json"
    "component-analyzer/package.json"
  )

  local invalid=0
  for pkg in "${packages[@]}"; do
    if [[ -f "${PLUGIN_ROOT}/${pkg}" ]]; then
      if ! node -e "JSON.parse(require('fs').readFileSync('${PLUGIN_ROOT}/${pkg}', 'utf8'))" 2>/dev/null; then
        log_fail "Invalid JSON: ${pkg}"
        ((invalid++))
      fi
    else
      log_fail "Missing: ${pkg}"
      ((invalid++))
    fi
  done

  if [[ ${invalid} -eq 0 ]]; then
    log_pass "All package.json files valid"
  else
    log_fail "${invalid} package.json files invalid/missing"
    return 1
  fi
}

# Test 12: TypeScript files compile
test_typescript_compilation() {
  log_test "TypeScript compilation (token-extraction)"

  local token_dir="${PLUGIN_ROOT}/scripts/token-extraction"

  if [[ -d "${token_dir}/node_modules" ]]; then
    cd "${token_dir}"
    if npx tsc --noEmit 2>/dev/null; then
      log_pass "Token extraction TypeScript compiles"
    else
      log_fail "Token extraction TypeScript errors"
      return 1
    fi
  else
    log_skip "node_modules not installed (run: cd ${token_dir} && npm install)"
  fi
}

# Test 13: Component analyzer TypeScript compiles
test_component_analyzer_compilation() {
  log_test "TypeScript compilation (component-analyzer)"

  local analyzer_dir="${PLUGIN_ROOT}/component-analyzer"

  if [[ -d "${analyzer_dir}/node_modules" ]]; then
    cd "${analyzer_dir}"
    if npx tsc --noEmit 2>/dev/null; then
      log_pass "Component analyzer TypeScript compiles"
    else
      log_fail "Component analyzer TypeScript errors"
      return 1
    fi
  else
    log_skip "node_modules not installed (run: cd ${analyzer_dir} && npm install)"
  fi
}

# Test 14: Unit tests exist
test_unit_tests_exist() {
  log_test "Unit tests"

  if [[ -f "${PLUGIN_ROOT}/component-analyzer/src/__tests__/variant-detector.test.ts" ]]; then
    log_pass "Unit tests present"
  else
    log_fail "No unit tests found"
    return 1
  fi
}

# Test 15: Examples exist
test_examples() {
  log_test "Example files"

  local examples=(
    "scripts/token-extraction/examples/basic-usage.ts"
    "scripts/token-extraction/examples/advanced-usage.ts"
    "component-analyzer/examples/usage-example.ts"
  )

  local missing=0
  for example in "${examples[@]}"; do
    if [[ ! -f "${PLUGIN_ROOT}/${example}" ]]; then
      log_fail "Missing: ${example}"
      ((missing++))
    fi
  done

  if [[ ${missing} -eq 0 ]]; then
    log_pass "All example files present"
  else
    log_fail "${missing} example files missing"
    return 1
  fi
}

# Main test runner
main() {
  echo ""
  echo "================================================"
  echo "  /co:extract Test Suite"
  echo "================================================"
  echo ""

  # Run all tests
  test_command_exists || true
  test_skill_exists || true
  test_core_extractor || true
  test_token_extraction_files || true
  test_token_extractors || true
  test_token_outputs || true
  test_component_analyzer_files || true
  test_component_analyzers || true
  test_auto_detection || true
  test_documentation || true
  test_package_json_validity || true
  test_typescript_compilation || true
  test_component_analyzer_compilation || true
  test_unit_tests_exist || true
  test_examples || true

  # Summary
  echo ""
  echo "================================================"
  echo "  Test Summary"
  echo "================================================"
  echo -e "Total tests:  ${TESTS_RUN}"
  echo -e "${GREEN}Passed:       ${TESTS_PASSED}${NC}"
  echo -e "${RED}Failed:       ${TESTS_FAILED}${NC}"
  echo ""

  if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}✗ ${TESTS_FAILED} test(s) failed${NC}"
    exit 1
  fi
}

# Run tests
main "$@"
