#!/bin/bash
set -euo pipefail

# tests/unit/test-shared-marketplace-sync.sh
# Regression coverage for the shared nyldn/plugins marketplace release sync.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Shared Marketplace Sync"

SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync-shared-marketplace.sh"
RELEASE_SCRIPT="$PROJECT_ROOT/scripts/release.sh"
LOCAL_MARKETPLACE="$PROJECT_ROOT/.claude-plugin/marketplace.json"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-shared-marketplace-test.XXXXXX")"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

local_octo_version() {
    jq -r '.plugins[] | select(.name == "octo") | .version' "$LOCAL_MARKETPLACE"
}

local_octo_description() {
    jq -r '.plugins[] | select(.name == "octo") | .description' "$LOCAL_MARKETPLACE"
}

create_shared_marketplace_remote() {
    local remote="$1"
    local seed="$2"

    git init -q --bare "$remote"
    git init -q -b main "$seed"
    git -C "$seed" config user.name "Octopus Test"
    git -C "$seed" config user.email "octopus-test@example.com"

    mkdir -p "$seed/.claude-plugin"
    cat > "$seed/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "nyldn-plugins",
  "owner": {
    "name": "nyldn",
    "url": "https://github.com/nyldn"
  },
  "metadata": {
    "description": "nyldn plugins for Claude Code workflows.",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "octo",
      "source": {
        "source": "url",
        "url": "https://github.com/nyldn/claude-octopus.git"
      },
      "description": "v9.41.0 - stale octopus marketplace entry",
      "version": "9.41.0",
      "author": {
        "name": "nyldn",
        "url": "https://github.com/nyldn"
      },
      "repository": "https://github.com/nyldn/claude-octopus",
      "homepage": "https://github.com/nyldn/claude-octopus",
      "license": "MIT",
      "keywords": [
        "multi-llm"
      ],
      "category": "orchestration"
    },
    {
      "name": "img",
      "source": {
        "source": "url",
        "url": "https://github.com/nyldn/img.git"
      },
      "description": "Generate and edit images.",
      "version": "0.1.18",
      "author": {
        "name": "nyldn",
        "url": "https://github.com/nyldn"
      },
      "repository": "https://github.com/nyldn/img",
      "homepage": "https://github.com/nyldn/img",
      "license": "MIT",
      "keywords": [
        "image-generation"
      ],
      "category": "creative"
    }
  ]
}
JSON

    git -C "$seed" add .claude-plugin/marketplace.json
    git -C "$seed" commit -q -m "seed shared marketplace"
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q origin main
}

test_sync_script_exists() {
    test_case "sync-shared-marketplace.sh exists and is executable"
    if [[ -x "$SYNC_SCRIPT" ]]; then
        test_pass
    else
        test_fail "missing executable script at $SYNC_SCRIPT"
    fi
}

test_release_script_invokes_shared_marketplace_sync() {
    test_case "release.sh syncs shared marketplace after creating the GitHub release"
    if grep -q "sync-shared-marketplace.sh" "$RELEASE_SCRIPT"; then
        test_pass
    else
        test_fail "release.sh does not invoke scripts/sync-shared-marketplace.sh"
    fi
}

test_shared_marketplace_sync_updates_only_octo() {
    local remote="$TMP_DIR/plugins.git"
    local seed="$TMP_DIR/seed"
    local work="$TMP_DIR/work"
    create_shared_marketplace_remote "$remote" "$seed"

    test_case "--check fails when shared octo entry is stale"
    if "$SYNC_SCRIPT" --repo "$remote" --workdir "$work" --check >/tmp/octo-shared-marketplace-check.out 2>&1; then
        test_fail "expected stale shared marketplace check to fail"
    else
        test_pass
    fi

    test_case "sync updates octo entry and pushes it to the shared marketplace"
    if "$SYNC_SCRIPT" --repo "$remote" --workdir "$work" >/tmp/octo-shared-marketplace-sync.out 2>&1; then
        local expected_version expected_desc got_version got_desc img_version metadata_version
        expected_version="$(local_octo_version)"
        expected_desc="$(local_octo_description)"
        got_version="$(jq -r '.plugins[] | select(.name == "octo") | .version' "$work/.claude-plugin/marketplace.json")"
        got_desc="$(jq -r '.plugins[] | select(.name == "octo") | .description' "$work/.claude-plugin/marketplace.json")"
        img_version="$(jq -r '.plugins[] | select(.name == "img") | .version' "$work/.claude-plugin/marketplace.json")"
        metadata_version="$(jq -r '.metadata.version' "$work/.claude-plugin/marketplace.json")"
        if [[ "$got_version" == "$expected_version" && "$got_desc" == "$expected_desc" && "$img_version" == "0.1.18" && "$metadata_version" == "1.0.0" ]]; then
            test_pass
        else
            test_fail "expected octo=$expected_version and img=0.1.18/metadata=1.0.0, got octo=$got_version img=$img_version metadata=$metadata_version"
        fi
    else
        test_fail "sync command failed; output: $(cat /tmp/octo-shared-marketplace-sync.out 2>/dev/null)"
    fi

    test_case "--check passes after sync"
    if "$SYNC_SCRIPT" --repo "$remote" --workdir "$work" --check >/tmp/octo-shared-marketplace-check2.out 2>&1; then
        test_pass
    else
        test_fail "expected synced shared marketplace check to pass; output: $(cat /tmp/octo-shared-marketplace-check2.out 2>/dev/null)"
    fi
}

test_sync_script_exists
test_release_script_invokes_shared_marketplace_sync
test_shared_marketplace_sync_updates_only_octo

test_summary
