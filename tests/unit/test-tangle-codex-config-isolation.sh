#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
log() { :; }
test_suite "tangle Codex configuration isolation"
fixture="$(mktemp -d /var/tmp/octopus-codex-config.XXXXXX)"
trap 'rm -rf "$fixture"; cleanup_test_environment' EXIT
fixture="$(cd "$fixture" && pwd -P)"
mkdir -p "$fixture/worktree" "$fixture/results" "$fixture/home" "$fixture/state"
phase=tangle role=implementer agent_type=codex
export OCTOPUS_TANGLE_EXECUTION_BOUNDARY=true
export OCTOPUS_TANGLE_WORKTREE="$fixture/worktree" OCTOPUS_TANGLE_RESULTS_DIR="$fixture/results"
export HOME="$fixture/home" CODEX_HOME="$fixture/state"
refused() {
    local status
    cmd_array=(bash -c 'touch "$1/ran"' _ "$fixture/worktree")
    if octopus_tangle_apply_execution_boundary; then return 1; else status=$?; fi
    [[ "$status" -eq 125 && ! -e "$fixture/worktree/ran" ]]
}
if ! octopus_tangle_execution_boundary_probe; then
    test_case "unsupported hosts refuse Codex dispatch"
    if refused; then test_pass; else test_fail "unconfined dispatch accepted"; fi
    test_summary
    exit 0
fi

test_case "trusted config and extensions are readable but cannot be modified or replaced"
mkdir -p "$CODEX_HOME/skills/demo" "$CODEX_HOME/plugins/demo" "$CODEX_HOME/profiles"
printf 'notify = ["trusted"]\n[mcp_servers.trusted]\ncommand = "trusted"\n' > "$CODEX_HOME/config.toml"
for item in AGENTS.md profile.config.toml skills/demo/SKILL.md plugins/demo/plugin.json profiles/trusted.toml; do
    printf 'trusted\n' > "$CODEX_HOME/$item"
done
cmd_array=(bash -c 'for item in config.toml AGENTS.md profile.config.toml skills/demo/SKILL.md plugins/demo/plugin.json profiles/trusted.toml; do
    [[ -r "$1/$item" ]] || exit 1
    if { printf poison > "$1/$item"; } 2>/dev/null; then exit 2; fi
    if mv "$1/$item" "$1/replaced" 2>/dev/null; then exit 3; fi
done' _ "$CODEX_HOME")
if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}"; then test_pass; else test_fail "trusted input was writable or unreadable"; fi

test_case "absent executable configuration and profile entries cannot be created"
cmd_array=(bash -c 'for item in new.config.toml AGENTS.override.md mcp.json notify.sh plugins/new/plugin.json skills/new/SKILL.md; do
    if mkdir -p "$(dirname "$1/$item")" 2>/dev/null && touch "$1/$item" 2>/dev/null; then exit 1; fi
done' _ "$CODEX_HOME")
if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}" && [[ ! -e "$CODEX_HOME/new.config.toml" ]]; then test_pass; else test_fail "worker created persistent executable inputs"; fi

