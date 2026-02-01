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

if [[ "$PLUGIN_NAME" != "octo" ]]; then
    echo -e "  ${RED}CRITICAL ERROR: plugin.json name is '$PLUGIN_NAME' - MUST be 'octo'${NC}"
    echo -e "  ${RED}This controls command namespace (/octo:* commands)${NC}"
    ((errors++))
else
    echo -e "  ${GREEN}✓ plugin.json name: octo (command namespace)${NC}"
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
    # Commands should NOT have "octo:" prefix in frontmatter (Claude Code adds it automatically)
    if [[ -n "$cmd_name" ]] && [[ "$cmd_name" == *":"* ]]; then
        echo -e "  ${RED}ERROR: $(basename "$cmd_file") has 'command: $cmd_name' - must NOT include namespace prefix${NC}"
        echo -e "  ${RED}  Claude Code will automatically add '/octo:' prefix based on plugin name${NC}"
        ((errors++))
        ((invalid_frontmatter++))
    fi
done

if [[ $invalid_frontmatter -eq 0 ]]; then
    echo -e "  ${GREEN}✓ All command frontmatters use correct format (no namespace prefix)${NC}"
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
    # Skills should use descriptive prefixes (skill-, flow-, sys-, etc.) but NOT namespace prefixes (octo:)
    if [[ "$skill_name" != "skill-"* ]] && [[ "$skill_name" != "flow-"* ]] && [[ "$skill_name" != "octopus-"* ]] && [[ "$skill_name" != "sys-"* ]]; then
        echo -e "  ${RED}ERROR: $(basename "$skill_file") has 'name: $skill_name' - must use descriptive prefix${NC}"
        echo -e "  ${RED}  Use: skill-, flow-, sys-, or octopus- prefix (NOT octo:)${NC}"
        ((errors++))
        ((invalid_skill_names++))
    fi
done

if [[ $invalid_skill_names -eq 0 ]]; then
    echo -e "  ${GREEN}✓ All skill names use correct format (descriptive prefix)${NC}"
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
# 8. GIT TAG CHECK & AUTO-CREATE
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
        echo -e "  ${YELLOW}  Updating tag to point to current HEAD...${NC}"

        # Delete old tag locally and remotely, create new one
        git tag -d "$EXPECTED_TAG" >/dev/null 2>&1 || true
        git push origin ":refs/tags/$EXPECTED_TAG" >/dev/null 2>&1 || true

        # Extract CHANGELOG entry for tag message
        TAG_MESSAGE=$(awk "/## \[$PLUGIN_VERSION\]/,/^## \[/" "$ROOT_DIR/CHANGELOG.md" | head -20 | tail -n +2)
        if [[ -n "$TAG_MESSAGE" ]]; then
            git tag -a "$EXPECTED_TAG" -m "$TAG_MESSAGE"
        else
            git tag -a "$EXPECTED_TAG" -m "Release $EXPECTED_TAG"
        fi
        echo -e "  ${GREEN}✓ Tag $EXPECTED_TAG updated to point to HEAD${NC}"
        ((warnings++))
    fi
else
    echo -e "  ${YELLOW}NOTE: Tag $EXPECTED_TAG not yet created${NC}"
    echo -e "  ${GREEN}  Auto-creating tag...${NC}"

    # Extract CHANGELOG entry for tag message
    TAG_MESSAGE=$(awk "/## \[$PLUGIN_VERSION\]/,/^## \[/" "$ROOT_DIR/CHANGELOG.md" | head -20 | tail -n +2)
    if [[ -n "$TAG_MESSAGE" ]]; then
        git tag -a "$EXPECTED_TAG" -m "$TAG_MESSAGE"
        echo -e "  ${GREEN}✓ Tag $EXPECTED_TAG created with CHANGELOG excerpt${NC}"
    else
        git tag -a "$EXPECTED_TAG" -m "Release $EXPECTED_TAG"
        echo -e "  ${GREEN}✓ Tag $EXPECTED_TAG created${NC}"
    fi
fi

echo ""

# ============================================================================
# 9. CHANGELOG ENTRY CHECK
# ============================================================================
echo "📝 Checking CHANGELOG entry..."

EXPECTED_TAG="v$PLUGIN_VERSION"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"

if [[ -f "$CHANGELOG_FILE" ]]; then
    # Check if version is mentioned in CHANGELOG
    if grep -q "## \[$PLUGIN_VERSION\]" "$CHANGELOG_FILE"; then
        echo -e "  ${GREEN}✓ CHANGELOG.md has entry for v$PLUGIN_VERSION${NC}"
    else
        echo -e "  ${RED}ERROR: CHANGELOG.md missing entry for v$PLUGIN_VERSION${NC}"
        echo -e "  ${RED}  Add a changelog entry before releasing${NC}"
        ((errors++))
    fi
else
    echo -e "  ${YELLOW}WARNING: CHANGELOG.md not found${NC}"
    ((warnings++))
fi

echo ""

# ============================================================================
# 10. GITHUB RELEASE CHECK & AUTO-CREATE
# ============================================================================
echo "🚀 Checking GitHub release..."

EXPECTED_TAG="v$PLUGIN_VERSION"

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo -e "  ${YELLOW}NOTE: gh CLI not installed - skipping GitHub release check${NC}"
    echo -e "  ${YELLOW}  Install with: brew install gh${NC}"
