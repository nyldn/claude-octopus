#!/usr/bin/env bash
# validate-no-hardcoded-paths.sh - Ensure no hardcoded local paths in deployment
# Prevents privacy leaks and environment-specific configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    local color="$NC"
    case "$level" in
        INFO) color="$GREEN" ;;
        WARN) color="$YELLOW" ;;
        ERROR) color="$RED" ;;
    esac
    printf '%b%s%b\n' "$color" "$*" "$NC" >&2
}

log INFO "🔍 Checking for hardcoded local paths..."
log INFO ""

violations=0

package_files=""
if command -v npm >/dev/null 2>&1; then
    package_files=$(npm pack --dry-run --json --ignore-scripts 2>/dev/null | \
        python3 -c 'import json, sys; data = json.load(sys.stdin); print("\\n".join(item["path"] for item in data[0].get("files", [])))' \
        2>/dev/null || true)
else
    log WARN "npm is unavailable; checking tracked files only"
fi

path_is_published() {
    local path="$1"
    git ls-files -- "$path" "$path/**" | grep -q . && return 0
    [[ -n "$package_files" ]] && printf '%s\n' "$package_files" | \
        awk -v path="$path" '$0 == path || index($0, path "/") == 1 { found = 1 } END { exit found ? 0 : 1 }'
}

# Development-only material belongs in the private development repository.
# Keep this guard in the public checkout so a later sync cannot republish it.
log INFO "Checking for development-only public files..."
for forbidden_path in \
    .beads \
    .claude/DEVELOPMENT.md \
    .claude/claude-octopus.local.md \
    .claude/settings.json \
    AI_AGENT_HANDOFF.md \
    GOALS.md \
    RTK.md \
    docs/plans \
    docs/research \
    docs/roadmaps \
    docs/superpowers; do
    if path_is_published "$forbidden_path"; then
        log ERROR "✗ Found forbidden development path in tracked/package contents: $forbidden_path"
        violations=$((violations + 1))
    fi
done
if [ "$violations" -eq 0 ]; then
    log INFO "✓ No forbidden development files found"
fi

# Check for absolute user paths in deployment files (only git-tracked files)
log INFO "Checking for absolute user paths (/Users/*, /home/*)..."
hardcoded_users=$(git ls-files | grep -E "\.(md|sh|js|json|yaml)$" | \
  grep -v '^tests/' | \
  grep -v '^docs/' | \
  grep -v "validate-no-hardcoded-paths.sh" | \
  xargs grep -n "/Users/[^/]*/\|/home/[^/]*/" 2>/dev/null | \
  grep -v "~/" | \
  grep -v "# Example:" | \
  grep -v "# Note:" | \
  grep -v "Example:" | \
  grep -v "/Users/<you>" | \
  grep -v "/home/<user>" | \
  grep -v "/home/user/" || true)

if [ -n "$hardcoded_users" ]; then
    log ERROR "✗ Found hardcoded user paths:"
    log ERROR "$(echo "$hardcoded_users" | head -10)"
    log INFO ""
    ((violations++)) || true
else
    log INFO "✓ No hardcoded user paths found"
fi

# Check for specific developer usernames (only git-tracked files)
log INFO ""
log INFO "Checking for developer usernames..."
dev_usernames=$(git ls-files | grep -E "\.(md|sh|js|json)$" | \
  grep -v '^tests/' | \
  grep -v '^docs/' | \
  grep -v "validate-no-hardcoded-paths.sh" | \
  xargs grep -n "/Users/chris\|/home/chris\|/Users/.*/git/" 2>/dev/null || true)

if [ -n "$dev_usernames" ]; then
    log ERROR "✗ Found developer username in paths:"
    log ERROR "  Occurrences: $(echo "$dev_usernames" | wc -l | tr -d ' ')"
    log INFO ""
    log ERROR "  First 5 occurrences:"
    log ERROR "$(echo "$dev_usernames" | head -5)"
    log INFO ""
    ((violations++)) || true
else
    log INFO "✓ No developer usernames in paths"
fi

# Check for absolute repository paths (only git-tracked files)
log INFO ""
log INFO "Checking for absolute git repository paths..."
git_paths=$(git ls-files | grep -E "\.(md|sh)$" | \
  grep -v '^tests/' | \
  grep -v '^docs/' | \
  grep -v "validate-no-hardcoded-paths.sh" | \
  xargs grep -n "git/claude-octopus\|/claude-octopus/plugin/" 2>/dev/null || true)

if [ -n "$git_paths" ]; then
    log ERROR "✗ Found absolute git repository paths:"
    log ERROR "  Occurrences: $(echo "$git_paths" | wc -l | tr -d ' ')"
    log INFO ""
    ((violations++)) || true
else
    log INFO "✓ No absolute git repository paths"
fi

# Check for hardcoded workspace paths (should be relative or ~/...)
log INFO ""
log INFO "Checking for hardcoded workspace paths..."
workspace_paths=$(grep -rn "\.claude-octopus" \
  --include="*.sh" --include="*.js" \
  --exclude-dir=.git --exclude-dir=tests \
  . 2>/dev/null | \
  grep -v "~/" | \
  grep -v "\${" | \
  grep -v "# " | \
  grep -v "//" || true)

if [ -n "$workspace_paths" ]; then
    log WARN "⚠ Found potential hardcoded workspace paths:"
    log WARN "$(echo "$workspace_paths" | head -5)"
    log INFO ""
    log WARN "  (Check if these should use ~/ or variables)"
else
    log INFO "✓ No hardcoded workspace paths"
fi

log INFO ""
log INFO "======================================"
if [ $violations -eq 0 ]; then
    log INFO "✅ VALIDATION PASSED"
    log INFO "No hardcoded local paths found in deployment files"
    exit 0
else
    log ERROR "❌ VALIDATION FAILED"
    log ERROR "$violations violation(s) found"
    log INFO ""
    log INFO "Fix these issues:"
    log INFO "  1. Replace /Users/username/... with relative paths or ~/"
    log INFO "  2. Replace absolute git paths with relative paths"
    log INFO "  3. Use environment variables for dynamic paths"
    log INFO "  4. Move development docs with paths to .gitignore"
    log INFO ""
    exit 1
fi
