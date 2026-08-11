#!/bin/bash
set -euo pipefail

# tests/unit/test-shared-marketplace-sync.sh
# Regression coverage for the shared nyldn/plugins marketplace release sync.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Shared Marketplace Sync"

SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync-shared-marketplace.sh"
LOCAL_SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync-marketplace.sh"
RELEASE_SCRIPT="$PROJECT_ROOT/scripts/release.sh"
CHANGELOG_LIB="$PROJECT_ROOT/scripts/lib/release-changelog.sh"
CI_LIB="$PROJECT_ROOT/scripts/lib/release-ci.sh"
LOCAL_MARKETPLACE="$PROJECT_ROOT/.claude-plugin/marketplace.json"

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
       grep -q 'docs.perplexity.ai/docs/getting-started/pricing' "$PROJECT_ROOT/README.md" &&
       grep -q 'Antigravity.*bill nothing extra' "$PROJECT_ROOT/README.md" &&
       grep -q 'Long-context and provider-specific rate rules' "$PROJECT_ROOT/README.md" &&
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

test_local_marketplace_sync_aligns_all_versions() {
    test_case "sync-marketplace rejects and repairs stale marketplace version fields"

    local fixture="$TEST_TMP_DIR/local-sync"
    local check_before_rc=0
    local check_after_rc=0
    local check_entry_rc=0
    local check_entry_repaired_rc=0
    local plugin_version metadata_version stale_entry_version
    local repaired_metadata_version repaired_entry_version

    mkdir -p "$fixture/scripts" "$fixture/.claude-plugin" "$fixture/agents/personas"
    cp "$LOCAL_SYNC_SCRIPT" "$fixture/scripts/sync-marketplace.sh"

    cat > "$fixture/.claude-plugin/plugin.json" <<'JSON'
{
  "version": "9.99.0",
  "description": "v9.99.0 — Fixture release. Run /octo:setup.",
  "keywords": ["fixture"],
  "skills": ["./skills/fixture"],
  "commands": ["./commands/fixture"]
}
JSON

    cat > "$fixture/.claude-plugin/marketplace.json" <<'JSON'
{
  "metadata": {"version": "1.0.0"},
  "plugins": [
    {
      "name": "octo",
      "description": "v9.99.0 - Fixture release. 0 personas, 1 commands, 1 skills. Run /octo:setup.",
      "version": "9.99.0",
      "keywords": ["fixture"]
    }
  ]
}
JSON

    bash "$fixture/scripts/sync-marketplace.sh" --check > "$TEST_TMP_DIR/local-sync-check-before.out" 2>&1 || check_before_rc=$?
    bash "$fixture/scripts/sync-marketplace.sh" > "$TEST_TMP_DIR/local-sync-update.out" 2>&1
    bash "$fixture/scripts/sync-marketplace.sh" --check > "$TEST_TMP_DIR/local-sync-check-after.out" 2>&1 || check_after_rc=$?

    jq '(.plugins[] | select(.name == "octo") | .version) = "1.0.0"' \
        "$fixture/.claude-plugin/marketplace.json" > "$TEST_TMP_DIR/local-sync-entry-stale.json"
    mv "$TEST_TMP_DIR/local-sync-entry-stale.json" "$fixture/.claude-plugin/marketplace.json"
    bash "$fixture/scripts/sync-marketplace.sh" --check > "$TEST_TMP_DIR/local-sync-check-entry.out" 2>&1 || check_entry_rc=$?

    plugin_version="$(jq -r '.version' "$fixture/.claude-plugin/plugin.json")"
    metadata_version="$(jq -r '.metadata.version' "$fixture/.claude-plugin/marketplace.json")"
    stale_entry_version="$(jq -r '.plugins[] | select(.name == "octo") | .version' "$fixture/.claude-plugin/marketplace.json")"

    bash "$fixture/scripts/sync-marketplace.sh" > "$TEST_TMP_DIR/local-sync-entry-repair.out" 2>&1
    bash "$fixture/scripts/sync-marketplace.sh" --check > "$TEST_TMP_DIR/local-sync-check-entry-repaired.out" 2>&1 || check_entry_repaired_rc=$?
    repaired_metadata_version="$(jq -r '.metadata.version' "$fixture/.claude-plugin/marketplace.json")"
    repaired_entry_version="$(jq -r '.plugins[] | select(.name == "octo") | .version' "$fixture/.claude-plugin/marketplace.json")"

    if [[ "$check_before_rc" -ne 0 &&
          "$check_after_rc" -eq 0 &&
          "$check_entry_rc" -ne 0 &&
          "$check_entry_repaired_rc" -eq 0 &&
          "$metadata_version" == "$plugin_version" &&
          "$stale_entry_version" != "$plugin_version" &&
          "$repaired_metadata_version" == "$plugin_version" &&
          "$repaired_entry_version" == "$plugin_version" ]] &&
       grep -Fqx "[WARN] Plugin version: $stale_entry_version (expected $plugin_version)" \
           "$TEST_TMP_DIR/local-sync-check-entry.out"; then
        test_pass
    else
        test_fail "expected independent entry-version rejection and repair; before=$check_before_rc after=$check_after_rc entry_check=$check_entry_rc entry_repaired=$check_entry_repaired_rc plugin=$plugin_version metadata=$metadata_version stale_entry=$stale_entry_version repaired_metadata=$repaired_metadata_version repaired_entry=$repaired_entry_version"
    fi
}

