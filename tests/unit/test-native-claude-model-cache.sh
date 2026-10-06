#!/usr/bin/env bash
# Native Claude model overrides must not depend on shared cache history.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Native Claude model cache precedence"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/octopus-native-model.XXXXXX")"
trap 'rm -rf "$fixture"; cleanup_test_environment' EXIT
mkdir -p "$fixture/home" "$fixture/cache"
config="$fixture/providers.json"
cat > "$config" <<'JSON'
{
  "providers": {
    "claude": {"default": "claude-sonnet-5"},
    "codex": {"default": "gpt-5.6-sol"}
  },
  "routing": {"roles": {"verifier": {"provider": "claude", "model": "claude-opus-5"}}}
}
JSON
cache="$fixture/cache/octo-model-cache-test-native-model.json"

# Each call is a new shell, sharing only the owned persistent session cache.
resolve_child() {
    env -u OCTOPUS_COST_MODE -u OCTOPUS_TASK_CLASS -u OCTOPUS_MODEL_READ_ONLY \
        HOME="$fixture/home" USER=test CLAUDE_CODE_SESSION=native-model \
        TMPDIR="$fixture/cache" OCTOPUS_PROVIDERS_CONFIG="$config" \
        CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" OCTOPUS_ROUTING_POLICY=off \
        OCTOPUS_FABLE5_MODE=on OCTOPUS_FABLE5_FALLBACK_MODEL="${5:-claude-opus-5}" \
        CLAUDE_MODEL="${1:-}" OCTOPUS_CLAUDE_MODEL="${2:-}" OCTOPUS_CODEX_MODEL= \
        bash -c 'log() { :; }; source "$1/scripts/lib/model-resolver.sh";
                 resolve_octopus_model "$2" "$2" probe "$3"' \
        _ "$PLUGIN_DIR" "${3:-claude}" "${4:-}"
}
check_model() {
    test_case "$3"
    if [[ "$1" == "$2" ]]; then test_pass; else test_fail "expected [$2], got [$1]"; fi
}

check_model "$(resolve_child)" claude-sonnet-5 "fresh default populates the shared session cache"
cp "$cache" "$fixture/default-cache.json"
check_model "$(resolve_child claude-haiku-4-5-20251001)" claude-haiku-4-5-20251001 \
    "native override beats a default cached by another process"
test_case "native override leaves prior shared cache bytes unchanged"
if cmp -s "$fixture/default-cache.json" "$cache"; then test_pass; else test_fail "native override modified shared cache"; fi
check_model "$(resolve_child)" claude-sonnet-5 "removing native override retains the cached default"
check_model "$(resolve_child claude-haiku-4-5-20251001 claude-opus-5)" claude-opus-5 \
    "explicit Octopus provider pin beats native override and cached default"

rm -f "$cache"
check_model "$(resolve_child claude-haiku-4-5-20251001)" claude-haiku-4-5-20251001 \
    "native override resolves with an empty cache"
test_case "native override does not create a shared cache entry"
if [[ ! -e "$cache" ]]; then test_pass; else test_fail "native override created a cache entry"; fi
check_model "$(resolve_child)" claude-sonnet-5 "native override removal returns to the configured default"
check_model "$(resolve_child '' '' claude verifier)" claude-opus-5 "role route populates its own cache entry"
check_model "$(resolve_child claude-haiku-4-5-20251001 '' claude verifier)" claude-haiku-4-5-20251001 \
    "native override intentionally outranks a warm explicit role route"
check_model "$(resolve_child '' '' claude verifier)" claude-opus-5 "unsetting native override restores the role route"
check_model "$(resolve_child '' '' codex)" gpt-5.6-sol "non-Claude default populates its cache"
check_model "$(resolve_child claude-haiku-4-5-20251001 '' codex)" gpt-5.6-sol \
    "native Claude override leaves other providers unchanged"

