#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

test_suite "configurable fallback chains"

TMP_ROOT="$TEST_TMP_DIR"
CFG="$TEST_TMP_DIR/providers.json"
mkdir -p "$TEST_TMP_DIR/model-cache"
export TMPDIR="$TEST_TMP_DIR/model-cache"
export OCTOPUS_PROVIDERS_CONFIG="$CFG"

write_config() {
    cat > "$CFG" <<'JSON'
{
  "providers": {
    "codex": {
      "default": "gpt-5.6-terra",
      "council": "gpt-5.5"
    },
    "claude": {
      "default": "claude-sonnet-5"
    }
  },
  "routing": {
    "roles": {
      "code-reviewer": {"provider":"codex","model":"gpt-5.6-luna"},
      "implementer-heavy": {"provider":"codex","model":"gpt-5.6-sol"},
      "architect": {"provider":"claude","model":"claude-opus-4.8"}
    }
  }
}
JSON
}
write_config

test_case "built-in default chain is code-reviewer -> implementer-heavy -> architect"
chain=$(octo_fallback_builtin_chain_json default | jq -r '[.[].role] | join(",")')
if [[ "$chain" == "code-reviewer,implementer-heavy,architect" ]]; then test_pass; else test_fail "unexpected default: $chain"; fi

test_case "default roles resolve through routing.roles provider and model"
specs=$(octo_fallback_chain_agent_specs default)
expected=$'codex:gpt-5.6-luna\ncodex:gpt-5.6-sol\nclaude:claude-opus-4.8'
if [[ "$specs" == "$expected" ]]; then test_pass; else test_fail "unexpected specs: [$specs]"; fi

test_case "built-in role defaults remain bare so session model precedence is preserved"
printf '%s\n' '{"routing":{"fallbackChains":{"default":[{"role":"code-reviewer"}]}}}' > "$CFG"
specs=$(octo_fallback_chain_agent_specs default)
resolved=$(OCTOPUS_CODEX_MODEL=gpt-session-override resolve_octopus_model codex "$specs" "tangle" "code-reviewer")
if [[ "$specs" == "codex-review" && "$resolved" == "gpt-session-override" ]]; then
    test_pass
else
    test_fail "role default became an exact pin or bypassed session precedence: spec=[$specs] model=[$resolved]"
fi
write_config

test_case "session model overrides beat configured fallback role models"
printf '%s\n' '{"routing":{"roles":{"code-reviewer":{"provider":"codex","model":"gpt-role-default"}},"fallbackChains":{"default":[{"role":"code-reviewer"}]}}}' > "$CFG"
specs=$(OCTOPUS_CODEX_MODEL=gpt-session-override octo_fallback_chain_agent_specs default)
if [[ "$specs" == "codex:gpt-session-override" ]]; then
    test_pass
else
    test_fail "configured role model bypassed session precedence: [$specs]"
fi
write_config

test_case "session model overrides beat legacy string role models"
printf '%s\n' '{"routing":{"roles":{"code-reviewer":"gpt-role-default"},"fallbackChains":{"default":[{"role":"code-reviewer"}]}}}' > "$CFG"
specs=$(OCTOPUS_CODEX_MODEL=gpt-session-override octo_fallback_chain_agent_specs default)
if [[ "$specs" == "codex-review:gpt-session-override" ]]; then
    test_pass
else
    test_fail "legacy role model bypassed session precedence: [$specs]"
fi
write_config

test_case "bare-provider role routes clear the inherited static-role model"
jq '.routing.roles["code-reviewer"]="claude" | .routing.fallbackChains.default=[{"role":"code-reviewer"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
specs=$(octo_fallback_chain_agent_specs default)
if [[ "$specs" == "claude" ]]; then test_pass; else test_fail "bare provider retained the prior role model: [$specs]"; fi

test_case "legacy agy-research role routes remain on the AGY provider"
jq '.routing.roles["code-reviewer"]="agy-research" | .routing.fallbackChains.default=[{"role":"code-reviewer"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
specs=$(octo_fallback_chain_agent_specs default)
if [[ "$specs" == "agy" ]]; then test_pass; else test_fail "agy-research was treated as a model or rerouted: [$specs]"; fi

