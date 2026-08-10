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
CHANGELOG_LIB="$PROJECT_ROOT/scripts/lib/release-changelog.sh"
CI_LIB="$PROJECT_ROOT/scripts/lib/release-ci.sh"
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

    mkdir -p "$seed/.claude-plugin" "$seed/.agents/plugins"
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

    cat > "$seed/.agents/plugins/marketplace.json" <<'JSON'
{
  "name": "nyldn-plugins",
  "plugins": [
    {
      "name": "claude-octopus",
      "source": {
        "source": "url",
        "url": "https://github.com/nyldn/claude-octopus.git"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Orchestration"
    }
  ]
}
JSON

    git -C "$seed" add .claude-plugin/marketplace.json .agents/plugins/marketplace.json
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

test_release_stages_routines_manifest() {
    test_case "release.sh stages the routines manifest after bumping it"

    local commit_block
    commit_block="$(sed -n '/^echo "2\/8 Committing\.\.\."/,/^git commit /p' "$RELEASE_SCRIPT")"
    if grep -q '\.claude-plugin/routines\.json' <<<"$commit_block"; then
        test_pass
    else
        test_fail "release.sh updates routines.json but omits it from the release commit"
    fi
}

test_release_updates_and_stages_browse_manifest() {
    test_case "release.sh updates and stages the plugin browse manifest"

    local commit_block
    commit_block="$(sed -n '/^echo "2\/8 Committing\.\.\."/,/^git commit /p' "$RELEASE_SCRIPT")"
    if grep -q "plugin_manifest_path = pathlib.Path('.claude-plugin/plugin-manifest.json')" "$RELEASE_SCRIPT" &&
       grep -q '\.claude-plugin/plugin-manifest\.json' <<<"$commit_block"; then
        test_pass
    else
        test_fail "release.sh does not version/count and stage plugin-manifest.json"
    fi
}

test_release_file_updates_are_portable() {
    test_case "release.sh avoids platform-specific sed -i syntax"
    if ! grep -q "sed -i ''" "$RELEASE_SCRIPT"; then
        test_pass
    else
        test_fail "release.sh still contains BSD-only sed -i syntax"
    fi
}

test_release_description_uses_current_summary() {
    test_case "release.sh replaces stale plugin summary and regenerates derived artifacts"

    if grep -q "version, summary = sys.argv\\[1:\\]" "$RELEASE_SCRIPT" &&
       grep -q "p\\['description'\\] = f'v{version}" "$RELEASE_SCRIPT" &&
       grep -q '^make sync$' "$RELEASE_SCRIPT"; then
        test_pass
    else
        test_fail "release.sh does not derive plugin metadata from the current release summary"
    fi
}

test_readme_provider_and_cost_contract() {
    test_case "README defines provider counting and auditable cost assumptions"

    if grep -q 'ten external provider integrations' "$PROJECT_ROOT/README.md" &&
       ! grep -q 'Up to 9 providers' "$PROJECT_ROOT/README.md" &&
       grep -q 'developers.openai.com/api/docs/models/gpt-5.6-sol' "$PROJECT_ROOT/README.md" &&
       grep -q 'ai.google.dev/gemini-api/docs/pricing' "$PROJECT_ROOT/README.md" &&
       grep -q 'docs.perplexity.ai/docs/getting-started/pricing' "$PROJECT_ROOT/README.md" &&
       grep -q 'prompts over 200K' "$PROJECT_ROOT/README.md" &&
       grep -q 'request fee' "$PROJECT_ROOT/README.md"; then
        test_pass
    else
        test_fail "README provider count or pricing assumptions remain ambiguous"
    fi
}

test_marketplace_description_error_uses_logger() {
    test_case "sync-marketplace routes missing descriptions through the logger"
    if grep -q 'log ERROR "description missing in \$PLUGIN_JSON"' "$PROJECT_ROOT/scripts/sync-marketplace.sh"; then
        test_pass
    else
        test_fail "sync-marketplace uses raw output for the missing-description error"
    fi
}

test_release_promotes_unreleased_changelog_notes() {
    test_case "release changelog helper promotes Unreleased notes into version entry"

    local changelog="$TMP_DIR/CHANGELOG.md"
    local unreleased_block version_block

    cat > "$changelog" <<'MD'
# Changelog

## [Unreleased]

### Added

- Add Opus 4.8 routing.

### Changed

- Make council runner-backed by default.

## [9.41.2] - 2026-05-28

### Fixed

- Previous patch release.
MD

    # shellcheck disable=SC1090
    source "$CHANGELOG_LIB"
    octo_release_update_changelog "$changelog" "9.42.0" "2026-06-02" "Release summary" >"$TMP_DIR/octo-release-changelog.out"

    unreleased_block="$(awk '/^## \[Unreleased\]/{flag=1; next} /^## \[9\.42\.0\]/{flag=0} flag {print}' "$changelog")"
    version_block="$(awk '/^## \[9\.42\.0\]/{flag=1; next} /^## \[9\.41\.2\]/{flag=0} flag {print}' "$changelog")"

    if ! grep -q "Add Opus 4.8 routing" <<<"$unreleased_block" &&
       grep -q "Add Opus 4.8 routing" <<<"$version_block" &&
       grep -q "Make council runner-backed" <<<"$version_block" &&
       grep -q "Previous patch release" "$changelog"; then
        test_pass
    else
        test_fail "unreleased notes were not moved into the 9.42.0 entry"
    fi
}

test_release_ci_parser_matches_exact_aggregate_checks() {
    test_case "release CI parser matches exact aggregate check names"

    local checks_json smoke unit integ smoke_matrix missing
    checks_json='[
        {"name":"Smoke Tests (${{ matrix.os }})","state":"SKIPPED"},
        {"name":"Smoke Tests","state":"SUCCESS"},
        {"name":"Unit Tests (${{ matrix.os }})","state":"SKIPPED"},
        {"name":"Unit Tests","state":"SUCCESS"},
        {"name":"Integration Tests (full)","state":"SKIPPED"},
        {"name":"Integration Tests","state":"SUCCESS"},
        {"name":"CodeRabbit","state":"PENDING"}
    ]'

    # shellcheck disable=SC1090
    source "$CI_LIB"
    smoke="$(octo_pr_check_state "$checks_json" "Smoke Tests")"
    unit="$(octo_pr_check_state "$checks_json" "Unit Tests")"
    integ="$(octo_pr_check_state "$checks_json" "Integration Tests")"
    smoke_matrix="$(octo_pr_check_state "$checks_json" 'Smoke Tests (${{ matrix.os }})')"
    missing="$(octo_pr_check_state "$checks_json" "Required Future Check")"

    if [[ "$smoke" == "pass" &&
          "$unit" == "pass" &&
          "$integ" == "pass" &&
          "$smoke_matrix" == "skip" &&
          "$missing" == "pending" ]]; then
        test_pass
    else
        test_fail "expected exact aggregate checks to pass without matching matrix checks"
    fi
}

