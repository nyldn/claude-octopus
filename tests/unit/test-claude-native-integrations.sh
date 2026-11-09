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
mkdir -p "$TEST_TMP_DIR/bin"
cat > "$TEST_TMP_DIR/bin/claude" <<'FIXTURE'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == --version ]]; then
        [[ -z "${OCTO_TEST_VERSION_LOG:-}" ]] || printf '%s\n' "$@" >> "$OCTO_TEST_VERSION_LOG"
        printf '%s\n' "${OCTO_TEST_CLAUDE_VERSION-2.1.319}"
        exit "${OCTO_TEST_VERSION_STATUS:-0}"
    fi
done
printf '%s\n' "$@" > "$OCTO_TEST_ARGV"
FIXTURE
chmod +x "$TEST_TMP_DIR/bin/claude"
export PATH="$TEST_TMP_DIR/bin:$PATH" OCTO_TEST_VERSION_LOG="$TEST_TMP_DIR/version-argv"

test_case 'default worker launch preserves its existing advisor configuration'
cmd="$(get_agent_command claude-sonnet develop implementer 128)"
if [[ "$cmd" != *--advisor* && ! -e "$OCTO_TEST_VERSION_LOG" ]] && validate_agent_command "$cmd"; then test_pass; else test_fail "$cmd"; fi

test_case 'explicit advisor reaches validated real argv without changing the worker model'
export OCTOPUS_CLAUDE_ADVISOR=opus
cmd="$(get_agent_command claude-sonnet develop implementer 128)"
if [[ "$cmd" == *'--model claude-sonnet-5-5 '* && "$cmd" == *'--advisor opus' ]] && validate_agent_command "$cmd"; then
    octo_dispatch_command_to_argv "$cmd"
    OCTO_TEST_ARGV="$TEST_TMP_DIR/argv" PATH="$TEST_TMP_DIR/bin:$PATH" "${OCTO_COMMAND_ARGV[@]}"
    if [[ "$(grep -cx -- --advisor "$TEST_TMP_DIR/argv")" == 1 ]] && grep -qx opus "$TEST_TMP_DIR/argv"; then test_pass; else test_fail 'lost advisor argv'; fi
else test_fail "$cmd"; fi

for version in 2.1.259 '' invalid; do
    test_case "explicit advisor fails on unsupported worker version '$version' despite a modern host"
    if OCTO_TEST_CLAUDE_VERSION="$version" get_agent_command claude-sonnet develop implementer 128 >/dev/null 2>&1; then test_fail 'accepted unproven worker'; else test_pass; fi
done

test_case 'documented headless floor is accepted even though help hides the flag'
if [[ "$(OCTO_TEST_CLAUDE_VERSION=2.1.260 octo_claude_advisor_fragment claude-sonnet)" == '--advisor opus' ]]; then test_pass; else test_fail 'floor rejected'; fi

test_case 'Codex host launches a supported Claude worker with an advisor'
worker_cmd="$(OCTOPUS_HOST=codex CLAUDE_CODE_VERSION= get_agent_command claude-sonnet probe reviewer 128)" || worker_cmd=''
if [[ "$worker_cmd" == *'--advisor opus'* && "$worker_cmd" == *'--setting-sources project,local'* ]] && validate_agent_command "$worker_cmd"; then test_pass; else test_fail "$worker_cmd"; fi

test_case 'an older host does not reject a supported worker'
if [[ "$(CLAUDE_CODE_VERSION=2.1.1 octo_claude_advisor_fragment claude-sonnet)" == '--advisor opus' ]]; then test_pass; else test_fail 'host version overrode worker'; fi

test_case 'a missing worker is not authorized by the host version'
if OCTOPUS_CLAUDE_BIN="$TEST_TMP_DIR/missing-worker" octo_claude_advisor_fragment claude-sonnet >/dev/null 2>&1; then test_fail 'missing worker accepted'; else test_pass; fi

test_case 'failed worker version probes fail closed even if they print a supported version'
if OCTO_TEST_VERSION_STATUS=1 octo_claude_advisor_fragment claude-sonnet >/dev/null 2>&1; then test_fail 'failed probe accepted'; else test_pass; fi

