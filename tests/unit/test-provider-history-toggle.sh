#!/usr/bin/env bash
# Regression checks for disabling provider history read/write/injection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "provider history toggle"

WORKSPACE_DIR="$TEST_TMP_DIR/provider-history-toggle"
RESULTS_DIR="$WORKSPACE_DIR/results"
LOG_LEVEL="WARN"
log() { :; }

assert_provider_history_toggle_for_script() (
    local script_path="$1"
    rm -rf "$WORKSPACE_DIR"
    mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"
    log() { :; }
    source "$script_path"

    export OCTOPUS_PROVIDER_HISTORY=off
    append_provider_history codex tangle "task" "learned"
    [[ ! -e "$WORKSPACE_DIR/.octo/providers/codex-history.md" ]] || return 1

    mkdir -p "$WORKSPACE_DIR/.octo/providers"
    cat > "$WORKSPACE_DIR/.octo/providers/codex-history.md" <<'EOF'
### tangle | 2026-01-01T00:00:00Z
**Task:** stale task
**Learned:** stale learning
---
EOF
    [[ -z "$(read_provider_history codex)" ]] || return 1
    [[ -z "$(build_provider_context codex)" ]] || return 1

    unset OCTOPUS_PROVIDER_HISTORY || true
    rm -rf "$WORKSPACE_DIR"
    mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"
    append_provider_history codex tangle "task" "learned"
    local ctx
    ctx="$(build_provider_context codex)"
    [[ "$ctx" == *"Provider History (codex)"* ]] && [[ "$ctx" == *"learned"* ]]
)

test_case "provider-routing.sh honors OCTOPUS_PROVIDER_HISTORY"
if assert_provider_history_toggle_for_script "$PROJECT_ROOT/scripts/lib/provider-routing.sh"; then
    test_pass
else
    test_fail "provider-routing.sh provider history toggle behavior regressed"
fi

test_case "quality.sh honors OCTOPUS_PROVIDER_HISTORY"
if assert_provider_history_toggle_for_script "$PROJECT_ROOT/scripts/lib/quality.sh"; then
    test_pass
else
    test_fail "quality.sh provider history toggle behavior regressed"
fi

test_case "model-qualified provider history writes to the normalized executor file"
rm -rf "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"
source "$PROJECT_ROOT/scripts/lib/provider-lockout.sh"
unset OCTOPUS_PROVIDER_HISTORY || true
append_provider_history 'commandcode:stealth/ox-alpha' tangle "task" "model-aware history"
if [[ -f "$WORKSPACE_DIR/.octo/providers/commandcode-history.md" ]] && \
   [[ ! -e "$WORKSPACE_DIR/.octo/providers/commandcode:stealth/ox-alpha-history.md" ]] && \
   grep -Fq 'model-aware history' "$WORKSPACE_DIR/.octo/providers/commandcode-history.md"; then
    test_pass
else
    test_fail "model-qualified provider history was not normalized to commandcode-history.md"
fi


test_case "provider history filename key cannot escape the providers directory"
rm -rf "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"
source "$PROJECT_ROOT/scripts/lib/provider-lockout.sh"
unset OCTOPUS_PROVIDER_HISTORY || true
append_provider_history '../../escaped' tangle "task" "safe history"
safe_file="$(find "$WORKSPACE_DIR/.octo/providers" -maxdepth 1 -type f -name '*escaped*-history.md' | head -1)"
if [[ -n "$safe_file" ]] && \
   [[ "$safe_file" == "$WORKSPACE_DIR/.octo/providers/"* ]] && \
   [[ ! -e "$WORKSPACE_DIR/escaped-history.md" ]] && \
   [[ ! -e "$WORKSPACE_DIR/.octo/escaped-history.md" ]]; then
    test_pass
else
    test_fail "provider history path escaped or safe file missing: ${safe_file:-none}"
fi