test_case "an empty Codex home cannot acquire configuration on either dispatch"
saved_codex_home="$CODEX_HOME"
CODEX_HOME="$fixture/empty-state"
mkdir "$CODEX_HOME"
empty_failures=0
for dispatch in first second; do
    cmd_array=(bash -c 'for item in config.toml AGENTS.md profile.config.toml skills/demo/SKILL.md plugins/demo/plugin.json; do
        if mkdir -p "$(dirname "$1/$item")" 2>/dev/null && touch "$1/$item" 2>/dev/null; then exit 1; fi
    done
    touch "$1/tmp/ran"' _ "$CODEX_HOME")
    if ! octopus_tangle_apply_execution_boundary || ! "${cmd_array[@]}" || [[ -e "$CODEX_HOME/config.toml" || -e "$CODEX_HOME/AGENTS.md" || -e "$CODEX_HOME/tmp/ran" ]]; then empty_failures=$((empty_failures + 1)); fi
done
CODEX_HOME="$saved_codex_home"
if [[ "$empty_failures" -eq 0 ]]; then test_pass; else test_fail "absent configuration became persistent or runtime failed"; fi

test_case "runtime caches, installation ID and SQLite are private on each dispatch"
printf 'host-installation-id\n' > "$CODEX_HOME/installation_id"
cmd_array=(bash -c '[[ ! -e "$1/tmp/installation_id" ]] || exit 4
printf private-installation-id > "$1/installation_id" || exit 5
for item in tmp sessions archived_sessions log shell_snapshots; do
    [[ ! -e "$1/$item/state" ]] || exit 1
    touch "$1/$item/state" || exit 2
done
[[ "$CODEX_SQLITE_HOME" == "$1/tmp/sqlite" ]] || exit 3
mkdir -p "$CODEX_SQLITE_HOME" && touch "$CODEX_SQLITE_HOME/state.db"' _ "$CODEX_HOME")
if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}" && [[ ! -e "$CODEX_HOME/tmp/state" && "$(cat "$CODEX_HOME/installation_id")" == host-installation-id ]]; then
    cmd_array=(bash -c '[[ ! -e "$1/tmp/state" && ! -e "$1/sessions/state" && ! -e "$1/installation_id" ]]' _ "$CODEX_HOME")
    if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}"; then test_pass; else test_fail "state crossed dispatches"; fi
else test_fail "private runtime writes failed or persisted"; fi

test_case "synthetic regular auth refresh works in place without writable replacement"
printf 'synthetic-before\n' > "$CODEX_HOME/auth.json"
cmd_array=(bash -c 'printf synthetic-after > "$1/auth.json" || exit 1
if mv "$1/auth.json" "$1/auth.saved" 2>/dev/null; then exit 2; fi
if touch "$1/new.config.toml" 2>/dev/null; then exit 3; fi' _ "$CODEX_HOME")
if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}" && [[ "$(cat "$CODEX_HOME/auth.json")" == synthetic-after ]]; then test_pass; else test_fail "in-place synthetic auth refresh or config protection failed"; fi

test_case "symlink and hard-linked auth files never gain a writable mount"
rm -f "$CODEX_HOME/auth.json"
printf 'synthetic-safe\n' > "$fixture/auth-target"
auth_failures=0
for layout in symlink hardlink; do
    if [[ "$layout" == symlink ]]; then ln -s "$fixture/auth-target" "$CODEX_HOME/auth.json"; else ln "$fixture/auth-target" "$CODEX_HOME/auth.json"; fi
    cmd_array=(bash -c 'if { printf poison > "$1/auth.json"; } 2>/dev/null; then exit 1; fi' _ "$CODEX_HOME")
    if ! octopus_tangle_apply_execution_boundary || ! "${cmd_array[@]}" || [[ "$(cat "$fixture/auth-target")" != synthetic-safe ]]; then auth_failures=$((auth_failures + 1)); fi
    rm -f "$CODEX_HOME/auth.json"
done
if [[ "$auth_failures" -eq 0 ]]; then test_pass; else test_fail "unsafe auth backing path became writable"; fi

test_case "configuration symlinks into worktree or auth refuse dispatch before execution"
printf 'synthetic\n' > "$CODEX_HOME/auth.json"
printf 'trusted\n' > "$fixture/worktree/target"
link_failures=0
for target in "$fixture/worktree/target" "$CODEX_HOME/auth.json"; do
    ln -s "$target" "$CODEX_HOME/skills/demo/link"
    refused || link_failures=$((link_failures + 1))
    rm "$CODEX_HOME/skills/demo/link"
done
if [[ "$link_failures" -eq 0 ]]; then test_pass; else test_fail "writable backing path admitted"; fi

test_case "hard-linked configuration refuses dispatch"
ln "$CODEX_HOME/AGENTS.md" "$fixture/worktree/agents-alias"
if refused; then test_pass; else test_fail "alternate writable config inode admitted"; fi
rm "$fixture/worktree/agents-alias"

