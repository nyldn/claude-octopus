#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/tests/helpers/test-framework.sh"
test_suite 'Claude native integrations'
log() { :; }
source "$PROJECT_ROOT/scripts/lib/providers.sh"
source "$PROJECT_ROOT/scripts/lib/utils.sh"
source "$PROJECT_ROOT/scripts/lib/validation.sh"
source "$PROJECT_ROOT/scripts/lib/model-cache-path.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/agents.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
source "$PROJECT_ROOT/scripts/lib/routing.sh"
source "$PROJECT_ROOT/scripts/lib/auto-route.sh"
export PLUGIN_DIR="$PROJECT_ROOT" OCTOPUS_DISPATCH_PREVIEW=true
export _BARE_OPT=''
export OCTOPUS_PROVIDERS_CONFIG="$TEST_TMP_DIR/providers.json"
printf '%s\n' '{}' > "$OCTOPUS_PROVIDERS_CONFIG"
unset OCTOPUS_CLAUDE_BIN OCTOPUS_CLAUDE_ADVISOR OCTOPUS_REFINEMENT_JUDGE
unset OCTOPUS_REASONING_LEVEL OCTOPUS_REASONING_POLICY OCTOPUS_OPUS_MODEL
export SUPPORTS_SONNET_5_5=true SUPPORTS_OPUS_5=true
export CLAUDE_CODE_VERSION=2.1.319

test_case 'default worker launch preserves its existing advisor configuration'
cmd="$(get_agent_command claude-sonnet develop implementer 128)"
if [[ "$cmd" != *--advisor* ]] && validate_agent_command "$cmd"; then test_pass; else test_fail "$cmd"; fi

test_case 'explicit advisor reaches validated real argv without changing the worker model'
export OCTOPUS_CLAUDE_ADVISOR=opus
cmd="$(get_agent_command claude-sonnet develop implementer 128)"
if [[ "$cmd" == *'--model claude-sonnet-5-5 '* && "$cmd" == *'--advisor opus' ]] && validate_agent_command "$cmd"; then
    mkdir -p "$TEST_TMP_DIR/bin"
    cat > "$TEST_TMP_DIR/bin/claude" <<'FIXTURE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$OCTO_TEST_ARGV"
FIXTURE
    chmod +x "$TEST_TMP_DIR/bin/claude"
    octo_dispatch_command_to_argv "$cmd"
    OCTO_TEST_ARGV="$TEST_TMP_DIR/argv" PATH="$TEST_TMP_DIR/bin:$PATH" "${OCTO_COMMAND_ARGV[@]}"
    if [[ "$(grep -cx -- --advisor "$TEST_TMP_DIR/argv")" == 1 ]] && grep -qx opus "$TEST_TMP_DIR/argv"; then test_pass; else test_fail 'lost advisor argv'; fi
else test_fail "$cmd"; fi

for version in 2.1.259 '' invalid; do
    test_case "explicit advisor fails on unsupported version '$version'"
    if CLAUDE_CODE_VERSION="$version" get_agent_command claude-sonnet develop implementer 128 >/dev/null 2>&1; then test_fail 'accepted unproven host'; else test_pass; fi
done

test_case 'documented headless floor is accepted even though help hides the flag'
if [[ "$(CLAUDE_CODE_VERSION=2.1.260 octo_claude_advisor_fragment claude-sonnet)" == '--advisor opus' ]]; then test_pass; else test_fail 'floor rejected'; fi

for value in 'opus --permission-mode bypassPermissions' 'opus;id' 'claude-foo/bar' 'claude-$(id)' '--advisor' 'haiku'; do
    test_case "reject malformed or unsupported advisor value: $value"
    if OCTOPUS_CLAUDE_ADVISOR="$value" get_agent_command claude-sonnet >/dev/null 2>&1; then test_fail 'unsafe value accepted'; else test_pass; fi
done

test_case 'validator rejects duplicate and injected advisor arguments'
if validate_agent_command "$cmd --advisor sonnet" || validate_agent_command "${cmd%opus}opus;id"; then test_fail 'unsafe command accepted'; else test_pass; fi

test_case 'fixed judges override enabled and saved advisors'
judge_cmd="$(OCTOPUS_REFINEMENT_JUDGE=true get_agent_command claude-sonnet probe reviewer 128)"
if [[ "$judge_cmd" == *'--advisor off' && "$judge_cmd" != *'--advisor opus'* ]] && validate_agent_command "$judge_cmd"; then test_pass; else test_fail "$judge_cmd"; fi

test_case 'exact model seats disable additional advisors'
exact_cmd="$(get_agent_command claude-sonnet:claude-sonnet-5-5 probe reviewer 128)"
if [[ "$exact_cmd" == *'--advisor off' ]] && validate_agent_command "$exact_cmd"; then test_pass; else test_fail "$exact_cmd"; fi

for advisor in off sonnet fable claude-opus-5-5; do
    test_case "accepted advisor value $advisor"
    if [[ "$(OCTOPUS_CLAUDE_ADVISOR="$advisor" octo_claude_advisor_fragment claude)" == "--advisor $advisor" ]]; then test_pass; else test_fail "$advisor"; fi
done

for prompt in 'refine this plan' 'iteratively improve this specification' 'improve this plan using a rubric' 'improve this deck to 95/100'; do
    test_case "explicit refinement handoff: $prompt"
    if [[ "$(classify_task "$prompt")" == native-refine ]]; then test_pass; else test_fail "$(classify_task "$prompt")"; fi
done
for prompt in 'improve this plan' 'improve this plan without rubric scoring' 'define the refine variable' 'improve this plan with a security audit' 'refine this plan with all providers' 'refine this plan in parallel'; do
    test_case "ordinary edits and higher-priority intents keep their route: $prompt"
    if [[ "$(classify_task "$prompt")" != native-refine ]]; then test_pass; else test_fail 'unwanted judging workflow'; fi
done

test_case 'refine route is allowlisted and paths are rejected'
if [[ "$(auto_route_validate_workflow refine)" == refine ]] && ! auto_route_validate_workflow '../refine'; then test_pass; else test_fail 'route validation'; fi

test_case 'critical hooks block on host failure without applying the policy to unsupported events'
if python3 - "$PROJECT_ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
hooks = json.loads((root/'hooks/hooks.json').read_text())['hooks']
expected = {'provider-routing-validator.sh', 'codex-exec-guard.sh', 'scheduler-security-gate.sh', 'careful-check.sh', 'freeze-check.sh'}
seen = set()
for event, groups in hooks.items():
    for group in groups:
        for hook in group['hooks']:
            name = hook.get('command', '').rsplit('/', 1)[-1].strip('"')
            if event == 'PreToolUse' and name in expected:
                assert hook['onFailure'] == 'block', name
                assert not hook.get('async')
                seen.add(name)
            elif 'onFailure' in hook:
                raise AssertionError((event, name))
assert seen == expected, (seen, expected)
assert 'CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1' in (root/'scripts/refinement-judge.sh').read_text()
PY
then test_pass; else test_fail 'hook or judge failure policy'; fi

test_summary