test_release_promotes_unreleased_changelog_notes() {
    test_case "release changelog helper promotes Unreleased notes into version entry"

    local changelog="$TEST_TMP_DIR/CHANGELOG.md"
    local release_version="9.42.0"
    local release_date="2026-06-02"
    local expected_header="## [${release_version}] - ${release_date}"
    local unreleased_block version_block

    cat > "$changelog" <<'MD'
# Changelog

## [Unreleased]

### Added

- Add Opus 4.8 routing.

### Changed

- Make council runner-backed by default.

      preserve this indented example

## [9.41.2] - 2026-05-28

### Fixed

- Previous patch release.
MD

    # shellcheck disable=SC1090
    source "$CHANGELOG_LIB"
    octo_release_update_changelog "$changelog" "$release_version" "$release_date" "Release summary" >"$TEST_TMP_DIR/octo-release-changelog.out"

    unreleased_block="$(awk '$0 == "## [Unreleased]" {flag=1; next} /^## \[/ && flag {flag=0} flag {print}' "$changelog")"
    version_block="$(awk -v heading="$expected_header" '$0 == heading {flag=1; next} /^## \[/ && flag {flag=0} flag {print}' "$changelog")"

    local boundary_blank_lines
    boundary_blank_lines="$(awk -v heading="$expected_header" '
        $0 == heading { in_version = 1; next }
        in_version && /^## \[/ { print blank_lines; exit }
        in_version && $0 == "" { blank_lines++; next }
        in_version { blank_lines = 0 }
    ' "$changelog")"

    if ! grep -Fqx -- "- Add Opus 4.8 routing." <<<"$unreleased_block" &&
       grep -Fqx -- "## [Unreleased]" "$changelog" &&
       ! grep -q '[^[:space:]]' <<<"$unreleased_block" &&
       grep -Fqx -- "- Add Opus 4.8 routing." <<<"$version_block" &&
       grep -Fqx -- "- Make council runner-backed by default." <<<"$version_block" &&
       ! grep -Fqx -- "      preserve this indented example" <<<"$unreleased_block" &&
       grep -Fqx -- "      preserve this indented example" <<<"$version_block" &&
       [[ "$boundary_blank_lines" == "1" ]] &&
       python3 -c 'from pathlib import Path; import sys; text = Path(sys.argv[1]).read_text(); header = sys.argv[2]; raise SystemExit(0 if f"{header}\n\n### Added" in text and f"{header}\n\n\n" not in text else 1)' "$changelog" "$expected_header" &&
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
    local remote="$TEST_TMP_DIR/plugins.git"
    local seed="$TEST_TMP_DIR/seed"
    local work="$TEST_TMP_DIR/work"
    local stale_output="$TEST_TMP_DIR/octo-shared-marketplace-check.out"
    local sync_output="$TEST_TMP_DIR/octo-shared-marketplace-sync.out"
    local check_output="$TEST_TMP_DIR/octo-shared-marketplace-check2.out"
    local drift_output="$TEST_TMP_DIR/octo-shared-marketplace-codex-drift.out"
    local duplicate_output="$TEST_TMP_DIR/octo-shared-marketplace-codex-duplicate.out"
    local source_output="$TEST_TMP_DIR/octo-shared-marketplace-codex-source.out"
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
test_local_marketplace_sync_aligns_all_versions
test_release_promotes_unreleased_changelog_notes
test_release_ci_parser_matches_exact_aggregate_checks
test_shared_marketplace_sync_updates_only_octo

test_summary
