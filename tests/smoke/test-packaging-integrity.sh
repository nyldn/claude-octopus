#!/bin/bash
# tests/smoke/test-packaging-integrity.sh
# Validates all sourced scripts and required files exist in the package
# Regression test for issue #19 (missing metrics-tracker.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Packaging Integrity (Regression: Issue #19)"

PACKAGING_FIXTURE_DIR=""
cleanup_packaging_fixture() {
    case "$PACKAGING_FIXTURE_DIR" in
        "$TEST_TMP_DIR"/npm-pack-*) rm -rf -- "$PACKAGING_FIXTURE_DIR" ;;
    esac
    PACKAGING_FIXTURE_DIR=""
}
trap cleanup_packaging_fixture EXIT INT TERM

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

packaged_health_command() (
    local package_root="$1"
    local home="$2"
    local host="$3"
    local active_root="$4"
    shift 4
    cd "$home" || return 1

    case "$host" in
        claude)
            env -i HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" \
                TMPDIR="$home/tmp" PATH="$PATH" \
                OCTOPUS_HOST=claude CLAUDE_PLUGIN_ROOT="$active_root" \
                OCTOPUS_INSTALL_SCOPE=user "$package_root/bin/octopus" "$@"
            ;;
        codex)
            env -i HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" TMPDIR="$home/tmp" \
                CODEX_HOME="$home/.codex" PATH="$PATH" OCTOPUS_HOST=codex \
                CODEX_PLUGIN_ROOT="$active_root" OCTOPUS_INSTALL_SCOPE=user \
                "$package_root/bin/octopus" "$@"
            ;;
        *) return 2 ;;
    esac
)

packaged_home_snapshot() {
    local home="$1"
    {
        find "$home" -mindepth 1 -print 2>/dev/null
        find "$home" -mindepth 1 -exec ls -ldn {} \; 2>/dev/null
        find "$home" -type f -exec cksum {} \; 2>/dev/null
        find "$home" -type l -exec readlink {} \; 2>/dev/null
    } | LC_ALL=C sort | cksum
}