test_case 'configured worker paths with spaces and fixed arguments are probed as argv'
mkdir -p "$TEST_TMP_DIR/worker binary"
cp "$TEST_TMP_DIR/bin/claude" "$TEST_TMP_DIR/worker binary/claude"
: > "$OCTO_TEST_VERSION_LOG"
if [[ "$(CLAUDE_CODE_VERSION= OCTOPUS_CLAUDE_BIN="\"$TEST_TMP_DIR/worker binary/claude\" --setting-sources project,local" octo_claude_advisor_fragment claude-sonnet)" == '--advisor opus' ]] && grep -qx project,local "$OCTO_TEST_VERSION_LOG"; then test_pass; else test_fail 'configured worker probe failed'; fi

test_case 'a hanging worker version probe returns unknown within its deadline'
cat > "$TEST_TMP_DIR/bin/hanging-worker" <<'FIXTURE'
#!/usr/bin/env bash
sleep 30
FIXTURE
chmod +x "$TEST_TMP_DIR/bin/hanging-worker"
probe_start=$SECONDS
probe_version="$(OCTOPUS_CLAUDE_BIN="$TEST_TMP_DIR/bin/hanging-worker" octo_claude_installed_version)"
if [[ "$probe_version" == unknown && $((SECONDS - probe_start)) -le 8 ]]; then test_pass; else test_fail 'worker version probe exceeded its deadline'; fi

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

for seat in claude-sonnet claude-sonnet:claude-sonnet-5-5; do
    test_case "Codex host disables saved advisors for fixed seat $seat without an opt-in"
    fixed_judge=false
    [[ "$seat" != claude-sonnet ]] || fixed_judge=true
    fixed_cmd="$(OCTOPUS_HOST=codex CLAUDE_CODE_VERSION= OCTOPUS_CLAUDE_ADVISOR= OCTOPUS_REFINEMENT_JUDGE="$fixed_judge" get_agent_command "$seat" probe reviewer 128)"
    if [[ "$fixed_cmd" == *'--advisor off' ]] && validate_agent_command "$fixed_cmd"; then test_pass; else test_fail "$fixed_cmd"; fi
done

for advisor in off sonnet fable claude-opus-5-5; do
    test_case "accepted advisor value $advisor"
    if [[ "$(OCTOPUS_CLAUDE_ADVISOR="$advisor" octo_claude_advisor_fragment claude)" == "--advisor $advisor" ]]; then test_pass; else test_fail "$advisor"; fi
done

for prompt in 'refine this plan' 'iteratively improve this specification' 'improve this plan using a rubric' 'improve this deck to 95/100' 'Improve this plan to a score of 95/100' 'Can you improve this deck to a score of 90 / 100?' 'please improve this plan with a rubric' 'iterate on this plan with a target score of 95' 'Can you refine this plan against a rubric?' 'Can you please improve this plan using a rubric?' 'Could you iteratively improve this plan?' 'Please can you refine this plan?'; do
    test_case "explicit refinement handoff: $prompt"
    if [[ "$(classify_task "$prompt")" == native-refine ]]; then test_pass; else test_fail "$(classify_task "$prompt")"; fi
done
for prompt in 'improve this plan' 'improve this plan without rubric scoring' 'define the refine variable' 'improve this plan with a security audit' 'refine this plan with all providers' 'refine this plan in parallel' 'Can you improve this plan?' 'Can you explain the refine variable and target score?' 'Can you explain a score of 95/100?'; do
    test_case "ordinary edits and higher-priority intents keep their route: $prompt"
    if [[ "$(classify_task "$prompt")" != native-refine ]]; then test_pass; else test_fail 'unwanted judging workflow'; fi
done

for prompt in 'Could you refine this flowchart against a rubric?' 'refine this architecture diagram' 'improve this flowchart using a rubric' 'refine this plan using a rubric without changing the rubric'; do
    test_case "refinement of existing artifacts: $prompt"
    if [[ "$(classify_task "$prompt")" == native-refine ]]; then test_pass; else test_fail "$(classify_task "$prompt")"; fi
done
for prompt in 'Can you improve this plan without using a rubric?' 'Please refine this plan without a rubric.' 'Improve this plan without applying a rubric.' 'Refine this plan, but do not use a rubric.' 'Refine this plan without scoring it.' 'Improve this plan to a score of 95/100 without using a rubric.'; do
    test_case "refinement scoring opt-out: $prompt"
    if [[ "$(classify_task "$prompt")" != native-refine ]]; then test_pass; else test_fail 'ignored scoring opt-out'; fi
done
for prompt in 'Create a flowchart for this process' 'Generate an image of an octopus'; do
    test_case "image creation keeps its route: $prompt"
    if [[ "$(classify_task "$prompt")" == image ]]; then test_pass; else test_fail "$(classify_task "$prompt")"; fi
done
for route in native-multi native-security parallel; do
    case "$route" in
        native-multi) prompt='refine this flowchart with all providers' ;;
        native-security) prompt='refine this flowchart with a security audit' ;;
        parallel) prompt='refine this flowchart in parallel' ;;
    esac
    test_case "visual refinement preserves explicit $route priority"
    if [[ "$(classify_task "$prompt")" == "$route" ]]; then test_pass; else test_fail "$(classify_task "$prompt")"; fi
