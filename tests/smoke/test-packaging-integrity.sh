#!/bin/bash
# tests/smoke/test-packaging-integrity.sh
# Validates all sourced scripts and required files exist in the package
# Regression test for issue #19 (missing metrics-tracker.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Packaging Integrity (Regression: Issue #19)"

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

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
    local pack_dir pack_json tarball extract_dir package_root result
    pack_dir=$(mktemp -d "${TMPDIR:-/tmp}/octopus-pack.XXXXXX") || {
        test_fail "unable to allocate package fixture"
        return 1
    }
    extract_dir="$pack_dir/extracted"
    mkdir -p "$extract_dir"
    if ! pack_json=$(cd "$PROJECT_ROOT" && npm pack --ignore-scripts --json --pack-destination "$pack_dir" 2>/dev/null); then
        rm -rf "$pack_dir"
        test_fail "npm pack failed"
        return 1
    fi
    tarball=$(printf '%s' "$pack_json" | jq -r '.[0].filename // empty' 2>/dev/null)
    if [[ -z "$tarball" || ! -f "$pack_dir/$tarball" ]] ||
       ! tar -xzf "$pack_dir/$tarball" -C "$extract_dir"; then
        rm -rf "$pack_dir"
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

for adapter in ("mcp-server", "openclaw"):
    package = root / adapter / "package.json"
    if not package.is_file():
        missing.append(str(package.relative_to(root)))
        continue
    metadata = json.loads(package.read_text())
    entrypoint = root / adapter / metadata.get("main", "")
    if not entrypoint.is_file():
        missing.append(str(entrypoint.relative_to(root)))

for required in ("scripts/orchestrate.sh", "hooks/hooks.json", "config/model-pricing.tsv"):
    path = root / required
    if not path.exists():
        missing.append(required)
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
    rm -rf "$pack_dir"
    if [[ "$status" -eq 0 ]]; then
        test_pass
    else
        test_fail "extracted archive is incomplete: $result"
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

# Run tests
test_sourced_scripts_exist
test_metrics_tracker_exists
test_state_manager_exists
test_hook_scripts_exist
test_orchestrate_can_source_deps
test_extracted_archive_contract
test_metadata_fast_path_validates_archive

test_summary