validate_extracted_lifecycle_contract() {
    local package_root="$1"
    local active_root
    local home="$PACKAGING_FIXTURE_DIR/health-home"
    local state="$home/.claude-octopus/install-state.json"
    local sentinel="$home/.claude-octopus/results/user-result.txt"
    local missing_root="$home/missing-active-root"
    local expected_version version show_json doctor_json missing_doctor_json repair_json
    local before after before_dry after_dry before_records after_records rc=0

    active_root="$(cd "$package_root" && pwd -P)" || return 1
    mkdir -p "$(dirname "$sentinel")" "$home/.claude" "$home/.codex" "$home/tmp" || return 1
    printf '%s\n' 'keep-user-result' > "$sentinel"
    expected_version="$(jq -r '.version' "$package_root/.claude-plugin/plugin.json")"
    if version="$(packaged_health_command "$package_root" "$home" claude \
        "$active_root" version 2>&1)"; then
        :
    else
        printf 'packaged version command failed\n'
        return 1
    fi
    if [[ "$version" != "$expected_version" ]]; then
        printf 'packaged version mismatch: expected %s, got %s\n' "$expected_version" "$version"
        return 1
    fi

    packaged_health_command "$package_root" "$home" claude "$active_root" \
        install-state record >/dev/null 2>&1 || return 1
    packaged_health_command "$package_root" "$home" codex "$active_root" \
        install-state record >/dev/null 2>&1 || return 1
    before_records="$(jq -c '.hosts | with_entries(.value |= del(.recorded_at))' "$state")"
    packaged_health_command "$package_root" "$home" claude "$active_root" \
        install-state record >/dev/null 2>&1 || return 1
    packaged_health_command "$package_root" "$home" codex "$active_root" \
        install-state record >/dev/null 2>&1 || return 1
    after_records="$(jq -c '.hosts | with_entries(.value |= del(.recorded_at))' "$state")"

    if [[ "$before_records" != "$after_records" ]] ||
       ! jq -e --arg root "$active_root" --arg version "$expected_version" '
        .schema == 2 and (.hosts | keys | sort) == ["claude","codex"] and
        .hosts.claude.plugin_root == $root and
        .hosts.codex.plugin_root == $root and
        .hosts.claude.plugin_version == $version and
        .hosts.codex.plugin_version == $version and
        .hosts.claude.install_scope == "user" and
        .hosts.codex.install_scope == "user"
    ' "$state" >/dev/null 2>&1; then
        printf 'repeated recording did not preserve exactly one record for each host\n'
        return 1
    fi
    if show_json="$(packaged_health_command "$package_root" "$home" codex \
        "$active_root" install-state show 2>/dev/null)"; then
        :
    else
        printf 'packaged install-state show failed\n'
        return 1
    fi
    if ! jq -e '.current == true and .recorded.host == "codex"' \
        <<<"$show_json" >/dev/null 2>&1; then
        printf 'repeated host record is not current\n'
        return 1
    fi

    if doctor_json="$(packaged_health_command "$package_root" "$home" claude \
        "$active_root" doctor installation --json 2>/dev/null)"; then
        :
    else
        printf 'packaged installation doctor failed for the candidate\n'
        return 1
    fi
    if ! jq -e '
        any(.results[]; .name == "install-state" and .status == "pass") and
        any(.results[]; .name == "stable-plugin-root" and .status == "warn")
    ' <<<"$doctor_json" >/dev/null 2>&1; then
        printf 'packaged installation doctor omitted lifecycle evidence\n'
        return 1
    fi

    before="$(cksum "$state")"
    if packaged_health_command "$package_root" "$home" claude "$missing_root" \
        install-state record >/dev/null 2>&1; then
        printf 'missing active root was recorded\n'
        return 1
    else
        rc=$?
    fi
    after="$(cksum "$state")"
    if [[ "$rc" -eq 0 || "$before" != "$after" ]]; then
        printf 'missing active root changed the saved host records\n'
        return 1
    fi
    rc=0
    if missing_doctor_json="$(packaged_health_command "$package_root" "$home" claude \
        "$missing_root" doctor installation --json 2>/dev/null)"; then
        rc=0
    else
        rc=$?
    fi
    if [[ "$rc" -eq 0 ]] || ! jq -e '
        any(.results[]; .category == "installation" and .status == "fail")
    ' <<<"$missing_doctor_json" >/dev/null 2>&1; then
        printf 'installation doctor did not reject a missing active root\n'
        return 1
    fi

    before_dry="$(packaged_home_snapshot "$home")"
    if repair_json="$(packaged_health_command "$package_root" "$home" claude \
        "$active_root" repair --dry-run --json 2>/dev/null)"; then
        :
    else
        printf 'packaged repair dry-run failed\n'
        return 1
    fi
    after_dry="$(packaged_home_snapshot "$home")"
    if [[ "$before_dry" != "$after_dry" || -e "$home/.claude-octopus/plugin" ]] ||
       ! jq -e '.mode == "dry-run" and .status == "missing" and .result == "ready"' \
           <<<"$repair_json" >/dev/null 2>&1; then
        printf 'repair dry-run changed isolated host state\n'
        return 1
    fi
    if [[ "$(cat "$sentinel" 2>/dev/null || true)" != "keep-user-result" ]]; then
        printf 'lifecycle health commands changed user data\n'
        return 1
    fi
}

test_public_publication_boundary() {
    test_case "public checkout excludes private development material"
    local output
    local boundary_home="$TEST_TMP_DIR/public-boundary-home"
    mkdir -p "$boundary_home/npm-cache" "$boundary_home/tmp"
    if output=$(env -i HOME="$boundary_home" TMPDIR="$boundary_home/tmp" PATH="$PATH" \
        NPM_CONFIG_CACHE="$boundary_home/npm-cache" NPM_CONFIG_USERCONFIG=/dev/null \
        bash "$PROJECT_ROOT/scripts/validate-no-hardcoded-paths.sh" 2>&1); then
        test_pass
    else
        test_fail "public publication boundary failed: $output"
        return 1
    fi
}

