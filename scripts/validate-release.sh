#!/usr/bin/env bash
# validate-release.sh - Pre-release validation for claude-octopus
# Prevents common release issues like version mismatches and missing registrations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

errors=0
warnings=0

echo "🐙 Claude Octopus Release Validation"
echo "======================================"
echo ""

# ============================================================================
# 1. PLUGIN NAME CHECK (CRITICAL - DO NOT CHANGE)
# ============================================================================
echo "🔒 Checking plugin names..."

PLUGIN_NAME=$(grep '"name"' "$ROOT_DIR/.claude-plugin/plugin.json" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
MARKETPLACE_PLUGIN_NAME=$(sed -n '/"plugins"/,/]/p' "$ROOT_DIR/.claude-plugin/marketplace.json" | grep '"name"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

if [[ "$PLUGIN_NAME" != "claude-octopus" ]]; then
    echo -e "  ${RED}CRITICAL ERROR: plugin.json name is '$PLUGIN_NAME' - MUST be 'claude-octopus'${NC}"
    echo -e "  ${RED}This controls plugin registration${NC}"
    ((errors++))
else
    echo -e "  ${GREEN}✓ plugin.json name: claude-octopus${NC}"
fi

if [[ "$MARKETPLACE_PLUGIN_NAME" != "claude-octopus" ]]; then
    echo -e "  ${RED}CRITICAL ERROR: marketplace.json plugin name is '$MARKETPLACE_PLUGIN_NAME' - MUST be 'claude-octopus'${NC}"
    echo -e "  ${RED}This controls install command (claude-octopus@nyldn-plugins)${NC}"
    ((errors++))
else
    echo -e "  ${GREEN}✓ marketplace.json plugin name: claude-octopus (install name)${NC}"
fi

echo ""

# ============================================================================
# 2. VERSION SYNC CHECK
# ============================================================================
echo "📦 Checking version synchronization..."

PLUGIN_VERSION=$(grep '"version"' "$ROOT_DIR/.claude-plugin/plugin.json" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
MARKETPLACE_VERSION=$(grep '"version"' "$ROOT_DIR/.claude-plugin/marketplace.json" | grep -v "1.0.0" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
PACKAGE_VERSION=$(grep '"version"' "$ROOT_DIR/package.json" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

# Check README badge
README_BADGE_VERSION=$(grep -o 'Version-[0-9.]*' "$ROOT_DIR/README.md" | head -1 | sed 's/Version-//')

echo "  plugin.json:      $PLUGIN_VERSION"
echo "  marketplace.json: $MARKETPLACE_VERSION"
echo "  package.json:     $PACKAGE_VERSION"
echo "  README badge:     $README_BADGE_VERSION"

if [[ "$PLUGIN_VERSION" != "$MARKETPLACE_VERSION" ]]; then
    echo -e "  ${RED}ERROR: plugin.json ($PLUGIN_VERSION) != marketplace.json ($MARKETPLACE_VERSION)${NC}"
    ((errors++))
fi

if [[ "$PLUGIN_VERSION" != "$PACKAGE_VERSION" ]]; then
    echo -e "  ${RED}ERROR: plugin.json ($PLUGIN_VERSION) != package.json ($PACKAGE_VERSION)${NC}"
    ((errors++))
fi

if [[ "$PLUGIN_VERSION" != "$README_BADGE_VERSION" ]]; then
    echo -e "  ${YELLOW}WARNING: plugin.json ($PLUGIN_VERSION) != README badge ($README_BADGE_VERSION)${NC}"
    ((warnings++))
fi

if [[ $errors -eq 0 ]] && [[ "$PLUGIN_VERSION" == "$MARKETPLACE_VERSION" ]] && [[ "$PLUGIN_VERSION" == "$PACKAGE_VERSION" ]]; then
    echo -e "  ${GREEN}✓ All versions synchronized: v$PLUGIN_VERSION${NC}"
fi

echo ""

# ============================================================================
# 3. COMMAND REGISTRATION CHECK
# ============================================================================
echo "📝 Checking command registration..."

# Get all .md files in commands directory
COMMAND_FILES=$(ls "$ROOT_DIR/.claude/commands/"*.md 2>/dev/null | xargs -n1 basename | sort)

# Get commands registered in plugin.json
REGISTERED_COMMANDS=$(grep -o '\.claude/commands/[^"]*\.md' "$ROOT_DIR/.claude-plugin/plugin.json" | sed 's|.*\.claude/commands/||' | sort)

# Find unregistered commands
for cmd_file in $COMMAND_FILES; do
    if ! echo "$REGISTERED_COMMANDS" | grep -q "^${cmd_file}$"; then
        echo -e "  ${RED}ERROR: Command file '$cmd_file' not registered in plugin.json${NC}"
        ((errors++))
    fi
done

# Find registered but missing commands
for reg_cmd in $REGISTERED_COMMANDS; do
    if ! echo "$COMMAND_FILES" | grep -q "^${reg_cmd}$"; then
        echo -e "  ${RED}ERROR: Registered command '$reg_cmd' does not exist${NC}"
        ((errors++))
    fi
done

cmd_count=$(echo "$COMMAND_FILES" | wc -l | tr -d ' ')
reg_count=$(echo "$REGISTERED_COMMANDS" | wc -l | tr -d ' ')

if [[ "$cmd_count" == "$reg_count" ]] && [[ $errors -eq 0 ]]; then
    echo -e "  ${GREEN}✓ All $cmd_count commands properly registered${NC}"
fi

echo ""

# ============================================================================
# 4. COMMAND FRONTMATTER FORMAT CHECK
# ============================================================================
echo "📛 Checking command frontmatter format..."

invalid_frontmatter=0
for cmd_file in "$ROOT_DIR/.claude/commands/"*.md; do
    cmd_name=$(sed -n '2p' "$cmd_file" | grep -o 'command: .*' | sed 's/command: //')
    if [[ -n "$cmd_name" ]] && [[ "$cmd_name" != "octo:"* ]]; then
        echo -e "  ${RED}ERROR: $(basename "$cmd_file") has 'command: $cmd_name' - must start with 'octo:'${NC}"
        echo -e "  ${RED}  Command prefix must be explicit in frontmatter${NC}"
        ((errors++))
        ((invalid_frontmatter++))
    fi
done

if [[ $invalid_frontmatter -eq 0 ]]; then
    echo -e "  ${GREEN}✓ All command frontmatters use correct format (octo: prefix)${NC}"
fi

echo ""

# ============================================================================
# 5. SKILL REGISTRATION CHECK
# ============================================================================
echo "🎯 Checking skill registration..."

SKILL_FILES=$(ls "$ROOT_DIR/.claude/skills/"*.md 2>/dev/null | xargs -n1 basename | sort)
REGISTERED_SKILLS=$(grep -o '\.claude/skills/[^"]*\.md' "$ROOT_DIR/.claude-plugin/plugin.json" | sed 's|.*\.claude/skills/||' | sort)

for skill_file in $SKILL_FILES; do
    if ! echo "$REGISTERED_SKILLS" | grep -q "^${skill_file}$"; then
        echo -e "  ${RED}ERROR: Skill file '$skill_file' not registered in plugin.json${NC}"
        ((errors++))
    fi
done

for reg_skill in $REGISTERED_SKILLS; do
    if ! echo "$SKILL_FILES" | grep -q "^${reg_skill}$"; then
        echo -e "  ${RED}ERROR: Registered skill '$reg_skill' does not exist${NC}"
        ((errors++))
    fi
done

skill_count=$(echo "$SKILL_FILES" | wc -l | tr -d ' ')
reg_skill_count=$(echo "$REGISTERED_SKILLS" | wc -l | tr -d ' ')

if [[ "$skill_count" == "$reg_skill_count" ]] && [[ $errors -eq 0 ]]; then
    echo -e "  ${GREEN}✓ All $skill_count skills properly registered${NC}"
fi

echo ""

# ============================================================================
# 6. SKILL FRONTMATTER FORMAT CHECK
# ============================================================================
echo "🏷️  Checking skill frontmatter format..."

invalid_skill_names=0
for skill_file in "$ROOT_DIR/.claude/skills/"*.md; do
    skill_name=$(sed -n '2p' "$skill_file" | grep -o 'name: .*' | sed 's/name: //')
    # Skip if no name found (might be a different format)
    if [[ -z "$skill_name" ]]; then
        continue
    fi
    # Check if name starts with octo: or contains specific prefixes that are allowed
    if [[ "$skill_name" != "octo:"* ]] && [[ "$skill_name" != "skill-"* ]] && [[ "$skill_name" != "flow-"* ]] && [[ "$skill_name" != "octopus-"* ]] && [[ "$skill_name" != "sys-"* ]]; then
        echo -e "  ${RED}ERROR: $(basename "$skill_file") has 'name: $skill_name' - must start with 'octo:' (or use special prefix)${NC}"
        echo -e "  ${RED}  Skill names without prefix cause command ambiguity${NC}"
        ((errors++))
        ((invalid_skill_names++))
    fi
done

if [[ $invalid_skill_names -eq 0 ]]; then
    echo -e "  ${GREEN}✓ All skill names use correct format (octo: or special prefix)${NC}"
fi

echo ""

# ============================================================================
# 7. MARKETPLACE DESCRIPTION VERSION CHECK
# ============================================================================
echo "🏪 Checking marketplace description..."

MARKETPLACE_DESC=$(grep '"description"' "$ROOT_DIR/.claude-plugin/marketplace.json" | grep -v "Multi-tentacled orchestration" | head -1)

if echo "$MARKETPLACE_DESC" | grep -q "v$PLUGIN_VERSION"; then
    echo -e "  ${GREEN}✓ Marketplace description mentions v$PLUGIN_VERSION${NC}"
else
    echo -e "  ${YELLOW}WARNING: Marketplace description may not mention current version v$PLUGIN_VERSION${NC}"
    ((warnings++))
fi

echo ""

# ============================================================================
# 8. GIT TAG CHECK
# ============================================================================
echo "🔖 Checking git tag..."

EXPECTED_TAG="v$PLUGIN_VERSION"
if git tag -l "$EXPECTED_TAG" | grep -q "$EXPECTED_TAG"; then
    TAG_COMMIT=$(git rev-list -n 1 "$EXPECTED_TAG")
    HEAD_COMMIT=$(git rev-parse HEAD)
    
    if [[ "$TAG_COMMIT" == "$HEAD_COMMIT" ]]; then
        echo -e "  ${GREEN}✓ Tag $EXPECTED_TAG exists and points to HEAD${NC}"
    else
        echo -e "  ${YELLOW}WARNING: Tag $EXPECTED_TAG exists but doesn't point to HEAD${NC}"
        echo -e "  ${YELLOW}  Tag points to: ${TAG_COMMIT:0:7}${NC}"
        echo -e "  ${YELLOW}  HEAD is:       ${HEAD_COMMIT:0:7}${NC}"
        ((warnings++))
    fi
else
    echo -e "  ${YELLOW}NOTE: Tag $EXPECTED_TAG not yet created${NC}"
    echo -e "  ${YELLOW}  Create with: git tag -a $EXPECTED_TAG -m 'Release $EXPECTED_TAG'${NC}"
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "======================================"
if [[ $errors -gt 0 ]]; then
    echo -e "${RED}❌ VALIDATION FAILED: $errors error(s), $warnings warning(s)${NC}"
    echo ""
    echo "Fix the errors above before releasing."
    exit 1
elif [[ $warnings -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  VALIDATION PASSED WITH WARNINGS: $warnings warning(s)${NC}"
    echo ""
    echo "Consider fixing the warnings before releasing."
    exit 0
else
    echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
    echo ""
    echo "Ready to release v$PLUGIN_VERSION!"
    exit 0
fi
