#!/usr/bin/env bash
# release.sh — One-command version bump, PR, merge, release, submodule update.
#
# Usage:
#   ./scripts/release.sh <version> "<summary>"
#
# Example:
#   ./scripts/release.sh 11.0.1 "Retire an unused compatibility adapter"
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
    echo "Example: $0 11.0.1 \"Retire an unused compatibility adapter\""
    exit 1
fi

VERSION="$1"
SUMMARY="$2"
DATE=$(date +%Y-%m-%d)
BRANCH="release/v${VERSION}"
REMOTE="${OCTO_RELEASE_REMOTE:-origin}"
CI_TIMEOUT_SECONDS="${OCTO_RELEASE_CI_TIMEOUT_SECONDS:-900}"

if [[ ! "$CI_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: OCTO_RELEASE_CI_TIMEOUT_SECONDS must be a positive integer."
    exit 1
fi

cd "$PLUGIN_ROOT"

# gh infers the target repo from remotes independently of $REMOTE, so a dev
# clone pointing $REMOTE at the canonical repo (with origin left on a fork)
# would otherwise create the PR/release against the wrong repo. Pin it.
REPO_SLUG="$(git remote get-url "$REMOTE" | sed -E 's#^(git@|https://)([^:/]+)[:/]##; s#\.git$##')"
REPO_OWNER="${REPO_SLUG%%/*}"
REPO_NAME="${REPO_SLUG#*/}"

if [[ -z "$REPO_OWNER" || -z "$REPO_NAME" || "$REPO_OWNER" == "$REPO_NAME" ]]; then
    echo "Error: could not parse owner/repository from remote ${REMOTE}: ${REPO_SLUG}"
    exit 1
fi

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

# plugin.json — use the release summary as the new marketplace source text
python3 - "$VERSION" "$SUMMARY" <<'PY'
import json
import sys

version, summary = sys.argv[1:]
summary = summary.strip().rstrip(".")
p = json.load(open('.claude-plugin/plugin.json'))
p['version'] = version
p['description'] = f'v{version} \u2014 {summary}. Run /octo:setup.'
json.dump(p, open('.claude-plugin/plugin.json', 'w'), indent=2)
print('   .claude-plugin/plugin.json')
PY

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
if not droid_dir.is_dir():
    print('ERROR: agents/droids is missing; cannot calculate browse manifest counts', file=sys.stderr)
    raise SystemExit(1)
droid_count = len(list(droid_dir.glob('*.md')))

with open('.claude-plugin/routines.json') as f:
    routines = json.load(f)
routine_count = len(routines.get('routines', []))

with open('hooks/hooks.json') as f:
    hooks = json.load(f)
hook_event_count = len(hooks.get('hooks', hooks))

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
    if path == 'README.md':
        text = re.sub(r'Version-\d+\.\d+\.\d+-blue', f'Version-{version}-blue', text)
        text = re.sub(r'Version \d+\.\d+\.\d+', f'Version {version}', text)
    readme_path.write_text(text)
print('   README count surfaces')

routines['\$comment'] = re.sub(r'\(v\d+\.\d+\.\d+\)', f'(v{version})', routines.get('\$comment', ''))
with open('.claude-plugin/routines.json', 'w') as f:
    json.dump(routines, f, indent=2)
    f.write('\n')
print('   .claude-plugin/routines.json')

plugin_manifest_path = pathlib.Path('.claude-plugin/plugin-manifest.json')
with plugin_manifest_path.open() as f:
    plugin_manifest = json.load(f)
plugin_manifest['version'] = version
components = plugin_manifest.setdefault('components', {})
components.setdefault('commands', {})['count'] = command_count
agents = components.setdefault('agents', {})
agents['count'] = persona_count + droid_count
agent_breakdown = agents.setdefault('breakdown', {})
agent_breakdown['personas'] = persona_count
agent_breakdown['droids'] = droid_count
components.setdefault('skills', {})['count'] = skill_count
components.setdefault('hooks', {})['events'] = hook_event_count
components.setdefault('routines', {})['count'] = routine_count
with plugin_manifest_path.open('w') as f:
    json.dump(plugin_manifest, f, indent=2)
    f.write('\n')
print('   .claude-plugin/plugin-manifest.json')

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

octo_release_update_changelog CHANGELOG.md "$VERSION" "$DATE" "$SUMMARY"

# Regenerate README and marketplace artifacts from their source
# files. The changelog entry must exist first so README sync can derive the
# release date for PRODUCT.md.
make sync

echo ""

# --- 2. Commit ---

echo "2/8 Committing..."
if [[ "$ON_RELEASE_BRANCH" == "false" ]]; then
    git checkout -b "$BRANCH" --quiet
fi
git add package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json .claude-plugin/plugin-manifest.json .claude-plugin/routines.json .claude-plugin/README.md .codex-plugin/plugin.json .cursor-plugin/plugin.json .factory-plugin/plugin.json .factory-plugin/marketplace.json README.md PRODUCT.md docs/AGENTS.md docs/COMMAND-REFERENCE.md docs/README.md CHANGELOG.md
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
PR_BODY="## Release v${VERSION}

${SUMMARY}

---
🤖 Generated with release.sh"
if ! PR_URL=$("$SCRIPT_DIR/safe-gh-comment.sh" \
        --repo "$REPO_SLUG" pr-create "chore: release v${VERSION}" \
        "$BRANCH" - <<< "$PR_BODY"); then
    echo "   ERROR: PR creation was blocked or failed."
    exit 1
fi
PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$')
echo "   PR #${PR_NUM}: ${PR_URL}"
echo ""

# --- 5. Wait for CI ---

echo "5/8 Waiting for CI..."
# macOS unit jobs routinely take around 10 minutes, so leave enough headroom
# while keeping the wait configurable for slower or faster repositories.
DEADLINE=$((SECONDS + CI_TIMEOUT_SECONDS))
while [[ $SECONDS -lt $DEADLINE ]]; do
    CHECKS=$(gh pr checks "$PR_NUM" -R "$REPO_SLUG" --json name,state 2>&1 || true)
    SMOKE=$(octo_pr_check_state "$CHECKS" "Smoke Tests")
    UNIT=$(octo_pr_check_state "$CHECKS" "Unit Tests")
    INTEG=$(octo_pr_check_state "$CHECKS" "Integration Tests")

    if [[ "$SMOKE" == "pass" && "$UNIT" == "pass" && "$INTEG" == "pass" ]]; then
        echo "   Smoke: pass | Unit: pass | Integration: pass"
        break
    fi

    if [[ "$SMOKE" == "fail" || "$UNIT" == "fail" || "$INTEG" == "fail" ]]; then
        echo "   CI FAILED — Smoke: ${SMOKE} | Unit: ${UNIT} | Integration: ${INTEG}"
        echo "   Fix failures, then run: gh pr merge ${PR_NUM} --squash -R ${REPO_SLUG}"
        exit 1
    fi

    sleep 10
done

if [[ $SECONDS -ge $DEADLINE ]]; then
    echo "   CI timed out after ${CI_TIMEOUT_SECONDS} seconds."
    echo "   Check manually: gh pr checks ${PR_NUM} -R ${REPO_SLUG}"
    echo "   Then merge: gh pr merge ${PR_NUM} --squash -R ${REPO_SLUG}"
    exit 1
fi
echo ""

# Required checks can pass while a review still has actionable findings.
# Fail closed instead of relying on an owner/admin merge bypass.
echo "   Checking review gate..."
if ! REVIEW_DECISION=$(gh pr view "$PR_NUM" -R "$REPO_SLUG" --json reviewDecision --jq '.reviewDecision // ""'); then
    echo "   ERROR: Could not read the PR review decision."
    exit 1
fi
if ! UNRESOLVED_THREADS=$(octo_release_unresolved_review_threads \
    "$REPO_OWNER" "$REPO_NAME" "$PR_NUM"); then
    echo "   ERROR: Could not read PR review threads."
    exit 1
fi
if ! octo_release_review_gate "$REVIEW_DECISION" "$UNRESOLVED_THREADS"; then
    echo "   REVIEW BLOCKED — decision=${REVIEW_DECISION:-none} | unresolved threads=${UNRESOLVED_THREADS}"
    echo "   An explicit approval and zero unresolved threads are required."
    exit 1
fi
echo "   Review: ${REVIEW_DECISION} | unresolved threads: 0"
echo ""

# --- 6. Merge + Release ---

echo "6/8 Merging and creating release..."
merge_release_pr() {
    gh pr merge "$PR_NUM" -R "$REPO_SLUG" --squash "$@"
}

read_release_pr_state() {
    gh pr view "$PR_NUM" -R "$REPO_SLUG" --json state --jq '.state'
}

if ! merge_release_pr --quiet 2>/dev/null; then
    if ! PR_STATE=$(read_release_pr_state); then
        echo "   ERROR: Merge failed and the PR state could not be read."
        exit 1
    fi
    if [[ "$PR_STATE" != "MERGED" ]]; then
        if ! merge_release_pr; then
            if ! PR_STATE=$(read_release_pr_state); then
                echo "   ERROR: Merge retry failed and the PR state could not be read."
                exit 1
            fi
            if [[ "$PR_STATE" != "MERGED" ]]; then
                echo "   ERROR: Release PR is still ${PR_STATE} after the merge retry."
                exit 1
            fi
        fi
    fi
fi

if ! MERGE_SHA=$(gh pr view "$PR_NUM" \
    -R "$REPO_SLUG" \
    --json state,mergeCommit \
    --jq 'select(.state == "MERGED") | .mergeCommit.oid // empty'); then
    echo "   ERROR: Could not read the merged PR commit."
    exit 1
fi
if [[ ! "$MERGE_SHA" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "   ERROR: Merged PR returned an invalid merge commit: ${MERGE_SHA:-empty}"
    exit 1
fi

git fetch --quiet "$REMOTE" main
if ! git merge-base --is-ancestor "$MERGE_SHA" FETCH_HEAD; then
    echo "   ERROR: PR merge commit ${MERGE_SHA} is not present on ${REMOTE}/main."
    exit 1
fi

if [[ "$ON_RELEASE_BRANCH" == "true" ]]; then
    # main is normally still checked out in the worktree this release branch
    # was cut from; don't touch this worktree's checkout or delete the branch
    # we're standing on. The PR API above is the release SHA source of truth.
    :
else
    git checkout main --quiet
    git pull --quiet "$REMOTE" main
    git branch -d "$BRANCH" --quiet 2>/dev/null || true
fi

# Do not publish a tag while the exact post-squash main commit is unverified.
echo "   Waiting for main Test Suite on ${MERGE_SHA}..."
MAIN_RUN_ID=""
MAIN_RUN_DEADLINE=$((SECONDS + 120))
while [[ -z "$MAIN_RUN_ID" && $SECONDS -lt $MAIN_RUN_DEADLINE ]]; do
    MAIN_RUN_ID=$(gh run list \
        -R "$REPO_SLUG" \
        --workflow "Test Suite" \
        --branch main \
        --event push \
        --limit 20 \
        --json databaseId,headSha \
        --jq ".[] | select(.headSha == \"${MERGE_SHA}\") | .databaseId" \
        | head -n 1)
    [[ -n "$MAIN_RUN_ID" ]] || sleep 5
done
if [[ -z "$MAIN_RUN_ID" ]]; then
    echo "   ERROR: Main Test Suite run did not appear for ${MERGE_SHA}."
    exit 1
fi
if ! octo_release_run_with_timeout "$CI_TIMEOUT_SECONDS" \
    gh run watch "$MAIN_RUN_ID" -R "$REPO_SLUG" --exit-status; then
    echo "   ERROR: Main Test Suite failed for ${MERGE_SHA}; tag and release were not created."
    exit 1
fi

TAG_NAME="v${VERSION}"
git tag -a "$TAG_NAME" "$MERGE_SHA" -m "${TAG_NAME}: ${SUMMARY}"
git push --quiet "$REMOTE" "$TAG_NAME"

gh release create "v${VERSION}" \
    -R "$REPO_SLUG" \
    --verify-tag \
    --title "v${VERSION} — ${SUMMARY}" \
    --notes "### Changed
- ${SUMMARY}

**Full Changelog**: https://github.com/nyldn/claude-octopus/compare/v${CURRENT}...v${VERSION}" \
    --quiet 2>/dev/null || \
gh release create "v${VERSION}" \
    -R "$REPO_SLUG" \
    --verify-tag \
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