test_case "concurrent model-qualified seats serialize shared provider history append and trim"
rm -rf "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"
source "$PROJECT_ROOT/scripts/lib/provider-lockout.sh"
unset OCTOPUS_PROVIDER_HISTORY || true
for i in $(seq 1 48); do
    append_provider_history 'commandcode:stealth/ox-alpha' tangle "seed-$i" "seed history $i"
done
pids=""
for i in $(seq 49 56); do
    append_provider_history "commandcode:model-$i" tangle "concurrent-$i" "concurrent history $i" &
    pids="$pids $!"
done
for pid in $pids; do wait "$pid"; done
history_file="$WORKSPACE_DIR/.octo/providers/commandcode-history.md"
entry_count="$(grep -c '^### ' "$history_file" 2>/dev/null || true)"
leftovers="$(find "$WORKSPACE_DIR/.octo/providers" -maxdepth 1 \( -name 'commandcode-history.md.tmp.*' -o -name 'commandcode-history.md.lock' \) -print)"
missing=""
for i in $(seq 49 56); do
    grep -Fq "**Task:** concurrent-$i" "$history_file" || missing="$missing $i"
done
if [[ "$entry_count" == '50' ]] && [[ -z "$leftovers" ]] && [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "concurrent history transaction was not serialized: entries=$entry_count leftovers=${leftovers:-none} missing=${missing:-none}"
fi

test_case "provider history lock rejects utility success for an existing lock"
lock_file="$WORKSPACE_DIR/held-history.md"
mkdir "${lock_file}.lock"
printf 'existing owner\n' > "${lock_file}.lock/owner"
if (
    # Simulate a mkdir utility reporting success after losing a creation race.
    mkdir() { return 0; }
    sleep() { :; }
    ! provider_history_lock "$lock_file"
) && [[ "$(cat "${lock_file}.lock/owner")" == 'existing owner' ]]; then
    test_pass
else
    test_fail "provider history admitted a writer into another owner's lock"
fi
rm -rf "${lock_file}.lock"

test_case "provider history lock fails closed when Python is unavailable"
if (
    PATH="$TEST_TMP_DIR/no-python"
    mkdir() { return 0; }
    ! provider_history_lock "$WORKSPACE_DIR/no-runtime-history.md"
); then
    test_pass
else
    test_fail "provider history trusted utility admission without kernel locking"
fi

test_case "provider history append reports write failure and releases its lock"
rm -rf "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR/.octo/providers/codex-history.md" "$RESULTS_DIR"
source "$PROJECT_ROOT/scripts/lib/provider-lockout.sh"
unset OCTOPUS_PROVIDER_HISTORY || true
if append_provider_history codex tangle "task" "write must fail"; then
    test_fail "provider history append reported success when the history path was a directory"
elif [[ -e "$WORKSPACE_DIR/.octo/providers/codex-history.md.lock" ]]; then
    test_fail "provider history append left its lock behind after a write failure"
else
    test_pass
fi

test_case "provider history fails closed when agent-spec helpers are unavailable"
missing_spec_root="$TEST_TMP_DIR/provider-history-missing-agent-spec"
rm -rf "$missing_spec_root"
mkdir -p "$missing_spec_root/lib" "$missing_spec_root/workspace" "$RESULTS_DIR"
cp "$PROJECT_ROOT/scripts/lib/provider-lockout.sh" "$missing_spec_root/lib/provider-lockout.sh"
missing_spec_rc=0
(
    set +e
    unset -f octo_agent_spec_provider octo_agent_spec_slug
    WORKSPACE_DIR="$missing_spec_root/workspace"
    log() { :; }
    source "$missing_spec_root/lib/provider-lockout.sh"
    append_provider_history codex tangle "task" "must not write without normalization"
) || missing_spec_rc=$?
if [[ "$missing_spec_rc" -ne 127 ]]; then
    test_fail "provider history did not return dependency status 127: rc=$missing_spec_rc"
elif find "$missing_spec_root/workspace" -type f -name '*-history.md' -print | grep -q .; then
    test_fail "provider history wrote a fallback file without agent-spec normalization"
else
    test_pass
fi

test_summary
