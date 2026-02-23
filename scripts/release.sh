#!/usr/bin/env bash
# release.sh — One-command version bump, PR, merge, release, submodule update.
#
# Usage:
#   ./scripts/release.sh <version> "<summary>"
#
# Example:
#   ./scripts/release.sh 8.22.6 "Fix OpenClaw register crash"
#
# What it does:
#   1. Updates version in all 5 files (package.json, plugin.json, marketplace.json, README, CHANGELOG)
#   2. Commits on a new branch
#   3. Pushes and creates a PR
#   4. Waits for required CI checks
#   5. Merges the PR
#   6. Creates a GitHub release with tag
#   7. Updates the submodule in the dev repo (if detected)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Args ---

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <version> \"<summary>\""
    echo "Example: $0 8.22.6 \"Fix OpenClaw register crash\""
    exit 1
fi

VERSION="$1"
SUMMARY="$2"
DATE=$(date +%Y-%m-%d)
BRANCH="release/v${VERSION}"

cd "$PLUGIN_ROOT"

# --- Preflight ---

if ! git diff --quiet 2>/dev/null; then
    echo "Error: working tree has uncommitted changes. Commit or stash first."
    exit 1
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "Error: must be on main branch."
    exit 1
fi

git pull --quiet origin main

CURRENT=$(python3 -c "import json; print(json.load(open('package.json'))['version'])")
echo "Releasing: ${CURRENT} → ${VERSION}"
echo "Summary: ${SUMMARY}"
echo ""

# --- 1. Update version files ---

echo "1/7 Updating version files..."

# package.json
python3 -c "
import json
p = json.load(open('package.json'))
p['version'] = '${VERSION}'
json.dump(p, open('package.json', 'w'), indent=2)
print('   package.json')
"

# plugin.json
python3 -c "
import json
p = json.load(open('.claude-plugin/plugin.json'))
p['version'] = '${VERSION}'
p['description'] = p['description'].replace('(v${CURRENT})', '(v${VERSION})')
if '(v${VERSION})' not in p['description']:
    # Fallback: replace first version-like pattern
    import re
    p['description'] = re.sub(r'\(v\d+\.\d+\.\d+\)', '(v${VERSION})', p['description'], count=1)
json.dump(p, open('.claude-plugin/plugin.json', 'w'), indent=2)
print('   .claude-plugin/plugin.json')
"

# marketplace.json
python3 -c "
import json
m = json.load(open('.claude-plugin/marketplace.json'))
for plugin in m.get('plugins', []):
    if plugin.get('name') == 'claude-octopus':
        plugin['version'] = '${VERSION}'
        plugin['description'] = 'v${VERSION} - ${SUMMARY}. ' + plugin['description'].split('. ', 1)[-1] if '. ' in plugin['description'] else 'v${VERSION} - ${SUMMARY}.'
json.dump(m, open('.claude-plugin/marketplace.json', 'w'), indent=2)
print('   .claude-plugin/marketplace.json')
"

# README badge
sed -i '' "s/Version-[0-9]*\.[0-9]*\.[0-9]*-blue/Version-${VERSION}-blue/g" README.md
sed -i '' "s/Version [0-9]*\.[0-9]*\.[0-9]*/Version ${VERSION}/g" README.md
echo "   README.md"

# CHANGELOG
CHANGELOG_ENTRY="## [${VERSION}] - ${DATE}"
if ! grep -q "\\[${VERSION}\\]" CHANGELOG.md 2>/dev/null; then
    # Prepend new entry
    TEMP=$(mktemp)
    echo "${CHANGELOG_ENTRY}" > "$TEMP"
    echo "" >> "$TEMP"
    echo "### Changed" >> "$TEMP"
    echo "" >> "$TEMP"
    echo "- ${SUMMARY}" >> "$TEMP"
    echo "" >> "$TEMP"
    echo "---" >> "$TEMP"
    echo "" >> "$TEMP"
    cat CHANGELOG.md >> "$TEMP"
    mv "$TEMP" CHANGELOG.md
    echo "   CHANGELOG.md (new entry)"
else
    echo "   CHANGELOG.md (entry already exists)"
fi

echo ""

# --- 2. Commit ---

