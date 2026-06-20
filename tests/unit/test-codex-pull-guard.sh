#!/usr/bin/env bash
# Test: codex-run.sh guard against the codex CLI's built-in OSS/local-model
# auto-pull (the SECOND unbounded-`ollama pull` vector — distinct from Octopus's
# own ollama provider, which ollama-run.sh already guards). Verifies the shim
# FAILS CLOSED when codex is pinned to an absent gpt-oss/local model unless the
# user has explicitly opted into downloads, enforces a size cap when pulls are
# allowed, leaves cloud codex models untouched, and that dispatch routes an
# OSS-model codex through the shim (not a bare `codex exec`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Codex OSS auto-pull guard"

SHIM="$PROJECT_ROOT/scripts/helpers/codex-run.sh"
TMP="$TEST_TMP_DIR/codex-guard"
mkdir -p "$TMP"
FAKE_OLLAMA="$TMP/ollama"
FAKE_CODEX="$TMP/codex"
ERRF="$TMP/stderr.txt"

# ── A fake `ollama` CLI (same shape as test-ollama-pull-guard.sh): `list`
#    reports models named in $FAKE_OLLAMA_STATE; `pull` emits a progress line
#    carrying a configurable total size, optionally stalls, then registers the
#    model. Every subcommand is appended to $FAKE_OLLAMA_LOG. ──
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

# ── A fake `codex` CLI. A REAL codex pinned to an absent gpt-oss model would
#    itself trigger an unbounded `ollama pull` — this fake does NOT, so "codex
#    ran" in a test means the guard let execution through. It consumes the prompt
#    on stdin, records the call, and echoes a marker with the resolved model. ──
cat > "$FAKE_CODEX" <<'SH'
#!/usr/bin/env bash
printf 'codex %s\n' "$*" >> "$FAKE_CODEX_LOG"
cat >/dev/null 2>&1 || true   # consume the prompt on stdin
model=""; prev=""
for a in "$@"; do
  case "$prev" in --model|-m) model="$a";; esac
  case "$a" in --model=*) model="${a#--model=}";; -m=*) model="${a#-m=}";; esac
  prev="$a"
done
echo "CODEX_RAN:${model}"
SH
chmod +x "$FAKE_CODEX"

export FAKE_OLLAMA_STATE="$TMP/state"
export FAKE_OLLAMA_LOG="$TMP/ollama-calls.log"
export FAKE_CODEX_LOG="$TMP/codex-calls.log"

reset_state() { : > "$FAKE_OLLAMA_STATE"; : > "$FAKE_OLLAMA_LOG"; : > "$FAKE_CODEX_LOG"; }
seed_model()  { printf '%s\n' "$1" >> "$FAKE_OLLAMA_STATE"; }
ollama_called() { grep -q "^$1 " "$FAKE_OLLAMA_LOG" 2>/dev/null; }
codex_ran()     { grep -q "^codex " "$FAKE_CODEX_LOG" 2>/dev/null; }

# Run the shim wrapping the fake codex, exactly as dispatch would build the argv.
# Captures GRC / GOUT / GERR.
run_codex_guard() {
    local m="$1"
    GRC=0
    GOUT="$(printf 'test-prompt' | OCTOPUS_OLLAMA_BIN="$FAKE_OLLAMA" "$SHIM" \
        "$FAKE_CODEX" exec --skip-git-repo-check --model "$m" --sandbox workspace-write - \
        2>"$ERRF")" || GRC=$?
    GERR="$(cat "$ERRF" 2>/dev/null || true)"
}

# ── 1. Absent OSS model + no opt-in → refuse, NO ollama pull, codex never runs ─
test_case "Absent OSS model without opt-in is refused (no pull, no codex)"
reset_state
unset OCTOPUS_OLLAMA_ALLOW_PULL || true
run_codex_guard "gpt-oss:120b"
if [[ "$GRC" -eq 70 ]] && ! ollama_called pull && ! codex_ran \
   && [[ "$GERR" == *"Refusing to auto-pull"* ]]; then
    test_pass
else
    test_fail "rc=$GRC pull=$(ollama_called pull && echo y || echo n) codex=$(codex_ran && echo y || echo n) err=${GERR:0:80}"
fi

# ── 2. OSS model already present in ollama → codex runs directly, never pulls ──
test_case "Present OSS model lets codex run without pulling"
reset_state
seed_model "gpt-oss:120b"
unset OCTOPUS_OLLAMA_ALLOW_PULL || true
run_codex_guard "gpt-oss:120b"
if [[ "$GRC" -eq 0 ]] && codex_ran && ! ollama_called pull \
   && [[ "$GOUT" == *"CODEX_RAN:gpt-oss:120b"* ]]; then
    test_pass
else
    test_fail "rc=$GRC out=${GOUT:0:80} pull=$(ollama_called pull && echo y || echo n)"
fi

# ── 3. Cloud (non-OSS) model → codex runs directly, ollama never touched ───────
test_case "Cloud codex model bypasses the guard entirely"
reset_state
unset OCTOPUS_OLLAMA_ALLOW_PULL || true
run_codex_guard "gpt-5.4"
if [[ "$GRC" -eq 0 ]] && codex_ran && ! ollama_called list && ! ollama_called pull \
   && [[ "$GOUT" == *"CODEX_RAN:gpt-5.4"* ]]; then
    test_pass
else
    test_fail "rc=$GRC out=${GOUT:0:80} list=$(ollama_called list && echo y || echo n)"
fi

