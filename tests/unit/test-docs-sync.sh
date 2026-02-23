#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test result tracking
declare -a FAILURES

# Helper functions
pass() {
  echo -e "${GREEN}✓${NC} $1"
  ((PASSED_TESTS++)) || true
  ((TOTAL_TESTS++)) || true
}

fail() {
  echo -e "${RED}✗${NC} $1"
  FAILURES+=("$1")
  ((FAILED_TESTS++)) || true
  ((TOTAL_TESTS++)) || true
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

info() {
  echo "$1"
}

# Extract version from plugin.json
get_plugin_version() {
  if [ ! -f ".claude-plugin/plugin.json" ]; then
    echo "ERROR: plugin.json not found"
    exit 1
  fi

  # Extract version using grep and sed (portable, no jq needed)
  # Use head -n 1 to get only the first version (main plugin version, not dependencies)
  grep '"version"' .claude-plugin/plugin.json | head -n 1 | sed 's/.*"version": *"\([^"]*\)".*/\1/'
}

# Check if version appears in README badges
check_readme_version() {
  local version="$1"

  if [ ! -f "README.md" ]; then
    fail "README.md not found"
    return 1
  fi

  if grep -q "Version-${version}" README.md; then
    pass "README.md badge shows version ${version}"
  else
    fail "README.md badge does not show version ${version}"
  fi
}

# Check if version appears in CHANGELOG
check_changelog_version() {
  local version="$1"

  if [ ! -f "CHANGELOG.md" ]; then
    fail "CHANGELOG.md not found"
    return 1
  fi

  if grep -q "## \[${version}\]" CHANGELOG.md || grep -q "## ${version}" CHANGELOG.md; then
    pass "CHANGELOG.md has entry for version ${version}"
  else
    fail "CHANGELOG.md missing entry for version ${version}"
  fi
}

# Check README structure
check_readme_structure() {
  local readme="README.md"

  info "\nValidating README.md structure..."

  # Check required sections exist
  local required_sections=(
    "# Claude Octopus"
    "## Quickstart"
    "## What It Does"
    "## How It Works"
    "## Documentation"
    "## Attribution"
    "## Contributing"
    "## License"
  )

  for section in "${required_sections[@]}"; do
    # Allow emoji prefixes in section headers
    if grep -q "^${section}" "$readme" || grep -q "^## .*${section#\#\# }" "$readme"; then
      pass "README has section: $section"
    else
      fail "README missing section: $section"
    fi
  done

  # Check if README mentions visual indicators (v7.4 feature)
  if grep -q "Visual Indicators" "$readme" || grep -q "visual indicators" "$readme"; then
    pass "README documents visual indicators (v7.4 feature)"
  else
    warn "README missing visual indicators documentation"
  fi

  # Check if README mentions natural language workflows (v7.4 feature)
  if grep -q "Natural Language" "$readme" || grep -q "natural language" "$readme"; then
    pass "README documents natural language workflows (v7.4 feature)"
  else
    warn "README missing natural language documentation"
  fi

  # Check README length (should be under 600 lines for plugin-first approach)
  local line_count=$(wc -l < "$readme" | tr -d ' ')
  if [ "$line_count" -le 600 ]; then
    pass "README.md is concise ($line_count lines, target ≤600)"
  else
    warn "README.md is long ($line_count lines, target ≤600)"
  fi
}

# Check documentation files exist
check_docs_files() {
  info "\nValidating documentation files..."

  local required_docs=(
    "docs/VISUAL-INDICATORS.md"
    "docs/TRIGGERS.md"
    "docs/CLI-REFERENCE.md"
    "docs/PLUGIN-ARCHITECTURE.md"
  )

  for doc in "${required_docs[@]}"; do
    if [ -f "$doc" ]; then
      pass "Documentation file exists: $doc"
    else
      fail "Missing documentation file: $doc"
    fi
  done
}

# Check all primary skills are registered in plugin.json (v7.5+)
check_skills_registered() {
  info "\nValidating skill registration..."

  local plugin_json=".claude-plugin/plugin.json"
  local skills_dir=".claude/skills"

  if [ ! -f "$plugin_json" ]; then
    fail "plugin.json not found"
    return 1
  fi

  if [ ! -d "$skills_dir" ]; then
    fail "Skills directory not found: $skills_dir"
    return 1
  fi

  # v7.5+: Primary skills follow naming pattern: sys-*, flow-*, skill-*
  # Shortcut aliases (probe.md, review.md, etc.) are NOT registered in plugin.json
  # They're defined as aliases in the primary skill's frontmatter

  # Find all primary skill files (sys-*, flow-*, skill-*)
  local skill_files=$(find "$skills_dir" -name "*.md" -type f | grep -E '(sys-|flow-|skill-).*\.md$')

  while IFS= read -r skill_file; do
    local skill_path="./.claude/skills/$(basename "$skill_file")"

    if grep -q "$skill_path" "$plugin_json"; then
      pass "Skill registered: $(basename "$skill_file")"
    else
      fail "Skill NOT registered in plugin.json: $(basename "$skill_file")"
    fi
  done <<< "$skill_files"
}

# Check workflow skills exist (v7.5+: renamed to flow-*)
check_workflow_skills() {
  info "\nValidating workflow skills (v7.5+: flow-* naming)..."

  # v7.9+: Double Diamond workflow phases
  local workflow_skills=(
    ".claude/skills/flow-discover.md"
    ".claude/skills/flow-define.md"
    ".claude/skills/flow-develop.md"
    ".claude/skills/flow-deliver.md"
  )

  for skill in "${workflow_skills[@]}"; do
    if [ -f "$skill" ]; then
      pass "Workflow skill exists: $(basename "$skill")"
    else
      fail "Missing workflow skill: $(basename "$skill")"
    fi
  done
}

# Check hooks configuration
check_hooks_config() {
  info "\nValidating hooks configuration..."

  local hooks_json=".claude-plugin/hooks.json"

  if [ ! -f "$hooks_json" ]; then
    fail "hooks.json not found"
    return 1
  fi

  # Check for visual indicator hooks (v7.4)
  if grep -q "orchestrate.*probe|grasp|tangle|ink" "$hooks_json"; then
    pass "hooks.json has orchestrate.sh workflow hooks"
  else
    fail "hooks.json missing orchestrate.sh workflow hooks"
  fi

  if grep -q "codex exec" "$hooks_json"; then
    pass "hooks.json has Codex CLI hook"
  else
    fail "hooks.json missing Codex CLI hook"
  fi

  if grep -q "gemini -" "$hooks_json"; then
    pass "hooks.json has Gemini CLI hook"
  else
    fail "hooks.json missing Gemini CLI hook"
  fi
}

# Check debate skill (v7.5+: renamed to skill-debate.md)
check_debate_skill() {
  info "\nValidating debate skill (v7.5+: skill-debate naming)..."

  # v7.5+: Primary skill is skill-debate.md, debate.md is a shortcut alias
  local debate_skill=".claude/skills/skill-debate.md"
  local debate_alias=".claude/skills/debate.md"

  # Check primary skill exists
  if [ ! -f "$debate_skill" ]; then
    fail "skill-debate.md not found"
    return 1
  fi

  # Check if skill-debate.md has YAML frontmatter
  if head -n 1 "$debate_skill" | grep -q "^---$"; then
    pass "skill-debate.md has YAML frontmatter"
  else
    fail "skill-debate.md missing YAML frontmatter (required for Claude Code)"
  fi

  # Check if skill-debate.md is registered in plugin.json
  if grep -q "./.claude/skills/skill-debate.md" ".claude-plugin/plugin.json"; then
    pass "skill-debate.md registered in plugin.json"
  else
    fail "skill-debate.md NOT registered in plugin.json"
  fi

  # Check that shortcut alias exists
  if [ -f "$debate_alias" ]; then
    pass "debate.md shortcut alias exists"
  else
    warn "debate.md shortcut alias not found (optional)"
  fi
}

# Check marketplace.json version sync
check_marketplace_version() {
  info "\nValidating marketplace.json version sync..."

  local marketplace_json=".claude-plugin/marketplace.json"
  local plugin_json=".claude-plugin/plugin.json"

  if [ ! -f "$marketplace_json" ]; then
    fail "marketplace.json not found"
    return 1
  fi

  if [ ! -f "$plugin_json" ]; then
    fail "plugin.json not found"
    return 1
  fi

  # Extract version from plugin.json
  local plugin_version=$(grep '"version"' "$plugin_json" | head -n 1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')

  # Extract version field from marketplace.json
  local marketplace_version=$(grep '"version"' "$marketplace_json" | tail -n 1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')

  # Check if versions match
  if [ "$plugin_version" = "$marketplace_version" ]; then
    pass "marketplace.json version matches plugin.json ($plugin_version)"
  else
    fail "marketplace.json version ($marketplace_version) does not match plugin.json ($plugin_version)"
  fi

  # Check if version appears at START of description
  if grep -q "\"description\": \"v${plugin_version}" "$marketplace_json"; then
    pass "marketplace.json description starts with version (v${plugin_version})"
  else
    fail "marketplace.json description should start with 'v${plugin_version} - ...'"
  fi
}

# Check command YAML frontmatter (v7.5.5+)
check_command_frontmatter() {
  info "\nValidating command YAML frontmatter..."

  local commands_dir=".claude/commands"

  if [ ! -d "$commands_dir" ]; then
    fail "Commands directory not found: $commands_dir"
    return 1
  fi

  # Check each command file
  for cmd_file in "$commands_dir"/*.md; do
    if [ ! -f "$cmd_file" ]; then
      continue
    fi

    local filename=$(basename "$cmd_file")

    # Check if file has YAML frontmatter
    if ! head -1 "$cmd_file" | grep -q "^---$"; then
      fail "$filename: Missing YAML frontmatter"
      continue
    fi

    # Check if it uses 'command:' field (correct)
    if grep -q "^command:" "$cmd_file"; then
      pass "$filename uses 'command:' field"
    else
      # Check if it incorrectly uses 'name:' field
      if grep -q "^name:" "$cmd_file"; then
        fail "$filename uses 'name:' instead of 'command:' (run: ./scripts/fix-command-frontmatter.sh)"
      else
        fail "$filename: No 'command:' field found"
      fi
    fi
  done
}

# Main test execution
main() {
  echo "================================================================"
  echo "  Documentation Sync Validation Test Suite"
  echo "================================================================"
  echo

  # Get version from plugin.json
  VERSION=$(get_plugin_version)
  info "Current version from plugin.json: $VERSION"
  echo

  # Run test suites
  check_readme_version "$VERSION"
  check_changelog_version "$VERSION"
  check_readme_structure
  check_docs_files
  check_skills_registered
  check_workflow_skills
  check_hooks_config
  check_debate_skill
  check_marketplace_version
  check_command_frontmatter

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
