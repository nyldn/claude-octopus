#!/usr/bin/env bash
# check-vendor-updates.sh — Verify vendor submodules are healthy and check for updates
#
# Checks:
# 1. All vendor submodules are initialized and present
# 2. Required files exist in each vendor (entry points, data)
# 3. No new external dependencies introduced (Python stdlib only for ui-ux-pro-max)
# 4. Upstream has new commits (informational — does not auto-update)
# 5. Feature compatibility with main codebase
#
# Modes:
#   ./scripts/check-vendor-updates.sh           # Full check with upstream query
#   ./scripts/check-vendor-updates.sh --local   # Local-only checks (no network)
#   ./scripts/check-vendor-updates.sh --ci      # CI mode: exit non-zero on any failure
#
# Exit codes:
#   0 = All checks pass
#   1 = Failure (missing files, broken deps, etc.)
#   2 = Updates available (--ci mode only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
WARN=0
MODE="${1:-full}"

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }
warn() { echo "  WARN: $1"; WARN=$((WARN + 1)); }

echo "=== Vendor Submodule Health Check ==="
echo "Mode: ${MODE}"
echo ""

# ── 1. Submodule initialization ──────────────────────────────────────────────

echo "1. Submodule Initialization"

if [ ! -f "$PLUGIN_ROOT/.gitmodules" ]; then
    echo "  No .gitmodules found — no vendor submodules configured."
    echo ""
    echo "Summary: 0 pass, 0 fail, 0 warn"
    exit 0
fi

# Parse .gitmodules for submodule paths
SUBMODULE_PATHS=()
while IFS= read -r line; do
    path=$(echo "$line" | sed 's/.*path = //')
    SUBMODULE_PATHS+=("$path")
done < <(grep 'path = ' "$PLUGIN_ROOT/.gitmodules")

if [ ${#SUBMODULE_PATHS[@]} -eq 0 ]; then
    echo "  No submodule paths found in .gitmodules"
    exit 0
fi

for subpath in "${SUBMODULE_PATHS[@]}"; do
    full_path="$PLUGIN_ROOT/$subpath"
    if [ -d "$full_path" ] && [ "$(ls -A "$full_path" 2>/dev/null)" ]; then
        pass "$subpath initialized"
    else
        fail "$subpath not initialized (run: git submodule update --init $subpath)"
    fi
done

echo ""

# ── 2. Required file checks per vendor ───────────────────────────────────────

echo "2. Required Files"

# ui-ux-pro-max-skill checks
UX_VENDOR="$PLUGIN_ROOT/vendors/ui-ux-pro-max-skill"
if [ -d "$UX_VENDOR" ] && [ "$(ls -A "$UX_VENDOR" 2>/dev/null)" ]; then
    # Entry point
    if [ -f "$UX_VENDOR/src/ui-ux-pro-max/scripts/search.py" ]; then
        pass "ui-ux-pro-max: search.py entry point exists"
    else
        fail "ui-ux-pro-max: search.py missing"
    fi

    # Core module
    if [ -f "$UX_VENDOR/src/ui-ux-pro-max/scripts/core.py" ]; then
        pass "ui-ux-pro-max: core.py module exists"
    else
        fail "ui-ux-pro-max: core.py missing"
    fi

    # Design system module
    if [ -f "$UX_VENDOR/src/ui-ux-pro-max/scripts/design_system.py" ]; then
        pass "ui-ux-pro-max: design_system.py module exists"
    else
        fail "ui-ux-pro-max: design_system.py missing"
    fi

    # Data files (at minimum styles and colors)
    for csv_file in styles.csv colors.csv typography.csv products.csv ux-guidelines.csv; do
        if [ -f "$UX_VENDOR/src/ui-ux-pro-max/data/$csv_file" ]; then
            pass "ui-ux-pro-max: data/$csv_file exists"
        else
            fail "ui-ux-pro-max: data/$csv_file missing"
        fi
    done

    # License
    if [ -f "$UX_VENDOR/LICENSE" ]; then
        pass "ui-ux-pro-max: LICENSE file present"
    else
        warn "ui-ux-pro-max: LICENSE file missing"
    fi
fi

echo ""

# ── 3. Dependency check (no external Python packages) ────────────────────────

echo "3. Dependency Audit"

if [ -d "$UX_VENDOR" ] && [ "$(ls -A "$UX_VENDOR" 2>/dev/null)" ]; then
    # Check Python files for non-stdlib imports
    BANNED_IMPORTS=""
    for pyfile in "$UX_VENDOR"/src/ui-ux-pro-max/scripts/*.py; do
        [ -f "$pyfile" ] || continue
        # Extract import lines, filter out stdlib and relative imports
        while IFS= read -r imp; do
            module=$(echo "$imp" | sed -E 's/^(import|from) +([a-zA-Z0-9_]+).*/\2/')
            # Python stdlib modules used by the project
            case "$module" in
                csv|re|math|argparse|sys|io|os|pathlib|json|collections|functools|textwrap|datetime|hashlib|typing|abc|dataclasses|enum|copy|itertools|string|unicodedata|difflib)
                    ;; # stdlib — OK
                core|design_system|search)
                    ;; # internal — OK
                *)
                    BANNED_IMPORTS="${BANNED_IMPORTS}  ${pyfile##*/}: imports '${module}'\n"
                    ;;
            esac
        done < <(grep -E '^(import |from )' "$pyfile" 2>/dev/null | grep -v '^\s*#')
    done

    if [ -z "$BANNED_IMPORTS" ]; then
        pass "ui-ux-pro-max: no external Python dependencies"
    else
        fail "ui-ux-pro-max: external Python imports detected:"
        echo -e "$BANNED_IMPORTS" >&2
    fi

    # Verify python3 can load the modules
    if command -v python3 &>/dev/null; then
        if python3 -c "import csv, re, math, argparse, sys, io" 2>/dev/null; then
            pass "python3 stdlib modules available"
        else
            fail "python3 stdlib modules missing"
        fi
    else
        warn "python3 not installed — design intelligence will be unavailable"
    fi
