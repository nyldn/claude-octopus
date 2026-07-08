#!/usr/bin/env bash
# Test: ollama-run.sh guard against unbounded auto-pull (provider-failure cascade
# safety). Verifies the shim FAILS CLOSED on an absent model unless the user has
# explicitly opted into downloads, enforces a size cap when pulls are allowed,
# and that dispatch routes Ollama through the shim rather than a bare `ollama run`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Ollama auto-pull guard"

HELPER="$PROJECT_ROOT/scripts/helpers/ollama-run.sh"
TMP="$TEST_TMP_DIR/ollama-guard"
mkdir -p "$TMP"
FAKE_OLLAMA="$TMP/ollama"
ERRF="$TMP/stderr.txt"

# ── A fake `ollama` CLI. `list` reports models named in $FAKE_OLLAMA_STATE;
#    `run` records the call and echoes a marker; `pull` emits a progress line
#    carrying a configurable total size, optionally stalls, then registers the
#    model as present. Every subcommand is appended to $FAKE_OLLAMA_LOG. ──
cat > "$FAKE_OLLAMA" <<'SH'
#!/usr/bin/env bash
sub="${1:-}"; shift 2>/dev/null || true
printf '%s %s\n' "$sub" "$*" >> "$FAKE_OLLAMA_LOG"
case "$sub" in
  list)
    echo "NAME	ID	SIZE	MODIFIED"
    if [[ -f "$FAKE_OLLAMA_STATE" ]]; then
      while IFS= read -r m; do
        [[ -n "$m" ]] && printf '%s\tabc123\t4.0 GB\t2 days ago\n' "$m"
      done < "$FAKE_OLLAMA_STATE"
    fi
    ;;
  run)
    cat >/dev/null 2>&1 || true   # consume the prompt on stdin
    echo "RUN_OK:${1:-}"
    ;;
  pull)
    model="${1:-}"
    gb="${FAKE_OLLAMA_PULL_GB:-1.0}"
    echo "pulling manifest"
    echo "pulling deadbeef:   0% |   | 119 KB/ ${gb} GB  2.0 MB/s  1h2m"
    [[ "${FAKE_OLLAMA_PULL_SLOW:-0}" == "1" ]] && sleep 3
    printf '%s\n' "$model" >> "$FAKE_OLLAMA_STATE"
    echo "success"
    ;;
  *) echo "fake-ollama: unknown subcommand $sub" >&2; exit 2 ;;
esac
SH
chmod +x "$FAKE_OLLAMA"

export FAKE_OLLAMA_STATE="$TMP/state"
export FAKE_OLLAMA_LOG="$TMP/calls.log"

reset_state() { : > "$FAKE_OLLAMA_STATE"; : > "$FAKE_OLLAMA_LOG"; }
seed_model()  { printf '%s\n' "$1" >> "$FAKE_OLLAMA_STATE"; }
called()      { grep -q "^$1 " "$FAKE_OLLAMA_LOG" 2>/dev/null; }

# Run the guard with the fake ollama. Captures GUARD_RC / GUARD_OUT / GUARD_ERR.
run_guard() {
    local m="$1"
    GUARD_RC=0
    GUARD_OUT="$(printf 'test-prompt' | OCTOPUS_OLLAMA_BIN="$FAKE_OLLAMA" "$HELPER" "$m" 2>"$ERRF")" || GUARD_RC=$?
    GUARD_ERR="$(cat "$ERRF" 2>/dev/null || true)"
}

# ── 1. Absent model + no opt-in → refuse, NO download ──────────────────────────
test_case "Absent model without opt-in is refused (no pull, no run)"
reset_state
unset OCTOPUS_OLLAMA_ALLOW_PULL || true
run_guard "ghost-model:7b"
if [[ "$GUARD_RC" -eq 70 ]] && ! called pull && ! called run \
   && [[ "$GUARD_ERR" == *"Refusing to auto-pull"* ]]; then
    test_pass
else
    test_fail "rc=$GUARD_RC pull=$(called pull && echo y || echo n) run=$(called run && echo y || echo n) err=${GUARD_ERR:0:80}"
fi

# ── 2. Present model runs directly, never pulls ───────────────────────────────
test_case "Present model runs directly without pulling"
reset_state
seed_model "qwen2.5-coder:7b"
unset OCTOPUS_OLLAMA_ALLOW_PULL || true
run_guard "qwen2.5-coder:7b"
if [[ "$GUARD_RC" -eq 0 ]] && called run && ! called pull \
   && [[ "$GUARD_OUT" == *"RUN_OK:qwen2.5-coder:7b"* ]]; then
    test_pass