test_sourced_scripts_exist() {
    test_case "All scripts sourced by orchestrate.sh exist"

    if [[ ! -f "$ORCHESTRATE" ]]; then
        test_fail "orchestrate.sh not found"
        return 1
    fi

    local missing=0
    local script_dir
    script_dir=$(dirname "$ORCHESTRATE")

    # Extract all source statements from orchestrate.sh
    # Matches: source "${SCRIPT_DIR}/foo.sh" and source "$SCRIPT_DIR/foo.sh"
    while IFS= read -r line; do
        # Extract the filename from source "${SCRIPT_DIR}/filename.sh"
        local sourced_file
        sourced_file=$(echo "$line" | grep -oE 'source "\$\{?SCRIPT_DIR\}?/[^"]+' | sed 's|source "\${SCRIPT_DIR}/||;s|source "$SCRIPT_DIR/||')

        if [[ -n "$sourced_file" ]]; then
            local full_path="${script_dir}/${sourced_file}"
            if [[ ! -f "$full_path" ]]; then
                echo "  MISSING: ${sourced_file} (referenced in orchestrate.sh)"
                missing=$((missing + 1))
            fi
        fi
    done < <(grep '^source ' "$ORCHESTRATE" 2>/dev/null)

    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing sourced script(s) missing from package"
        return 1
    fi
}

test_metrics_tracker_exists() {
    test_case "metrics-tracker.sh exists (regression: issue #19)"

    local expected="$PROJECT_ROOT/scripts/metrics-tracker.sh"

    if [[ -f "$expected" ]]; then
        test_pass
    else
        test_fail "metrics-tracker.sh missing - this was bug #19"
        return 1
    fi
}

test_state_manager_exists() {
    test_case "state-manager.sh exists"

    local expected="$PROJECT_ROOT/scripts/state-manager.sh"

    if [[ -f "$expected" ]]; then
        test_pass
    else
        test_fail "state-manager.sh missing from scripts/"
        return 1
    fi
}

test_hook_scripts_exist() {
    test_case "All hook scripts referenced in hooks/ are valid"

    local hooks_dir="$PROJECT_ROOT/hooks"

    if [[ ! -d "$hooks_dir" ]]; then
        test_skip "hooks/ directory not found"
        return 0
    fi

    local missing=0
    for hook in "$hooks_dir"/*.sh; do
        [[ ! -f "$hook" ]] && continue

        # Verify hook is valid bash
        if ! bash -n "$hook" 2>/dev/null; then
            echo "  INVALID SYNTAX: $(basename "$hook")"
            missing=$((missing + 1))
        fi

        # Verify hook is executable
        if [[ ! -x "$hook" ]]; then
            echo "  NOT EXECUTABLE: $(basename "$hook")"
            missing=$((missing + 1))
        fi
    done

    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing hook script issue(s) found"
        return 1
    fi
}

test_orchestrate_can_source_deps() {
    test_case "orchestrate.sh can source all dependencies without error"

    if [[ ! -f "$ORCHESTRATE" ]]; then
        test_fail "orchestrate.sh not found"
        return 1
    fi

    # Extract source lines and verify each target file exists
    # Note: we check file existence rather than eval-sourcing because sourced
    # scripts may reference variables only set during orchestrate.sh runtime
    local result="OK"
    local script_dir
    script_dir=$(dirname "$ORCHESTRATE")
    while IFS= read -r line; do
        # Extract the path from 'source "$SCRIPT_DIR/lib/foo.sh" 2>/dev/null || true' etc.
        # Strip 'source ', quotes, and any trailing redirects/error handling
        local src_path
        src_path=$(echo "$line" | sed 's/^source //' | sed 's/"//g' | sed 's/ *2>.*//' | sed "s|\\\$SCRIPT_DIR|$script_dir|g" | sed "s|\${SCRIPT_DIR}|$script_dir|g")
        if [[ ! -f "$src_path" ]]; then
            result="FAIL: $line (resolved to $src_path)"
            break
        fi
    done < <(grep "^source " "$ORCHESTRATE" 2>/dev/null)

    if [[ "$result" == "OK" ]]; then
        test_pass
    else
        test_fail "Failed to source dependencies: $result"
        return 1
    fi
}