fi

echo ""

# ── 4. Upstream update check (skip in --local mode) ──────────────────────────

UPDATES_AVAILABLE=0

if [ "$MODE" != "--local" ]; then
    echo "4. Upstream Update Check"

    for subpath in "${SUBMODULE_PATHS[@]}"; do
        full_path="$PLUGIN_ROOT/$subpath"
        [ -d "$full_path" ] && [ "$(ls -A "$full_path" 2>/dev/null)" ] || continue

        # Get current pinned commit
        pinned_commit=$(cd "$full_path" && git rev-parse HEAD 2>/dev/null)
        short_pinned=$(echo "$pinned_commit" | cut -c1-7)

        # Fetch latest from remote (timeout after 10s)
        if timeout 10 git -C "$full_path" fetch origin 2>/dev/null; then
            latest_commit=$(git -C "$full_path" rev-parse origin/main 2>/dev/null || git -C "$full_path" rev-parse origin/master 2>/dev/null || echo "")

            if [ -z "$latest_commit" ]; then
                warn "$subpath: could not determine upstream HEAD"
            elif [ "$pinned_commit" = "$latest_commit" ]; then
                pass "$subpath: up to date ($short_pinned)"
            else
                short_latest=$(echo "$latest_commit" | cut -c1-7)
                new_commits=$(git -C "$full_path" rev-list "$pinned_commit..origin/main" 2>/dev/null | wc -l | tr -d ' ')
                warn "$subpath: ${new_commits} new commits upstream (pinned: $short_pinned, latest: $short_latest)"
                UPDATES_AVAILABLE=1

                # Show what changed
                echo "    Recent upstream commits:"
                git -C "$full_path" log --oneline "$pinned_commit..origin/main" 2>/dev/null | head -5 | sed 's/^/      /'
                remaining=$((new_commits - 5))
                [ $remaining -gt 0 ] && echo "      ... and $remaining more"
                echo ""

                # Check for breaking changes (new imports, deleted files)
                changed_files=$(git -C "$full_path" diff --name-only "$pinned_commit..origin/main" 2>/dev/null)
                if echo "$changed_files" | grep -q 'scripts/search.py\|scripts/core.py'; then
                    warn "  Core search files changed — review before updating"
                fi
                if echo "$changed_files" | grep -q 'requirements\|setup.py\|pyproject.toml'; then
                    warn "  Dependency files changed — audit for new external packages"
                fi
            fi
        else
            warn "$subpath: could not fetch upstream (network timeout)"
        fi
    done
else
    echo "4. Upstream Update Check (skipped — local mode)"
fi

echo ""

# ── 5. Feature compatibility with main codebase ─────────────────────────────

echo "5. Feature Compatibility"

# Check that persona references the correct search.py path
PERSONA_FILE="$PLUGIN_ROOT/agents/personas/ui-ux-designer.md"
if [ -f "$PERSONA_FILE" ]; then
    if grep -q 'vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py' "$PERSONA_FILE"; then
        pass "ui-ux-designer persona: search.py path correct"
    else
        fail "ui-ux-designer persona: search.py path mismatch"
    fi
else
    warn "ui-ux-designer persona not found"
fi

# Check that skill references the correct path
SKILL_FILE="$PLUGIN_ROOT/.claude/skills/skill-ui-ux-design.md"
if [ -f "$SKILL_FILE" ]; then
    if grep -q 'vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py' "$SKILL_FILE"; then
        pass "ui-ux-design skill: search.py path correct"
    else
        fail "ui-ux-design skill: search.py path mismatch"
    fi
else
    warn "ui-ux-design skill not found"
fi

# Check that command file exists
CMD_FILE="$PLUGIN_ROOT/.claude/commands/ui-ux-design.md"
if [ -f "$CMD_FILE" ]; then
    pass "ui-ux-design command file exists"
else
    warn "ui-ux-design command file not found"
fi

# Check routing.sh has ui-ux-designer pattern
ROUTING_FILE="$PLUGIN_ROOT/scripts/lib/routing.sh"
if [ -f "$ROUTING_FILE" ]; then
    if grep -q 'ui-ux-designer' "$ROUTING_FILE"; then
        pass "routing.sh: ui-ux-designer pattern present"
    else
        fail "routing.sh: ui-ux-designer pattern missing"
    fi
fi

# Verify search.py actually runs
if [ -f "$UX_VENDOR/src/ui-ux-pro-max/scripts/search.py" ] && command -v python3 &>/dev/null; then
    if python3 "$UX_VENDOR/src/ui-ux-pro-max/scripts/search.py" "test" --domain style -n 1 >/dev/null 2>&1; then
        pass "search.py: smoke test passed"
    else
        fail "search.py: smoke test failed"
    fi
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────

echo "=== Summary ==="
echo "  $PASS passed, $FAIL failed, $WARN warnings"

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "Action required: fix failures before releasing."
    exit 1
fi

if [ "$MODE" = "--ci" ] && [ $UPDATES_AVAILABLE -gt 0 ]; then
    echo ""
    echo "Vendor updates available. Review and update submodule references if appropriate."
    exit 2
fi

echo ""
echo "All checks passed."
exit 0
