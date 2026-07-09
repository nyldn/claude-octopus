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
#   1. Updates core version files plus public adapter manifests
#   2. Commits on a new branch
#   3. Pushes and creates a PR
#   4. Waits for required CI checks
#   5. Merges the PR
#   6. Creates a GitHub release with tag
#   7. Syncs the shared nyldn/plugins marketplace entry
#   8. Updates the submodule in the dev repo (if detected)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/lib/release-changelog.sh
source "$SCRIPT_DIR/lib/release-changelog.sh"
# shellcheck source=scripts/lib/release-ci.sh
source "$SCRIPT_DIR/lib/release-ci.sh"

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
REMOTE="${OCTO_RELEASE_REMOTE:-origin}"

cd "$PLUGIN_ROOT"

# --- Preflight ---

if ! git diff --quiet 2>/dev/null; then
    echo "Error: working tree has uncommitted changes. Commit or stash first."
    exit 1
fi

# RELEASING.md §0 allows two flows: run from main and let this script cut the
# release branch, or (worktree flow) cut ${BRANCH} from origin/main yourself
# and run this script already checked out on it.
CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "$BRANCH" ]]; then
    echo "Error: must be on main, or on ${BRANCH} cut from main (see RELEASING.md §0)."
    exit 1
fi
ON_RELEASE_BRANCH=false
[[ "$CURRENT_BRANCH" == "$BRANCH" ]] && ON_RELEASE_BRANCH=true

if [[ "$ON_RELEASE_BRANCH" == "false" ]]; then
    git pull --quiet "$REMOTE" main
fi

CURRENT=$(python3 -c "import json; print(json.load(open('package.json'))['version'])")
echo "Releasing: ${CURRENT} → ${VERSION}"
echo "Summary: ${SUMMARY}"
echo ""

# --- 1. Update version files ---

echo "1/8 Updating version files..."

# package.json
python3 -c "
import json
p = json.load(open('package.json'))
p['version'] = '${VERSION}'
json.dump(p, open('package.json', 'w'), indent=2)
print('   package.json')
"

# plugin.json — strip old version prefix, prepend new one from version field
python3 -c "
import json, re
p = json.load(open('.claude-plugin/plugin.json'))
p['version'] = '${VERSION}'
# Strip any existing version prefix, then prepend the new one
desc = re.sub(r'^v\d+\.\d+\.\d+\s*[\u2014\-]\s*', '', p['description'])
p['description'] = 'v${VERSION} \u2014 ' + desc
json.dump(p, open('.claude-plugin/plugin.json', 'w'), indent=2)
print('   .claude-plugin/plugin.json')
"

# marketplace.json — strip old version prefix, prepend new one
python3 -c "
import json, re
m = json.load(open('.claude-plugin/marketplace.json'))
for plugin in m.get('plugins', []):
    if plugin.get('name') == 'octo':
        plugin['version'] = '${VERSION}'
        # Strip any existing version prefix, then prepend the new one
        desc = re.sub(r'^v\d+\.\d+\.\d+\s*[\-\u2014]\s*', '', plugin['description'])
        plugin['description'] = 'v${VERSION} - ' + desc
m['metadata']['version'] = '${VERSION}'
json.dump(m, open('.claude-plugin/marketplace.json', 'w'), indent=2)
print('   .claude-plugin/marketplace.json')
"

# Public adapter manifests — keep every public root surface on the release version
python3 -c "
import json, pathlib, re, sys

version = '${VERSION}'

with open('.claude-plugin/plugin.json') as f:
    plugin = json.load(f)
command_count = len(plugin.get('commands', []))
skill_count = len(plugin.get('skills', []))

persona_dir = pathlib.Path('agents/personas')
if not persona_dir.is_dir():
    print('ERROR: agents/personas is missing; cannot calculate adapter manifest counts', file=sys.stderr)
    raise SystemExit(1)
persona_count = len(list(persona_dir.glob('*.md')))
if persona_count == 0:
    print('ERROR: agents/personas contains no persona markdown files', file=sys.stderr)
    raise SystemExit(1)

droid_dir = pathlib.Path('agents/droids')
droid_count = len(list(droid_dir.glob('*.md'))) if droid_dir.is_dir() else 0

manifest_path = pathlib.Path('.claude-plugin/plugin-manifest.json')
manifest = json.loads(manifest_path.read_text())
manifest['version'] = version
components = manifest.get('components', {})
components.get('commands', {})['count'] = command_count
components.get('skills', {})['count'] = skill_count
agents = components.get('agents', {})
agents['count'] = persona_count + droid_count
agents.get('breakdown', {})['personas'] = persona_count
agents.get('breakdown', {})['droids'] = droid_count
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print('   .claude-plugin/plugin-manifest.json')

count_phrase = f'{persona_count} personas, {command_count} commands, {skill_count} skills'
expert_count_phrase = f'{persona_count} expert personas, {command_count} commands, {skill_count} skills'
specialized_count_phrase = f'{command_count} commands, {skill_count} skills, {persona_count} specialized personas'