test_case "provider capability role routes resolve to a concrete model"
jq '.routing.roles["code-reviewer"]="codex:council" | .routing.fallbackChains.default=[{"role":"code-reviewer"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
specs=$(octo_fallback_chain_agent_specs default)
if [[ "$specs" == "codex:gpt-5.5" ]]; then test_pass; else test_fail "provider capability was not recursively resolved: [$specs]"; fi
write_config

test_case "providers.json may replace the fallback chain"
jq '.routing.fallbackChains.default=[{"role":"architect"},{"provider":"commandcode","model":"custom/model"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
specs=$(octo_fallback_chain_agent_specs default)
expected=$'claude:claude-opus-4.8\ncommandcode:custom/model'
if [[ "$specs" == "$expected" ]]; then test_pass; else test_fail "override not honored: [$specs]"; fi

test_case "configured fallback cannot select explicit-only Astra without an invocation grant"
jq '.routing.fallbackChains.default=[{"provider":"codex","model":"gpt-6-astra"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
specs=""
rc=0
specs=$(octo_fallback_chain_agent_specs default review 2>/dev/null) || rc=$?
if [[ "$rc" -ne 0 && -z "$specs" ]]; then
    test_pass
else
    test_fail "automatic fallback admitted Astra: rc=$rc specs=[$specs]"
fi

test_case "invocation-scoped fallback grant admits only its exact frontier model"
specs=$(octo_fallback_chain_agent_specs default review gpt-6-astra 2>/dev/null || true)
if [[ "$specs" == "codex:gpt-6-astra" ]]; then
    test_pass
else
    test_fail "exact invocation grant did not admit Astra: [$specs]"
fi

test_case "provider-native Astra namespace remains explicit-only in fallback chains"
jq '.routing.fallbackChains.default=[{"provider":"commandcode","model":"openai/gpt-6-astra"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
specs=""
rc=0
specs=$(octo_fallback_chain_agent_specs default review 2>/dev/null) || rc=$?
if [[ "$rc" -ne 0 && -z "$specs" ]]; then
    test_pass
else
    test_fail "provider-native Astra bypassed fallback admission: rc=$rc specs=[$specs]"
fi
write_config

test_case "provider aliases canonicalize and equivalent candidates are deduplicated"
printf '%s\n' '{"routing":{"fallbackChains":{"default":[{"provider":"anthropic","model":"claude-opus-4.8"},{"provider":"agy"},{"provider":"antigravity"},{"provider":"gemini"}]}}}' > "$CFG"
specs=$(octo_fallback_chain_agent_specs default)
expected=$'claude:claude-opus-4.8\nagy'
if [[ "$specs" == "$expected" ]]; then
    test_pass
else
    test_fail "aliases were rejected or retried: [$specs]"
fi

assert_invalid_chain_fails_closed() {
    local description="$1" contents="$2" output="" rc=0
    test_case "$description"
    printf '%s\n' "$contents" > "$CFG"
    output=$(octo_fallback_chain_agent_specs default 2>/dev/null) || rc=$?
    if [[ "$rc" -ne 0 && -z "$output" ]]; then
        test_pass
    else
        test_fail "invalid chain fell back or partially dispatched: rc=$rc output=[$output]"
    fi
}

assert_invalid_chain_fails_closed \
    "malformed providers JSON fails closed" \
    '{"routing":{"fallbackChains":'
assert_invalid_chain_fails_closed \
    "wrong fallback chain type fails closed" \
    '{"routing":{"fallbackChains":{"default":{"attempts":"codex"}}}}'
assert_invalid_chain_fails_closed \
    "wrong routing object type fails closed" \
    '{"routing":"codex"}'
assert_invalid_chain_fails_closed \
    "wrong routing roles type fails closed" \
    '{"routing":{"roles":"broken"}}'
assert_invalid_chain_fails_closed \
    "wrong routing phases type fails closed" \
    '{"routing":{"phases":["codex"]}}'
assert_invalid_chain_fails_closed \
    "unknown fallback role fails closed" \
    '{"routing":{"fallbackChains":{"default":[{"role":"made-up-role"}]}}}'
assert_invalid_chain_fails_closed \
    "invalid fallback candidate fails the whole chain" \
    '{"routing":{"fallbackChains":{"default":[{"provider":"claude"},{"provider":"not-a-provider"}]}}}'