# ── 4. Opt-in + within cap → ollama pulls, then codex runs ─────────────────────
test_case "Opt-in OSS pull within size cap proceeds then runs codex"
reset_state
export OCTOPUS_OLLAMA_ALLOW_PULL=true
export OCTOPUS_OLLAMA_MAX_PULL_GB=20
export FAKE_OLLAMA_PULL_GB="1.0"
unset FAKE_OLLAMA_PULL_SLOW || true
run_codex_guard "gpt-oss:20b"
if [[ "$GRC" -eq 0 ]] && ollama_called pull && codex_ran; then
    test_pass
else
    test_fail "rc=$GRC pull=$(ollama_called pull && echo y || echo n) codex=$(codex_ran && echo y || echo n)"
fi
unset OCTOPUS_OLLAMA_ALLOW_PULL OCTOPUS_OLLAMA_MAX_PULL_GB FAKE_OLLAMA_PULL_GB || true

# ── 5. Opt-in + over cap → abort the pull, codex never runs ────────────────────
test_case "Opt-in OSS pull over size cap is aborted (no codex)"
reset_state
export OCTOPUS_OLLAMA_ALLOW_PULL=true
export OCTOPUS_OLLAMA_MAX_PULL_GB=20
export FAKE_OLLAMA_PULL_GB="99"
export FAKE_OLLAMA_PULL_SLOW=1
run_codex_guard "gpt-oss:120b"
if [[ "$GRC" -eq 75 ]] && ollama_called pull && ! codex_ran \
   && [[ "$GERR" == *"exceeds cap"* ]]; then
    test_pass
else
    test_fail "rc=$GRC codex=$(codex_ran && echo y || echo n) err=${GERR:0:80}"
fi
unset OCTOPUS_OLLAMA_ALLOW_PULL OCTOPUS_OLLAMA_MAX_PULL_GB FAKE_OLLAMA_PULL_GB FAKE_OLLAMA_PULL_SLOW || true

# ── 6. Empty argv → usage error ───────────────────────────────────────────────
test_case "Missing codex command exits 64"
GRC=0
printf 'x' | OCTOPUS_OLLAMA_BIN="$FAKE_OLLAMA" "$SHIM" >/dev/null 2>&1 || GRC=$?
if [[ "$GRC" -eq 64 ]]; then
    test_pass
else
    test_fail "rc=$GRC"
fi

# ── 7. OSS model matcher classifies gpt-oss/tagged as OSS, cloud models as not ─
test_case "_codex_model_is_oss matcher classifies models correctly"
(
    set +u
    source "$SHIM"   # source-guarded: loads functions, runs no work
    _codex_model_is_oss "gpt-oss:120b" \
        && _codex_model_is_oss "GPT-OSS:20B" \
        && _codex_model_is_oss "qwen2.5-coder:7b" \
        && ! _codex_model_is_oss "gpt-5.4" \
        && ! _codex_model_is_oss "o3" \
        && ! _codex_model_is_oss "gpt-5.2-codex" \
        && ! _codex_model_is_oss ""
) && test_pass || test_fail "OSS model matcher misclassified a model"

# ── 8. Dispatch routes an OSS-model codex through the shim, cloud models direct ─
test_case "dispatch get_agent_command routes OSS codex through codex-run.sh"
(
    set +u
    log() { :; }
    export PLUGIN_DIR="$PROJECT_ROOT"
    source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
    get_agent_model() { echo "gpt-oss:120b"; }
    cmd="$(get_agent_command codex)"
    [[ "$cmd" == *"/scripts/helpers/codex-run.sh "* ]] \
        && [[ "$cmd" == *"codex exec --skip-git-repo-check --model gpt-oss:120b"* ]]
) && test_pass || test_fail "OSS codex dispatch did not route through codex-run.sh"

test_case "dispatch leaves cloud codex models as a bare codex exec"
(
    set +u
    log() { :; }
    export PLUGIN_DIR="$PROJECT_ROOT"
    source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
    get_agent_model() { echo "gpt-5.4"; }
    cmd="$(get_agent_command codex)"
    [[ "$cmd" == "codex exec --skip-git-repo-check --model gpt-5.4 --sandbox workspace-write -" ]] \
        && [[ "$cmd" != *codex-run.sh* ]]
) && test_pass || test_fail "cloud codex dispatch was unexpectedly wrapped"

# ── 9. validate_agent_command accepts the shim path, rejects it when embedded ──
test_case "validate_agent_command accepts the codex-run shim path"
(
    set +u
    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/utils.sh"
    validate_agent_command "$PROJECT_ROOT/scripts/helpers/codex-run.sh codex exec --model gpt-oss:120b -" \
        && ! validate_agent_command "echo $PROJECT_ROOT/scripts/helpers/codex-run.sh" 2>/dev/null
) && test_pass || test_fail "validate_agent_command did not gate the codex-run shim correctly"

# ── 10. build_provider_env forwards the pull-guard opt-in into codex's env ─────
test_case "build_provider_env forwards OCTOPUS_OLLAMA_* into the isolated codex env"
(
    set +u
    log() { :; }
    log_warn() { :; }
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
    export OCTOPUS_OLLAMA_ALLOW_PULL=true
    export OCTOPUS_OLLAMA_MAX_PULL_GB=15
    build_provider_env codex
    joined="${PROVIDER_ENV_ARRAY[*]}"
    [[ "$joined" == *"OCTOPUS_OLLAMA_ALLOW_PULL=true"* ]] \
        && [[ "$joined" == *"OCTOPUS_OLLAMA_MAX_PULL_GB=15"* ]]
) && test_pass || test_fail "codex isolated env did not carry the pull-guard opt-in"

test_summary