test_shared_marketplace_sync_updates_only_octo() {
    local remote="$TMP_DIR/plugins.git"
    local seed="$TMP_DIR/seed"
    local work="$TMP_DIR/work"
    local stale_output="$TMP_DIR/octo-shared-marketplace-check.out"
    local sync_output="$TMP_DIR/octo-shared-marketplace-sync.out"
    local check_output="$TMP_DIR/octo-shared-marketplace-check2.out"
    local drift_output="$TMP_DIR/octo-shared-marketplace-codex-drift.out"
    local duplicate_output="$TMP_DIR/octo-shared-marketplace-codex-duplicate.out"
    local source_output="$TMP_DIR/octo-shared-marketplace-codex-source.out"
    create_shared_marketplace_remote "$remote" "$seed"

    test_case "--check fails when shared octo entry is stale"
    if "$SYNC_SCRIPT" --repo "$remote" --workdir "$work" --check >"$stale_output" 2>&1; then
        test_fail "expected stale shared marketplace check to fail"
    else
        test_pass
    fi

    test_case "sync updates octo entry and pushes it to the shared marketplace"
    if "$SYNC_SCRIPT" --repo "$remote" --workdir "$work" >"$sync_output" 2>&1; then
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
        test_fail "sync command failed; output: $(cat "$sync_output" 2>/dev/null)"
    fi

    test_case "--check passes after sync"
    if "$SYNC_SCRIPT" --repo "$remote" --workdir "$work" --check >"$check_output" 2>&1 &&
       grep -q 'shared Codex marketplace selector is compatible (claude-octopus)' "$check_output"; then
        test_pass
    else
        test_fail "expected synced Claude entry and stable Codex selector to pass; output: $(cat "$check_output" 2>/dev/null)"
    fi

    test_case "--check rejects a renamed Codex marketplace selector"
    jq '(.plugins[] | select(.name == "claude-octopus")).name = "octo"' \
        "$work/.agents/plugins/marketplace.json" > "$work/.agents/plugins/marketplace.json.tmp"
    mv "$work/.agents/plugins/marketplace.json.tmp" "$work/.agents/plugins/marketplace.json"
    if "$SYNC_SCRIPT" --repo "$remote" --workdir "$work" --check >"$drift_output" 2>&1; then
        test_fail "expected renamed Codex selector to fail compatibility validation"
    elif grep -q "shared Codex marketplace must have exactly one 'claude-octopus' plugin entry" "$drift_output"; then
        test_pass
    else
        test_fail "expected Codex selector mismatch diagnostic; output: $(cat "$drift_output" 2>/dev/null)"
    fi

    test_case "--check rejects duplicate Codex marketplace selectors"
    git -C "$work" show HEAD:.agents/plugins/marketplace.json > "$work/.agents/plugins/marketplace.json"
    jq '.plugins += [.plugins[] | select(.name == "claude-octopus")]' \
        "$work/.agents/plugins/marketplace.json" > "$work/.agents/plugins/marketplace.json.tmp"
    mv "$work/.agents/plugins/marketplace.json.tmp" "$work/.agents/plugins/marketplace.json"
    if "$SYNC_SCRIPT" --repo "$remote" --workdir "$work" --check >"$duplicate_output" 2>&1; then
        test_fail "expected duplicate Codex selectors to fail compatibility validation"
    elif grep -q "shared Codex marketplace must have exactly one 'claude-octopus' plugin entry" "$duplicate_output"; then
        test_pass
    else
        test_fail "expected duplicate Codex selector diagnostic; output: $(cat "$duplicate_output" 2>/dev/null)"
    fi

    test_case "--check rejects an invalid Codex marketplace source URL"
    git -C "$work" show HEAD:.agents/plugins/marketplace.json > "$work/.agents/plugins/marketplace.json"
    jq '(.plugins[] | select(.name == "claude-octopus").source.url) = "https://example.com/not-octopus.git"' \
        "$work/.agents/plugins/marketplace.json" > "$work/.agents/plugins/marketplace.json.tmp"
    mv "$work/.agents/plugins/marketplace.json.tmp" "$work/.agents/plugins/marketplace.json"
    if "$SYNC_SCRIPT" --repo "$remote" --workdir "$work" --check >"$source_output" 2>&1; then
        test_fail "expected invalid Codex source URL to fail compatibility validation"
    elif grep -q "shared Codex marketplace 'claude-octopus' source is invalid: https://example.com/not-octopus.git" "$source_output"; then
        test_pass
    else
        test_fail "expected invalid Codex source diagnostic; output: $(cat "$source_output" 2>/dev/null)"
    fi
}

test_sync_script_exists
test_release_script_invokes_shared_marketplace_sync
test_release_stages_routines_manifest
test_release_updates_and_stages_browse_manifest
test_release_file_updates_are_portable
test_release_description_uses_current_summary
test_readme_provider_and_cost_contract
test_marketplace_description_error_uses_logger
test_release_promotes_unreleased_changelog_notes
test_release_ci_parser_matches_exact_aggregate_checks
test_shared_marketplace_sync_updates_only_octo

test_summary