test_case "host executable cache aliases refuse before a worker can poison them"
mkdir -p "$CODEX_HOME/shell_snapshots" "$CODEX_HOME/tmp/bin"
printf 'trusted-cache\n' > "$CODEX_HOME/shell_snapshots/snapshot.sh"
printf 'trusted-cache\n' > "$fixture/worktree/tmp-tool"
cache_failures=0
ln "$CODEX_HOME/shell_snapshots/snapshot.sh" "$fixture/worktree/snapshot-alias"
refused || cache_failures=$((cache_failures + 1))
[[ "$(cat "$CODEX_HOME/shell_snapshots/snapshot.sh")" == trusted-cache ]] || cache_failures=$((cache_failures + 1))
rm "$fixture/worktree/snapshot-alias"
ln -s "$fixture/worktree/tmp-tool" "$CODEX_HOME/tmp/bin/tool"
refused || cache_failures=$((cache_failures + 1))
rm "$CODEX_HOME/tmp/bin/tool"
if [[ "$cache_failures" -eq 0 ]]; then test_pass; else test_fail "host cache writable backing was admitted"; fi

test_case "safe external skill links remain readable and read-only"
mkdir "$fixture/trusted-skill"
printf 'trusted\n' > "$fixture/trusted-skill/SKILL.md"
ln -s "$fixture/trusted-skill" "$CODEX_HOME/skills/external"
cmd_array=(bash -c '[[ "$(cat "$1/skills/external/SKILL.md")" == trusted ]] || exit 1
if { printf poison > "$1/skills/external/SKILL.md"; } 2>/dev/null; then exit 2; fi' _ "$CODEX_HOME")
if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}"; then test_pass; else test_fail "safe extension link lost protection or readability"; fi

test_case "broken and self-cyclic configuration links fail closed"
link_failures=0
for target in "$fixture/missing" "$CODEX_HOME/skills/demo/link"; do
    ln -s "$target" "$CODEX_HOME/skills/demo/link"
    refused || link_failures=$((link_failures + 1))
    rm "$CODEX_HOME/skills/demo/link"
done
if [[ "$link_failures" -eq 0 ]]; then test_pass; else test_fail "uninspectable configuration admitted"; fi

test_case "configured TMPDIR cannot reopen an outside-HOME config subtree"
printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$CODEX_HOME/profiles" > "$CODEX_HOME/config.toml"
if refused; then test_pass; else test_fail "TMPDIR reopened or hid configuration"; fi


test_case "configured TMPDIR inside worktree or with control delimiters fails closed"
failures=0
for value in "$fixture/worktree" "$fixture/worktree"$'\n'"another-path"; do
    python3 -I - "$CODEX_HOME/config.toml" "$value" <<'PYTHON'
import json, sys
with open(sys.argv[1], "w") as handle:
    handle.write("[shell_environment_policy]\nset = { TMPDIR = " + json.dumps(sys.argv[2]) + " }\n")
PYTHON
    refused || failures=$((failures + 1))
done
printf '[features]\nweb_search = false\n' > "$CODEX_HOME/config.toml"
if [[ "$failures" -eq 0 ]]; then test_pass; else test_fail "unsafe temporary path admitted"; fi

test_case "CODEX_HOME in the writable worktree aborts before a worker executes"
saved_codex_home="$CODEX_HOME"
mkdir "$fixture/worktree/state"
CODEX_HOME="$fixture/worktree/state"
if refused; then test_pass; else test_fail "unsafe overlapping CODEX_HOME admitted"; fi
CODEX_HOME="$saved_codex_home"

test_case "raw CODEX_HOME control delimiters refuse before worker execution"
saved_codex_home="$CODEX_HOME"
failures=0
for separator in $'\n' $'\r' $'\t' $'\177'; do
    CODEX_HOME="$saved_codex_home$separator/tmp"
    refused || failures=$((failures + 1))
done
CODEX_HOME="$saved_codex_home"
if [[ "$failures" -eq 0 ]]; then test_pass; else test_fail "control delimiter split state authority"; fi

test_case "missing configuration inspector fails closed"
python3() { return 127; }
if refused; then test_pass; else test_fail "failed inspector admitted worker"; fi
unset -f python3

test_summary
