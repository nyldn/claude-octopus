#!/usr/bin/env bash
# check-vendor-updates.sh — Verify vendored dependencies are healthy and check for updates
#
# Vendors are plain-file copies (not submodules, see #253). Each vendor directory
# carries a VENDOR.json manifest recording the upstream repo and the vendored tag.
#
# Checks:
# 1. VENDOR.json manifest present and parseable for each vendor
# 2. Required files exist in each vendor (entry points, data)
# 3. No new external dependencies introduced (Python stdlib only for ui-ux-pro-max)
# 4. Upstream has a newer release tag (informational — does not auto-update)
# 5. Feature compatibility with main codebase (path references still valid)
#
# Modes:
#   ./scripts/check-vendor-updates.sh           # Full check with upstream query
#   ./scripts/check-vendor-updates.sh --local   # Local-only checks (no network)
#   ./scripts/check-vendor-updates.sh --ci      # CI mode: exit 2 when updates are available
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

echo "=== Vendor Health Check ==="
echo "Mode: ${MODE}"
echo ""

VENDORS_DIR="$PLUGIN_ROOT/vendors"
UPDATES_AVAILABLE=0

if [ ! -d "$VENDORS_DIR" ]; then
    echo "No vendors/ directory — nothing to check."
    exit 0
fi

# ── 1. Manifest checks ───────────────────────────────────────────────────────

echo "1. Vendor Manifests"

VENDOR_DIRS=()
while IFS= read -r -d '' d; do
    VENDOR_DIRS+=("$d")
done < <(find "$VENDORS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

if [ ${#VENDOR_DIRS[@]} -eq 0 ]; then
    echo "  No vendor directories found."
    exit 0
fi

for vdir in "${VENDOR_DIRS[@]}"; do
    vname="${vdir##*/}"
    manifest="$vdir/VENDOR.json"
    if [ ! -f "$manifest" ]; then
        fail "$vname: VENDOR.json manifest missing"
        continue
    fi
    if command -v python3 &>/dev/null; then
        if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['upstream'] and d['tag']" "$manifest" 2>/dev/null; then
            tag=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['tag'])" "$manifest")
            pass "$vname: manifest valid (vendored tag: $tag)"
        else
            fail "$vname: VENDOR.json unparseable or missing upstream/tag fields"
        fi
    else
        warn "$vname: python3 unavailable — skipping manifest parse"
    fi
done

echo ""

# ── 2. Required file checks per vendor ───────────────────────────────────────

echo "2. Required Files"

UX_VENDOR="$VENDORS_DIR/ui-ux-pro-max-skill"
if [ -d "$UX_VENDOR" ]; then
    for f in scripts/search.py scripts/core.py scripts/design_system.py; do
        if [ -f "$UX_VENDOR/src/ui-ux-pro-max/$f" ]; then
            pass "ui-ux-pro-max: $f exists"
        else
            fail "ui-ux-pro-max: $f missing"
        fi
    done

    for csv_file in styles.csv colors.csv typography.csv products.csv ux-guidelines.csv; do
        if [ -f "$UX_VENDOR/src/ui-ux-pro-max/data/$csv_file" ]; then
            pass "ui-ux-pro-max: data/$csv_file exists"
        else
            fail "ui-ux-pro-max: data/$csv_file missing"
        fi
    done

    if [ -f "$UX_VENDOR/LICENSE" ]; then
        pass "ui-ux-pro-max: LICENSE file present"
    else
        fail "ui-ux-pro-max: LICENSE file missing (required for redistribution)"
    fi
fi

echo ""

# ── 3. Dependency check (no external Python packages) ────────────────────────

echo "3. Dependency Audit"

if [ -d "$UX_VENDOR" ]; then
    BANNED_IMPORTS=""
    for pyfile in "$UX_VENDOR"/src/ui-ux-pro-max/scripts/*.py; do
        [ -f "$pyfile" ] || continue
        while IFS= read -r imp; do
            module=$(echo "$imp" | sed -E 's/^(import|from) +([a-zA-Z0-9_]+).*/\2/')
            case "$module" in
                csv|re|math|argparse|sys|io|os|pathlib|json|collections|functools|textwrap|datetime|hashlib|typing|abc|dataclasses|enum|copy|itertools|string|unicodedata|difflib|shutil|unittest|tempfile)
                    ;; # stdlib — OK
                core|design_system|search|persist|dials)
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

if [ "$MODE" != "--local" ]; then
    echo "4. Upstream Update Check"

    for vdir in "${VENDOR_DIRS[@]}"; do
        vname="${vdir##*/}"
        manifest="$vdir/VENDOR.json"
        [ -f "$manifest" ] || continue
        command -v python3 &>/dev/null || { warn "$vname: python3 unavailable — skipping"; continue; }

        upstream=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['upstream'])" "$manifest" 2>/dev/null || echo "")
        pinned_tag=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['tag'])" "$manifest" 2>/dev/null || echo "")
        [ -n "$upstream" ] && [ -n "$pinned_tag" ] || { warn "$vname: manifest incomplete"; continue; }

        # owner/repo from the upstream URL
        slug=$(echo "$upstream" | sed -E 's#https?://github.com/##; s#/$##; s#\.git$##')

        latest_tag=""
        if command -v gh &>/dev/null; then
            latest_tag=$(gh api "repos/$slug/releases/latest" -q .tag_name 2>/dev/null || echo "")
        fi
        if [ -z "$latest_tag" ] && command -v curl &>/dev/null; then
            latest_tag=$(curl -fsSL --max-time 10 "https://api.github.com/repos/$slug/releases/latest" 2>/dev/null |
                python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || echo "")
        fi

        if [ -z "$latest_tag" ]; then
            warn "$vname: could not determine latest upstream release (network/auth)"
        elif [ "$latest_tag" = "$pinned_tag" ]; then
            pass "$vname: up to date ($pinned_tag)"
        else
            warn "$vname: update available (vendored: $pinned_tag, latest: $latest_tag) — see $upstream/releases"
            UPDATES_AVAILABLE=1
        fi
    done
else
    echo "4. Upstream Update Check (skipped — local mode)"
fi

echo ""

# ── 5. Feature compatibility with main codebase ─────────────────────────────

echo "5. Feature Compatibility"

# All first-party references to the vendored search.py must use the stable src/ path
REF_PATTERN='vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py'
for ref_file in \
    "$PLUGIN_ROOT/agents/personas/ui-ux-designer.md" \
    "$PLUGIN_ROOT/skills/octopus-ui-ux-design/SKILL.md"; do
    [ -f "$ref_file" ] || { warn "reference file missing: ${ref_file#"$PLUGIN_ROOT"/}"; continue; }
    if grep -q "$REF_PATTERN" "$ref_file"; then
        pass "${ref_file#"$PLUGIN_ROOT"/}: search.py path correct"
    else
        fail "${ref_file#"$PLUGIN_ROOT"/}: search.py path mismatch"
    fi
done

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
    echo "Vendor updates available. Refresh the vendored copy and update VENDOR.json."
    exit 2
fi

echo ""
echo "All checks passed."
exit 0