test_case "native override bypasses process-local memory cache too"
if env -u OCTOPUS_TASK_CLASS -u OCTOPUS_MODEL_READ_ONLY HOME="$fixture/home" TMPDIR="$fixture/cache" USER=test CLAUDE_CODE_SESSION=native-model \
    OCTOPUS_PROVIDERS_CONFIG="$config" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    CLAUDE_MODEL= OCTOPUS_CLAUDE_MODEL= OCTOPUS_COST_MODE=standard OCTOPUS_ROUTING_POLICY=off \
    bash -c 'log() { :; }; source "$1/scripts/lib/model-resolver.sh";
             resolve_octopus_model claude claude memory > "$2" || exit 1;
             [[ "$(< "$2")" == claude-sonnet-5 ]] || exit 1;
             export CLAUDE_MODEL=claude-haiku-4-5-20251001;
             [[ "$(resolve_octopus_model claude claude memory)" == "$CLAUDE_MODEL" ]]' \
    _ "$PLUGIN_DIR" "$fixture/memory-default"; then
    test_pass
else
    test_fail "memory cache hid the native override"
fi

test_case "invalid native override is rejected even with a valid warm cache"
if resolve_child 'bad model' > "$fixture/invalid.out" 2> "$fixture/invalid.err"; then
    test_fail "warm cache masked an invalid native override"
elif [[ ! -s "$fixture/invalid.out" ]]; then
    test_pass
else
    test_fail "invalid native override produced a model"
fi

rm -f "$cache"
test_case "invalid native override is rejected with an empty cache too"
if resolve_child 'bad model' > "$fixture/invalid-empty.out" 2> "$fixture/invalid-empty.err"; then
    test_fail "empty cache admitted an invalid native override"
elif [[ ! -s "$fixture/invalid-empty.out" && ! -e "$cache" ]]; then
    test_pass
else
    test_fail "invalid native override produced output or cached state"
fi
check_model "$(resolve_child claude-fable-5-1 '' claude security-reviewer)" claude-opus-5 \
    "native model pin retains the existing Fable security reroute"


for cache_state in cold warm; do
    rm -f "$cache"
    if [[ "$cache_state" == warm ]]; then
        resolve_child '' '' claude security-reviewer > "$fixture/warm-security.out"
    fi
    test_case "invalid native Fable fallback is rejected with a $cache_state cache"
    if resolve_child claude-fable-5-1 '' claude security-reviewer 'bad model' \
        > "$fixture/bad-fallback-$cache_state.out" 2> "$fixture/bad-fallback-$cache_state.err"; then
        test_fail "invalid effective fallback was admitted"
    elif [[ ! -s "$fixture/bad-fallback-$cache_state.out" ]]; then
        test_pass
    else
        test_fail "invalid effective fallback reached model output"
    fi
    check_model "$(resolve_child claude-fable-5-1 '' claude security-reviewer)" claude-opus-5 \
        "valid native Fable fallback still resolves with a $cache_state cache"
    check_model "$(resolve_child '' '' claude security-reviewer)" claude-sonnet-5 \
        "removing a native Fable pin restores the configured model after $cache_state resolution"
done

test_case "explicit provider pins also reject an invalid effective Fable fallback"
if resolve_child '' claude-fable-5-1 claude security-reviewer 'bad model' \
    > "$fixture/bad-explicit-fallback.out" 2> "$fixture/bad-explicit-fallback.err"; then
    test_fail "explicit pin emitted an invalid effective fallback"
elif [[ ! -s "$fixture/bad-explicit-fallback.out" ]]; then
    test_pass
else
    test_fail "invalid explicit fallback reached model output"
fi

test_case "failed model reroute preserves its status and does not emit partial output"
if env HOME="$fixture/home" TMPDIR="$fixture/cache" USER=test CLAUDE_CODE_SESSION=native-model \
    OCTOPUS_PROVIDERS_CONFIG="$config" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" \
    CLAUDE_MODEL=claude-fable-5-1 OCTOPUS_CLAUDE_MODEL= OCTOPUS_COST_MODE=standard OCTOPUS_ROUTING_POLICY=off \
    bash -c 'log() { :; }; source "$1/scripts/lib/model-resolver.sh";
             fable5_maybe_reroute() { printf "partial-model\n"; return 47; };
             status=0;
             resolve_octopus_model claude claude probe security-reviewer > "$2" || status=$?;
             [[ "$status" -eq 47 && ! -s "$2" ]]' \
    _ "$PLUGIN_DIR" "$fixture/failed-reroute.out"; then
    test_pass
else
    test_fail "reroute failure was masked or emitted a model"
fi

test_summary