for path in ('README.md', '.claude-plugin/README.md'):
    readme_path = pathlib.Path(path)
    text = readme_path.read_text()
    text = re.sub(r'\*\*\d+ specialized personas\*\*', f'**{persona_count} specialized personas**', text)
    text = re.sub(r'\*\*\d+ commands\*\*', f'**{command_count} commands**', text)
    text = re.sub(r'\*\*\d+ skills\*\*', f'**{skill_count} skills**', text)
    text = re.sub(r'\b\d+ commands, \d+ skills, \d+ specialized personas\b', specialized_count_phrase, text)
    text = re.sub(r'\ball \d+ commands\b', f'all {command_count} commands', text)
    readme_path.write_text(text)
print('   README count surfaces')

path = pathlib.Path('.claude-plugin/marketplace.json')
with open(path) as f:
    data = json.load(f)
for item in data.get('plugins', []):
    if item.get('name') == 'octo':
        desc = item.get('description', '')
        item['description'] = re.sub(r'\d+ personas, \d+ commands, \d+ skills', count_phrase, desc)
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('   .claude-plugin/marketplace.json counts')

for path in ('.codex-plugin/plugin.json', '.cursor-plugin/plugin.json', '.factory-plugin/plugin.json'):
    with open(path) as f:
        data = json.load(f)
    data['version'] = version
    if path == '.codex-plugin/plugin.json':
        interface = data.setdefault('interface', {})
        desc = interface.get('longDescription', '')
        desc = re.sub(r'\\d+ personas, \\d+ commands, \\d+ skills', count_phrase, desc)
        interface['longDescription'] = desc
    if path == '.factory-plugin/plugin.json':
        data['description'] = f\"Multi-tentacled orchestrator using Double Diamond methodology. v{version}. {expert_count_phrase}. Commands '/octo:*'. Run /octo:setup for guided setup. Compatible with Claude Code and Factory AI Droid.\"
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\\n')
    print(f'   {path}')

path = '.factory-plugin/marketplace.json'
with open(path) as f:
    data = json.load(f)
data.setdefault('metadata', {})['version'] = version
for item in data.get('plugins', []):
    if item.get('name') == 'claude-octopus':
        item['version'] = version
        item['description'] = f'v{version} - Multi-AI orchestration with Double Diamond workflow. {count_phrase}. Run /octo:setup after install.'
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\\n')
print(f'   {path}')
"

# README badge
sed -i '' -E "s/\(v[0-9]+\.[0-9]+\.[0-9]+\)/(v${VERSION})/" .claude-plugin/routines.json
echo "   .claude-plugin/routines.json"
sed -i '' "s/Version-[0-9]*\.[0-9]*\.[0-9]*-blue/Version-${VERSION}-blue/g" README.md
sed -i '' "s/Version [0-9]*\.[0-9]*\.[0-9]*/Version ${VERSION}/g" README.md
echo "   README.md"

octo_release_update_changelog CHANGELOG.md "$VERSION" "$DATE" "$SUMMARY"

echo ""

# --- 2. Commit ---

echo "2/8 Committing..."
if [[ "$ON_RELEASE_BRANCH" == "false" ]]; then
    git checkout -b "$BRANCH" --quiet
fi
git add package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json .claude-plugin/plugin-manifest.json .claude-plugin/routines.json .codex-plugin/plugin.json .cursor-plugin/plugin.json .factory-plugin/plugin.json .factory-plugin/marketplace.json README.md CHANGELOG.md
git commit --quiet -m "chore: release v${VERSION} — ${SUMMARY}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
echo "   Committed on ${BRANCH}"
echo ""

# --- 3. Push ---

echo "3/8 Pushing..."
# --no-verify: skip pre-push hook (CI validates on PR; pre-push re-runs tests already run at commit)
PUSH_OUTPUT=$(git push --quiet --no-verify -u "$REMOTE" "$BRANCH" 2>&1) || {
    printf '%s\n' "$PUSH_OUTPUT" | grep -v "^remote:" || true
    echo "   ERROR: Push failed. Aborting release."
    exit 1
}
printf '%s\n' "$PUSH_OUTPUT" | grep -v "^remote:" || true
echo "   Pushed"
echo ""

# --- 4. Create PR ---

echo "4/8 Creating PR..."
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

echo "5/8 Waiting for CI..."
# Poll until required checks finish (max 5 minutes)
DEADLINE=$((SECONDS + 300))
while [[ $SECONDS -lt $DEADLINE ]]; do
    CHECKS=$(gh pr checks "$PR_NUM" --json name,state 2>&1 || true)
    SMOKE=$(octo_pr_check_state "$CHECKS" "Smoke Tests")
    UNIT=$(octo_pr_check_state "$CHECKS" "Unit Tests")
    INTEG=$(octo_pr_check_state "$CHECKS" "Integration Tests")

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

echo "6/8 Merging and creating release..."
gh pr merge "$PR_NUM" --merge --quiet 2>/dev/null || gh pr merge "$PR_NUM" --merge
git checkout main --quiet
git pull --quiet "$REMOTE" main
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

# --- 7. Sync shared marketplace ---

echo "7/8 Syncing shared marketplace..."
"$SCRIPT_DIR/sync-shared-marketplace.sh"
echo ""

# --- 8. Update submodule (if in dev repo) ---

echo "8/8 Updating submodule..."
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