echo "2/7 Committing..."
git checkout -b "$BRANCH" --quiet
git add package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json README.md CHANGELOG.md
git commit --quiet -m "chore: release v${VERSION} — ${SUMMARY}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
echo "   Committed on ${BRANCH}"
echo ""

# --- 3. Push ---

echo "3/7 Pushing..."
git push --quiet -u origin "$BRANCH" 2>&1 | grep -v "^remote:" || true
echo "   Pushed"
echo ""

# --- 4. Create PR ---

echo "4/7 Creating PR..."
PR_URL=$(gh pr create \
    --title "chore: release v${VERSION}" \
    --body "## Release v${VERSION}

${SUMMARY}

---
🤖 Generated with release.sh" \
    2>&1)
PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$')
echo "   PR #${PR_NUM}: ${PR_URL}"
echo ""

# --- 5. Wait for CI ---

echo "5/7 Waiting for CI..."
# Poll until required checks finish (max 5 minutes)
DEADLINE=$((SECONDS + 300))
while [[ $SECONDS -lt $DEADLINE ]]; do
    CHECKS=$(gh pr checks "$PR_NUM" 2>&1 || true)
    SMOKE=$(echo "$CHECKS" | grep "Smoke Tests" | awk '{print $2}' || echo "pending")
    UNIT=$(echo "$CHECKS" | grep "Unit Tests" | awk '{print $2}' || echo "pending")
    INTEG=$(echo "$CHECKS" | grep "Integration Tests" | awk '{print $2}' || echo "pending")

    if [[ "$SMOKE" == "pass" && "$UNIT" == "pass" && "$INTEG" == "pass" ]]; then
        echo "   Smoke: pass | Unit: pass | Integration: pass"
        break
    fi

    if [[ "$SMOKE" == "fail" || "$UNIT" == "fail" || "$INTEG" == "fail" ]]; then
        echo "   CI FAILED — Smoke: ${SMOKE} | Unit: ${UNIT} | Integration: ${INTEG}"
        echo "   Fix failures, then run: gh pr merge ${PR_NUM} --merge"
        exit 1
    fi

    sleep 10
done

if [[ $SECONDS -ge $DEADLINE ]]; then
    echo "   CI timed out after 5 minutes."
    echo "   Check manually: gh pr checks ${PR_NUM}"
    echo "   Then merge: gh pr merge ${PR_NUM} --merge"
    exit 1
fi
echo ""

# --- 6. Merge + Release ---

echo "6/7 Merging and creating release..."
gh pr merge "$PR_NUM" --merge --quiet 2>/dev/null || gh pr merge "$PR_NUM" --merge
git checkout main --quiet
git pull --quiet origin main
git branch -d "$BRANCH" --quiet 2>/dev/null || true

gh release create "v${VERSION}" \
    --title "v${VERSION} — ${SUMMARY}" \
    --notes "### Changed
- ${SUMMARY}

**Full Changelog**: https://github.com/nyldn/claude-octopus/compare/v${CURRENT}...v${VERSION}" \
    --quiet 2>/dev/null || \
gh release create "v${VERSION}" \
    --title "v${VERSION} — ${SUMMARY}" \
    --notes "### Changed
- ${SUMMARY}

**Full Changelog**: https://github.com/nyldn/claude-octopus/compare/v${CURRENT}...v${VERSION}"

echo "   Merged PR #${PR_NUM}"
echo "   Release: https://github.com/nyldn/claude-octopus/releases/tag/v${VERSION}"
echo ""

# --- 7. Update submodule (if in dev repo) ---

echo "7/7 Updating submodule..."
DEV_ROOT="$(cd "$PLUGIN_ROOT/.." && pwd)"
if [[ -f "$DEV_ROOT/.gitmodules" ]] && grep -q "plugin" "$DEV_ROOT/.gitmodules" 2>/dev/null; then
    cd "$DEV_ROOT"
    git add plugin
    git commit --quiet -m "feat: update plugin submodule — v${VERSION} release

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
    git push --quiet
    echo "   Submodule updated and pushed"
else
    echo "   No dev repo detected, skipping submodule update"
fi

echo ""
echo "=== v${VERSION} released ==="