done

test_case 'incidental iterate and score terms preserve debugging intent'
if [[ "$(classify_task 'Fix the bug in the iterate loop when the target score is 5')" == native-debug ]]; then test_pass; else test_fail 'debug request entered refinement'; fi

for benchmark in Lighthouse 'PageSpeed Insights'; do
    test_case "measured $benchmark targets preserve performance optimization"
    route="$(classify_task "Improve this site; optimize performance to a score of 95/100 on $benchmark")"
    if [[ "$route" == optimize-performance ]]; then test_pass; else test_fail "$route"; fi
done
test_case 'a rubric request can still refine a Lighthouse rollout plan'
if [[ "$(classify_task 'Improve this Lighthouse rollout plan using a rubric')" == native-refine ]]; then test_pass; else test_fail 'rubric intent lost'; fi

for scenario in default-design coding-rule design-rule native-rule rule-order keyword-order explicit-role; do
    test_case "direct refinement spawn preserves roles and rule order: $scenario"
    if (
        source "$PROJECT_ROOT/scripts/lib/spawn.sh"
        DRY_RUN=true SUPPORTS_FORK_CONTEXT=false SUPPORTS_WORKTREE_HOOKS=false
        WORKSPACE_DIR="$TEST_TMP_DIR/spawn-$scenario"
        mkdir -p "$WORKSPACE_DIR/.octo"
        prompt='refine this layout'
        explicit_role=''
        case "$scenario" in
            default-design) rules='[]'; expected=frontend-architect ;;
            coding-rule) prompt='refine this function'; rules='[{"match":{"task_type":"coding"},"prefer":"reviewer"}]'; expected=reviewer ;;
            design-rule) rules='[{"match":{"task_type":"design"},"prefer":"researcher"}]'; expected=researcher ;;
            native-rule) rules='[{"match":{"task_type":"native-refine"},"prefer":"reviewer"}]'; expected=reviewer ;;
            rule-order) rules='[{"match":{"task_type":"design"},"prefer":"reviewer"},{"match":{"task_type":"native-refine"},"prefer":"implementer"}]'; expected=reviewer ;;
            keyword-order) rules='[{"match":{"keywords":"layout"},"prefer":"reviewer"},{"match":{"task_type":"design"},"prefer":"implementer"}]'; expected=reviewer ;;
            explicit-role) rules='[]'; explicit_role=reviewer; expected=reviewer ;;
        esac
        printf '{"rules":%s}\n' "$rules" > "$WORKSPACE_DIR/.octo/routing-rules.json"
        log() { printf '%s\n' "$*"; }
        get_agent_command() { printf '%s\n' fixture-command; }
        output="$(spawn_agent codex "$prompt" fixture "$explicit_role")"
        [[ "$output" == *"[DRY-RUN] Would execute: fixture-command with role=$expected"* ]]
    ); then test_pass; else test_fail "$scenario"; fi
done

test_case 'missing-input grader rejects asserted scores while allowing target discussion'
if python3 - "$PROJECT_ROOT/evals/refine-missing-input/graders/no-fabricated-score.md" <<'PY'
import pathlib, re, sys
pattern = re.compile(pathlib.Path(sys.argv[1]).read_text().split('---', 2)[2].strip(), re.I)
for response in ('Please provide the plan. The score is 95/100.',
                 'Its score is 95/100.', 'Your score: 95/100.',
                 'Score is 95/100.', 'The current score is 95/100.',
                 'Final score: 95/100.', 'I scored 95/100.'):
    assert pattern.search(response), response
for response in ('Please provide the plan so we can work toward 95/100.',
                 'Your target score is 95/100.', 'The requested score is 95/100.',
                 'I cannot score an absent plan.', 'Your desired score: 95/100.'):
    assert not pattern.search(response), response
PY
then test_pass; else test_fail 'fabricated-score grader'; fi

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