test_case "malformed nested routing blocks every runtime dispatch"
printf '%s\n' '{"routing":{"roles":"broken"}}' > "$CFG"
dispatch_marker="$TEST_TMP_DIR/malformed-routing-dispatched"
rm -f "$dispatch_marker"
malformed_rc=0
malformed_output="$({
    run_agent_sync() {
        : > "$dispatch_marker"
        printf '%s\n' 'usable result'
    }
    run_agent_sync_fallback_chain agy 'plan it' 30 researcher tangle '' default
} 2>/dev/null)" || malformed_rc=$?
if [[ "$malformed_rc" -ne 0 && -z "$malformed_output" && ! -e "$dispatch_marker" ]]; then
    test_pass
else
    test_fail "malformed nested routing dispatched: rc=$malformed_rc output=[$malformed_output]"
fi

write_config
is_agent_available_v2() { [[ "$1" == "claude" ]]; }
test_case "technical availability uses the same configured/default chain"
chosen=$(octo_fallback_first_available default commandcode)
if [[ "$chosen" == "claude:claude-opus-4.8" ]]; then test_pass; else test_fail "expected qualified claude spec, got $chosen"; fi

test_case "technical fallback prefers fail-closed v2 availability when present"
is_agent_available() { return 0; }
is_agent_available_v2() { [[ "$1" == "claude" ]]; }
chosen=$(octo_fallback_first_available default commandcode)
if [[ "$chosen" == "claude:claude-opus-4.8" ]]; then test_pass; else test_fail "legacy fail-open availability leaked into fallback selection: $chosen"; fi

test_case "technical fallback fails closed when v2 availability is absent"
unset -f is_agent_available_v2
is_agent_available() { return 0; }
chain_specs="$(octo_fallback_chain_agent_specs default)"
if [[ -z "$chain_specs" ]]; then
  test_fail "default fallback chain unexpectedly empty; fail-closed assertion would be vacuous"
elif chosen=$(octo_fallback_first_available default commandcode); then
  test_fail "legacy fail-open availability selected an unverified fallback: $chosen"
else
  test_pass
fi
is_agent_available_v2() { [[ "$1" == "claude" ]]; }

test_case "technical fallback preserves explicit provider:model candidates"
jq '.routing.fallbackChains.default=[{"provider":"claude","model":"claude-opus-4.8"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
chosen=$(octo_fallback_first_available default commandcode)
if [[ "$chosen" == "claude:claude-opus-4.8" ]]; then test_pass; else test_fail "explicit model was lost: $chosen"; fi
write_config

test_case "technical fallback rejects a chain containing an invalid qualified candidate"
jq '.routing.fallbackChains.default=[{"provider":"claude","model":"bad model"},{"provider":"claude","model":"claude-opus-4.8"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
chosen=""
rc=0
chosen=$(octo_fallback_first_available default commandcode) || rc=$?
if [[ "$rc" -ne 0 && -z "$chosen" ]]; then test_pass; else test_fail "invalid qualified candidate was skipped: rc=$rc chosen=[$chosen]"; fi

test_case "technical fallback fails closed when every qualified candidate is invalid"
jq '.routing.fallbackChains.default=[{"provider":"claude","model":"bad model"},{"provider":"claude","model":"also\tbad"}]' "$CFG" > "$CFG.tmp"
mv "$CFG.tmp" "$CFG"
if chosen=$(octo_fallback_first_available default commandcode); then
  test_fail "invalid qualified chain selected a candidate: $chosen"
else
  test_pass
fi
write_config

ATTEMPTS="$TMP_ROOT/attempts.log"
: > "$ATTEMPTS"
validate_protocol() {
    [[ "$1" == *"DECISIONS:"* && "$1" == *"DECOMPOSITION:"* ]]
}
run_agent_sync() {
    local spec="$1" role="$4" phase="$5"
    printf '%s|%s|%s\n' "$spec" "$role" "$phase" >> "$ATTEMPTS"
    case "$spec" in
        commandcode:primary) printf '   \n'; return 0 ;;
        codex:gpt-5.6-luna) printf 'I will inspect this first.\n'; return 0 ;;
        codex:gpt-5.6-sol) printf 'DECISIONS:\n- ACCEPT fix\nDECOMPOSITION:\n1. [CODING] valid\n'; return 0 ;;
        claude:claude-opus-4.8) printf 'DECISIONS:\n- ACCEPT last\nDECOMPOSITION:\n1. [CODING] last\n'; return 0 ;;
        commandcode:technical-fail) return 42 ;;
        *) return 7 ;;
    esac
}
log() { :; }