else
    test_fail "rc=$GUARD_RC out=${GUARD_OUT:0:80} pull=$(called pull && echo y || echo n)"
fi

# ── 3. Bare name matches an installed ":latest" tag ───────────────────────────
test_case "Bare model name matches installed :latest"
reset_state
seed_model "llama3.3:latest"
run_guard "llama3.3"
if [[ "$GUARD_RC" -eq 0 ]] && called run && ! called pull; then
    test_pass
else
    test_fail "rc=$GUARD_RC pull=$(called pull && echo y || echo n)"
fi

# ── 4. Opt-in + within cap → pulls then runs ──────────────────────────────────
test_case "Opt-in pull within size cap proceeds then runs"
reset_state
export OCTOPUS_OLLAMA_ALLOW_PULL=true
export OCTOPUS_OLLAMA_MAX_PULL_GB=20
export FAKE_OLLAMA_PULL_GB="1.0"
unset FAKE_OLLAMA_PULL_SLOW || true
run_guard "small-model:1b"
if [[ "$GUARD_RC" -eq 0 ]] && called pull && called run; then
    test_pass
else
    test_fail "rc=$GUARD_RC pull=$(called pull && echo y || echo n) run=$(called run && echo y || echo n)"
fi
unset OCTOPUS_OLLAMA_ALLOW_PULL OCTOPUS_OLLAMA_MAX_PULL_GB FAKE_OLLAMA_PULL_GB || true

# ── 5. Opt-in + over cap → abort the pull, never run ──────────────────────────
test_case "Opt-in pull over size cap is aborted (no run)"
reset_state
export OCTOPUS_OLLAMA_ALLOW_PULL=true
export OCTOPUS_OLLAMA_MAX_PULL_GB=20
export FAKE_OLLAMA_PULL_GB="99"
export FAKE_OLLAMA_PULL_SLOW=1
run_guard "giant-model:120b"
if [[ "$GUARD_RC" -eq 75 ]] && called pull && ! called run \
   && [[ "$GUARD_ERR" == *"exceeds cap"* ]]; then
    test_pass
else
    test_fail "rc=$GUARD_RC run=$(called run && echo y || echo n) err=${GUARD_ERR:0:80}"
fi
unset OCTOPUS_OLLAMA_ALLOW_PULL OCTOPUS_OLLAMA_MAX_PULL_GB FAKE_OLLAMA_PULL_GB FAKE_OLLAMA_PULL_SLOW || true

# ── 6. No model argument → usage error ────────────────────────────────────────
test_case "Missing model argument exits 64"
reset_state
run_guard ""
if [[ "$GUARD_RC" -eq 64 ]]; then
    test_pass
else
    test_fail "rc=$GUARD_RC"
fi

# ── 7. Missing ollama binary → unavailable ────────────────────────────────────
test_case "Missing ollama binary exits 69"
GUARD_RC=0
printf 'x' | OCTOPUS_OLLAMA_BIN="$TMP/does-not-exist-ollama" "$HELPER" "anything" >/dev/null 2>&1 || GUARD_RC=$?
if [[ "$GUARD_RC" -eq 69 ]]; then
    test_pass
else
    test_fail "rc=$GUARD_RC"
fi

# ── 8. Dispatch routes Ollama through the guard shim (not a bare `ollama run`) ──
test_case "dispatch get_agent_command routes ollama through the guard shim"
(
    set +u
    log() { :; }
    export PLUGIN_DIR="$PROJECT_ROOT"
    source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
    get_agent_model() { echo "qwen2.5-coder:7b"; }
    cmd="$(get_agent_command ollama)"
    [[ "$cmd" == *"/scripts/helpers/ollama-run.sh qwen2.5-coder:7b" ]] && [[ "$cmd" != "ollama run"* ]]
) && test_pass || test_fail "ollama dispatch did not route through ollama-run.sh"

# ── 9. validate_agent_command accepts the shim path, rejects it when embedded ──
test_case "validate_agent_command accepts the ollama-run shim path"
(
    set +u
    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/utils.sh"
    validate_agent_command "$PROJECT_ROOT/scripts/helpers/ollama-run.sh qwen2.5-coder:7b" \
        && ! validate_agent_command "echo $PROJECT_ROOT/scripts/helpers/ollama-run.sh" 2>/dev/null
) && test_pass || test_fail "validate_agent_command did not gate the ollama-run shim correctly"

test_summary