else
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        echo -e "  ${YELLOW}NOTE: Not authenticated with GitHub - skipping release check${NC}"
        echo -e "  ${YELLOW}  Authenticate with: gh auth login${NC}"
    else
        # Check if release exists
        if gh release view "$EXPECTED_TAG" &> /dev/null; then
            echo -e "  ${GREEN}✓ GitHub release $EXPECTED_TAG exists${NC}"
        else
            echo -e "  ${YELLOW}NOTE: GitHub release $EXPECTED_TAG does not exist${NC}"

            # Check if tag exists on remote
            REMOTE_TAG_SHA=$(git ls-remote origin "refs/tags/$EXPECTED_TAG" 2>/dev/null | cut -f1)

            if [[ -n "$REMOTE_TAG_SHA" ]]; then
                echo -e "  ${GREEN}  Auto-creating GitHub release from CHANGELOG...${NC}"

                # Extract CHANGELOG entry for this version
                RELEASE_NOTES=$(awk "/## \\[$PLUGIN_VERSION\\]/,/^---$/" "$ROOT_DIR/CHANGELOG.md" | sed '$d' | tail -n +3)

                if [[ -n "$RELEASE_NOTES" ]]; then
                    # Create release with CHANGELOG notes and mark as latest
                    if gh release create "$EXPECTED_TAG" --title "v$PLUGIN_VERSION" --notes "$RELEASE_NOTES" --latest >/dev/null 2>&1; then
                        echo -e "  ${GREEN}✓ GitHub release $EXPECTED_TAG created${NC}"
                    else
                        echo -e "  ${YELLOW}WARNING: Failed to create GitHub release${NC}"
                        ((warnings++))
                    fi
                else
                    echo -e "  ${YELLOW}WARNING: No CHANGELOG entry found for v$PLUGIN_VERSION${NC}"
                    echo -e "  ${YELLOW}  Cannot auto-create release without release notes${NC}"
                    ((warnings++))
                fi
            else
                echo -e "  ${YELLOW}  Tag not yet pushed to remote - will create release after push${NC}"
            fi
        fi
    fi
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

    # Auto-push tag if it was created/updated (v7.19.1+)
    EXPECTED_TAG="v$PLUGIN_VERSION"
    if git tag -l "$EXPECTED_TAG" | grep -q "$EXPECTED_TAG"; then
        # Check if tag needs to be pushed (doesn't exist on remote or is different)
        REMOTE_TAG_SHA=$(git ls-remote origin "refs/tags/$EXPECTED_TAG" 2>/dev/null | cut -f1)
        LOCAL_TAG_SHA=$(git rev-list -n 1 "$EXPECTED_TAG" 2>/dev/null)

        if [[ -z "$REMOTE_TAG_SHA" ]] || [[ "$REMOTE_TAG_SHA" != "$LOCAL_TAG_SHA" ]]; then
            echo ""
            echo -e "${GREEN}📤 Pushing tag $EXPECTED_TAG to remote...${NC}"
            git push --no-verify origin "$EXPECTED_TAG" --force 2>/dev/null
            echo -e "${GREEN}✓ Tag pushed to remote${NC}"

            # Auto-create GitHub release if gh is available and authenticated
            if command -v gh &> /dev/null && gh auth status &> /dev/null; then
                if ! gh release view "$EXPECTED_TAG" &> /dev/null; then
                    echo -e "${GREEN}📝 Creating GitHub release...${NC}"
                    RELEASE_NOTES=$(awk "/## \\[$PLUGIN_VERSION\\]/,/^---$/" "$ROOT_DIR/CHANGELOG.md" | sed '$d' | tail -n +3)
                    if [[ -n "$RELEASE_NOTES" ]] && gh release create "$EXPECTED_TAG" --title "v$PLUGIN_VERSION" --notes "$RELEASE_NOTES" --latest >/dev/null 2>&1; then
                        echo -e "${GREEN}✓ GitHub release $EXPECTED_TAG created${NC}"
                    fi
                fi
            fi
        fi
    fi

    exit 0
else
    echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
    echo ""
    echo "Ready to release v$PLUGIN_VERSION!"

    # Auto-push tag if it was created (v7.19.1+)
    EXPECTED_TAG="v$PLUGIN_VERSION"
    if git tag -l "$EXPECTED_TAG" | grep -q "$EXPECTED_TAG"; then
        REMOTE_TAG_SHA=$(git ls-remote origin "refs/tags/$EXPECTED_TAG" 2>/dev/null | cut -f1)
        LOCAL_TAG_SHA=$(git rev-list -n 1 "$EXPECTED_TAG" 2>/dev/null)

        if [[ -z "$REMOTE_TAG_SHA" ]] || [[ "$REMOTE_TAG_SHA" != "$LOCAL_TAG_SHA" ]]; then
            echo ""
            echo -e "${GREEN}📤 Pushing tag $EXPECTED_TAG to remote...${NC}"
            git push --no-verify origin "$EXPECTED_TAG" 2>/dev/null
            echo -e "${GREEN}✓ Tag pushed to remote${NC}"

            # Auto-create GitHub release if gh is available and authenticated
            if command -v gh &> /dev/null && gh auth status &> /dev/null; then
                if ! gh release view "$EXPECTED_TAG" &> /dev/null; then
                    echo -e "${GREEN}📝 Creating GitHub release...${NC}"
                    RELEASE_NOTES=$(awk "/## \\[$PLUGIN_VERSION\\]/,/^---$/" "$ROOT_DIR/CHANGELOG.md" | sed '$d' | tail -n +3)
                    if [[ -n "$RELEASE_NOTES" ]] && gh release create "$EXPECTED_TAG" --title "v$PLUGIN_VERSION" --notes "$RELEASE_NOTES" --latest >/dev/null 2>&1; then
                        echo -e "${GREEN}✓ GitHub release $EXPECTED_TAG created${NC}"
                    fi
                fi
            fi
        fi
    fi

    exit 0
fi