test_extracted_archive_contract() {
    test_case "npm archive contains every declared component and adapter entrypoint"
    local required_tool pack_json tarball extract_dir package_root result npm_error
    for required_tool in npm jq tar python3; do
        if ! command -v "$required_tool" >/dev/null 2>&1; then
            test_skip "$required_tool is required for npm archive validation"
            return 0
        fi
    done
    PACKAGING_FIXTURE_DIR="$TEST_TMP_DIR/npm-pack-${BASHPID:-$$}"
    if ! mkdir "$PACKAGING_FIXTURE_DIR"; then
        test_fail "unable to allocate package fixture"
        return 1
    fi
    npm_error="$PACKAGING_FIXTURE_DIR/npm-pack.stderr"
    extract_dir="$PACKAGING_FIXTURE_DIR/extracted"
    mkdir -p "$extract_dir" "$PACKAGING_FIXTURE_DIR/npm-home" "$PACKAGING_FIXTURE_DIR/npm-cache"
    if ! pack_json=$(cd "$PROJECT_ROOT" && env -i \
        HOME="$PACKAGING_FIXTURE_DIR/npm-home" PATH="$PATH" \
        TMPDIR="$PACKAGING_FIXTURE_DIR/npm-home" \
        NPM_CONFIG_CACHE="$PACKAGING_FIXTURE_DIR/npm-cache" NPM_CONFIG_USERCONFIG=/dev/null \
        npm pack --ignore-scripts --json --pack-destination "$PACKAGING_FIXTURE_DIR" \
        2>"$npm_error"); then
        result="$(tr '\n' ' ' < "$npm_error")"
        cleanup_packaging_fixture
        test_fail "npm pack failed: ${result:-no diagnostics}"
        return 1
    fi
    tarball=$(printf '%s' "$pack_json" | jq -r '.[0].filename // empty' 2>/dev/null)
    if [[ -z "$tarball" || ! -f "$PACKAGING_FIXTURE_DIR/$tarball" ]] ||
       ! tar -xzf "$PACKAGING_FIXTURE_DIR/$tarball" -C "$extract_dir"; then
        cleanup_packaging_fixture
        test_fail "npm archive could not be extracted"
        return 1
    fi
    package_root="$extract_dir/package"
    local status=0
    if result=$(python3 - "$package_root" <<'PYTEST'
import json
import os
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
missing = []

def resolve(relative, kind="path"):
    relative = str(relative)
    if relative.startswith("./"):
        relative = relative[2:]
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        missing.append(f"escaping {kind}: {relative}")
        return None
    return candidate

claude = json.loads((root / ".claude-plugin/plugin.json").read_text())
for command in claude.get("commands", []):
    path = resolve(command, "Claude command")
    if path is not None and not path.is_file():
        missing.append(str(command))
for skill in claude.get("skills", []):
    path = resolve(skill, "Claude skill")
    if path is not None and not (path / "SKILL.md").is_file():
        missing.append(f"{skill}/SKILL.md")

for manifest_name in (".codex-plugin/plugin.json", ".cursor-plugin/plugin.json"):
    manifest = json.loads((root / manifest_name).read_text())
    for field in ("skills", "agents", "commands"):
        relative = manifest.get(field)
        if isinstance(relative, str):
            path = resolve(relative, f"{manifest_name} {field}")
            if path is not None and not path.is_dir():
                missing.append(f"{manifest_name}:{field}:{relative}")

for adapter in ("mcp-server",):
    package = root / adapter / "package.json"
    if not package.is_file():
        missing.append(str(package.relative_to(root)))
        continue
    metadata = json.loads(package.read_text())
    entrypoint = root / adapter / metadata.get("main", "")
    if not entrypoint.is_file():
        missing.append(str(entrypoint.relative_to(root)))

for required in (
    "scripts/orchestrate.sh",
    "scripts/helpers/readiness-contract.py",
    "hooks/hooks.json",
    "config/model-pricing.tsv",
    "THIRD_PARTY_NOTICES.md",
    "licenses/mattpocock-skills-MIT.txt",
    "skills/blocks/architecture-simplification.md",
    "skills/blocks/debug-feedback-loop.md",
    "skills/blocks/domain-modeling.md",
    "data/evals/workflow-skill-cases.json",
    "data/evals/workflow-test-consolidation.json",
):
    path = root / required
    if not path.exists():
        missing.append(required)
license_text = (root / "licenses/mattpocock-skills-MIT.txt").read_text()
notices_text = (root / "THIRD_PARTY_NOTICES.md").read_text()
if "Copyright (c) 2026 Matt Pocock" not in license_text or "Permission is hereby granted" not in license_text:
    missing.append("complete Matt Pocock MIT notice")
for adopted in ("codebase-design", "DEEPENING", "diagnosing-bugs", "domain-modeling", "wayfinder", "prototype", "wizard", "writing-great-skills", "triage", "to-tickets", "grilling"):
    if adopted not in notices_text:
        missing.append("attribution:" + adopted)
if not os.access(root / "scripts/orchestrate.sh", os.X_OK):
    missing.append("scripts/orchestrate.sh:not-executable")

print("\n".join(missing))
raise SystemExit(bool(missing))
PYTEST
    ); then
        status=0
    else
        status=$?
    fi
    if [[ "$status" -eq 0 ]]; then
        if result="$(validate_extracted_lifecycle_contract "$package_root")"; then
            status=0
        else
            status=$?
        fi
    fi
    cleanup_packaging_fixture
    if [[ "$status" -eq 0 ]]; then
        test_pass
    else
        test_fail "extracted archive contract failed: ${result:-no diagnostics}"
        return 1
    fi
}