test_case "empty and semantically invalid success both advance the same chain"
: > "$ATTEMPTS"
out=$(run_agent_sync_fallback_chain commandcode:primary 'plan it' 30 researcher tangle validate_protocol default)
count=$(wc -l < "$ATTEMPTS" | tr -d ' ')
roles=$(cut -d'|' -f2 "$ATTEMPTS" | sort -u)
phases=$(cut -d'|' -f3 "$ATTEMPTS" | sort -u)
if [[ "$out" == *"DECOMPOSITION:"* && "$count" -eq 3 && "$roles" == "researcher" && "$phases" == "tangle" ]]; then
    test_pass
else
    test_fail "semantic fallback failed: count=$count roles=$roles phases=$phases out=[$out]"
fi

test_case "process failure advances through the same chain"
: > "$ATTEMPTS"
out=$(run_agent_sync_fallback_chain commandcode:technical-fail 'plan it' 30 researcher tangle validate_protocol default)
first=$(sed -n '1p' "$ATTEMPTS" | cut -d'|' -f1)
second=$(sed -n '2p' "$ATTEMPTS" | cut -d'|' -f1)
if [[ "$first" == "commandcode:technical-fail" && "$second" == "codex:gpt-5.6-luna" && "$out" == *"DECOMPOSITION:"* ]]; then
    # Luna is semantically invalid, so Sol should ultimately satisfy the validator.
    [[ $(wc -l < "$ATTEMPTS") -eq 3 ]] && test_pass || test_fail "expected three attempts"
else
    test_fail "technical fallback did not use common chain"
fi

test_case "chain exhausts and fails closed when every candidate is unusable"
run_agent_sync() {
    printf '%s\n' "$1" >> "$ATTEMPTS"
    printf 'not-valid\n'
    return 0
}
: > "$ATTEMPTS"
rc=0
run_agent_sync_fallback_chain commandcode:primary 'plan it' 30 researcher tangle validate_protocol default >/dev/null || rc=$?
if [[ "$rc" -ne 0 ]] && grep -c 'claude:claude-opus-4.8' "$ATTEMPTS" >/dev/null; then test_pass; else test_fail "chain did not exhaust safely"; fi

test_case "runtime, empty, and semantic failures use one real decomposition fallback path"
if (
    : > "$ATTEMPTS"
    tangle_decomposition_output_usable() { validate_protocol "$1"; }
    octo_fallback_chain_agent_specs() {
        printf '%s\n' agy antigravity gemini codex:gpt-5.6-luna codex:gpt-5.6-sol
    }
    run_agent_sync() {
        local spec="$1" role="$4" phase="$5"
        printf '%s|%s|%s\n' "$spec" "$role" "$phase" >> "$ATTEMPTS"
        case "$spec" in
            commandcode:primary) return 42 ;;
            codex:gpt-5.5) printf '   \n' ;;
            agy) printf 'not a decomposition\n' ;;
            codex:gpt-5.6-luna) printf 'still not a decomposition\n' ;;
            codex:gpt-5.6-sol) printf 'DECISIONS:\n- ACCEPT\nDECOMPOSITION:\n1. [CODING] valid\n' ;;
            *) return 7 ;;
        esac
    }
    out=$(tangle_run_decomposition_fallbacks commandcode:primary codex:gpt-5.5 'plan it' 30)
    attempted_specs=$(cut -d'|' -f1 "$ATTEMPTS" | paste -sd, -)
    [[ "$out" == *"DECOMPOSITION:"* ]] && \
        [[ "$attempted_specs" == "commandcode:primary,codex:gpt-5.5,agy,codex:gpt-5.6-luna,codex:gpt-5.6-sol" ]]
); then
    test_pass
else
    test_fail "real fallback path did not handle all failure classes or deduplicate aliases"
fi

test_summary
