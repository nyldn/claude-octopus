#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Provider-neutral design review ceremony"

TMP_HOME="$TEST_TMP_DIR/provider-neutral-design-review"
CHECKER="$TMP_HOME/check-providers.sh"
mkdir -p "$TMP_HOME/.claude-octopus/config"
cat >"$CHECKER" <<'EOF'
#!/bin/sh
cat <<'STATUS'
PROVIDER_CHECK_START
codex:available
commandcode:available
agy:missing
perplexity:missing
openrouter:missing
PROVIDER_CHECK_END
STATUS
EOF
chmod +x "$CHECKER"
cat >"$TMP_HOME/.claude-octopus/config/providers.json" <<'EOF'
{
  "version":"3.0",
  "providers": {
    "codex": {"default":"gpt-5.6-sol"},
    "commandcode": {
      "default":"deepseek/deepseek-v4-flash",
      "roles": {
        "researcher":"minimaxai/minimax-m3",
        "code-reviewer":"minimaxai/minimax-m3",
        "synthesizer":"minimaxai/minimax-m3"
      }
    },
    "claude": {"default":"claude-sonnet-5"}
  },
  "routing":{"phases":{},"roles":{}},
  "tiers":{},
  "overrides":{}
}
EOF

export HOME="$TMP_HOME"
export OCTOPUS_PROVIDER_CHECKER="$CHECKER"
export OCTO_ALLOWED_PROVIDERS="codex commandcode claude"
export PLUGIN_DIR="$PROJECT_ROOT"
export WORKSPACE_DIR="$TMP_HOME/workspace"
mkdir -p "$WORKSPACE_DIR"
source "$PROJECT_ROOT/scripts/lib/quality.sh"

test_case "design review defaults use the provider-neutral council pool"
defaults="$(design_review_default_agents test)"
if [[ "$defaults" == $'claude-sonnet\ncodex\ncommandcode\nclaude-sonnet' ]]; then
  test_pass
else
  test_fail "expected exact admitted provider sequence, got: $(tr '\n' '|' <<< "$defaults")"
fi

test_case "design review defaults fail closed when the allowlist admits no available provider"
defaults=""
if defaults="$(OCTO_ALLOWED_PROVIDERS=agy design_review_default_agents test)"; then
  test_fail "provider discovery unexpectedly succeeded with no admitted provider: $defaults"
elif [[ -z "$defaults" ]]; then
  test_pass
else
  test_fail "failed discovery emitted an unadmitted fallback: $defaults"
fi

test_case "invalid council provider policy prevents design review defaults"
defaults=""
if defaults="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=codex,codex design_review_default_agents test)"; then
  test_fail "invalid duplicate provider policy unexpectedly succeeded: $defaults"
elif [[ -z "$defaults" ]]; then
  test_pass
else
  test_fail "invalid policy emitted fallback providers: $defaults"
fi

test_case "design review assigns providers independently from semantic roles"
CAPTURE="$TMP_HOME/design-review.calls"
: > "$CAPTURE"
DRY_RUN=false
OCTOPUS_CEREMONIES=true
CYAN="" GREEN="" NC="" _BOX_TOP="" _BOX_BOT=""
log() { :; }
octo_provider_identity_label() { printf '%s / fixture\n' "$1"; }
write_structured_decision() { :; }
run_agent_sync_consultative() {
  printf '%s|%s|%s\n' "$1" "$4" "$5" >> "$CAPTURE"
  printf '%s\n' 'planning output'
}
design_review_ceremony "test" >/dev/null
roles="$(cut -d'|' -f2 "$CAPTURE" | tr '\n' '|')"
providers="$(cut -d'|' -f1 "$CAPTURE" | tr '\n' '|')"
expected_calls=$'claude-sonnet|implementer|ceremony\ncodex|researcher|ceremony\ncommandcode|code-reviewer|ceremony\nclaude-sonnet|synthesizer|ceremony'
if [[ "$(<"$CAPTURE")" == "$expected_calls" ]]; then
  test_pass
else
  test_fail "expected exact provider/role ceremony sequence; roles=$roles providers=$providers calls=$(tr '\n' ';' < "$CAPTURE")"
fi

test_case "explicit design-review override cannot bypass the provider allowlist"
: > "$CAPTURE"
override_rc=0
OCTO_ALLOWED_PROVIDERS=codex \
OCTOPUS_DESIGN_REVIEW_RESEARCHER_AGENT=agy \
  design_review_ceremony "test" >/dev/null 2>&1 || override_rc=$?
if [[ "$override_rc" -ne 0 && ! -s "$CAPTURE" ]]; then
  test_pass
else
  test_fail "disallowed override was dispatched or ceremony did not fail closed: rc=$override_rc calls=$(tr '\n' ';' < "$CAPTURE")"
fi

test_case "provider-local model keeps provider identity separate from role model"
log() { :; }
export OCTOPUS_PLATFORM=Linux
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
model="$(resolve_octopus_model commandcode commandcode ceremony researcher)"
if [[ "$model" == "minimaxai/minimax-m3" ]]; then
  test_pass
else
  test_fail "expected provider-local MiniMax researcher model, got '$model'"
fi

test_summary