test_metadata_fast_path_validates_archive() {
    test_case "metadata-only CI runs extracted archive validation"
    local workflow="$PROJECT_ROOT/.github/workflows/test.yml"
    if grep -q '^  package-integrity:' "$workflow" &&
       grep -q 'tests/smoke/test-packaging-integrity.sh' "$workflow"; then
        test_pass
    else
        test_fail "metadata fast path can skip package archive validation"
        return 1
    fi
}

test_package_integrity_checkout_is_hardened() {
    test_case "package integrity pins checkout and does not persist credentials"
    local workflow="$PROJECT_ROOT/.github/workflows/test.yml"
    local package_job package_checkout
    package_job=$(sed -n '/^  package-integrity:/,/^  portability-lint:/p' "$workflow")
    package_checkout=$(grep -A3 -F 'uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' <<< "$package_job" || true)
    if grep -Fq 'uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' <<< "$package_job" &&
       grep -Fq 'persist-credentials: false' <<< "$package_checkout"; then
        test_pass
    else
        test_fail "package integrity checkout is mutable or persists credentials"
        return 1
    fi
}

test_summary_propagates_package_integrity_failure() {
    test_case "test summary reports and fails on package integrity failure"
    local workflow="$PROJECT_ROOT/.github/workflows/test.yml"
    local summary_job package_status_check
    summary_job=$(sed -n '/^  test-summary:/,$p' "$workflow")
    # shellcheck disable=SC2016 # Match literal GitHub expressions in the workflow.
    package_status_check=$(grep -A3 -F 'if [[ "${{ needs.package-integrity.result }}" != "success" ]]; then' <<< "$summary_job" || true)
    # shellcheck disable=SC2016 # Match literal GitHub expressions in the workflow.
    if grep -Fq '| Package | ${{ needs.package-integrity.result }} |' <<< "$summary_job" &&
       grep -Fq 'if [[ "${{ needs.package-integrity.result }}" != "success" ]]; then' <<< "$summary_job" &&
       grep -Fq 'exit 1' <<< "$package_status_check"; then
        test_pass
    else
        test_fail "test summary does not propagate package integrity failure"
        return 1
    fi
}

# Run tests
test_public_publication_boundary
test_sourced_scripts_exist
test_metrics_tracker_exists
test_state_manager_exists
test_hook_scripts_exist
test_orchestrate_can_source_deps
test_extracted_archive_contract
test_metadata_fast_path_validates_archive
test_summary_propagates_package_integrity_failure
test_package_integrity_checkout_is_hardened

test_summary
