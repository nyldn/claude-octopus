#!/usr/bin/env bash
# Regression coverage for issue #898: Octopus stays dormant until explicitly used.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Explicit-only Octopus activation"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

frontmatter_value() {
    local file="$1" key="$2"
    awk -v key="$key" '
        BEGIN { in_frontmatter = 0 }
        /^---$/ { if (in_frontmatter) exit; in_frontmatter = 1; next }
        in_frontmatter && index($0, key ":") == 1 {
            sub("^" key ":[[:space:]]*", "")
            print
            exit
        }
    ' "$file"
}

test_case "every shipped command is manual-only"
bad=""
for file in "$PROJECT_ROOT"/commands/*.md; do
    [[ "$(frontmatter_value "$file" disable-model-invocation)" == "true" ]] || bad="$bad ${file##*/}"
done
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "commands missing disable-model-invocation: true:$bad"
fi

test_case "every source and generated skill is manual-only"
bad=""
while IFS= read -r file; do
    [[ "$(frontmatter_value "$file" disable-model-invocation)" == "true" ]] || bad="$bad ${file#$PROJECT_ROOT/}"
done < <(find "$PROJECT_ROOT/.claude/skills" "$PROJECT_ROOT/skills" -name SKILL.md -type f | sort)
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "skills missing disable-model-invocation: true:$bad"
fi

test_case "ordinary prompts are silent when router mode is unset"
home_dir="$TEST_TMP_DIR/default-router-home"
mkdir -p "$home_dir/.claude-octopus"
output="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"plain","prompt":"research options for OAuth"}' \
    | env -u OCTOPUS_AUTO_ROUTER_MODE -u OCTOPUS_AUTO_INVOKE \
        HOME="$home_dir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
        "$PROJECT_ROOT/hooks/user-prompt-submit.sh")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "default router injected context: $output"
fi

test_case "explicit commands still receive alias handling when router is off"
output="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"explicit","prompt":"/octo:configure providers"}' \
    | HOME="$home_dir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" OCTOPUS_AUTO_ROUTER_MODE=off \
        "$PROJECT_ROOT/hooks/user-prompt-submit.sh")"
if [[ "$output" == *"Alias resolved: /octo:configure -> /octo:setup"* ]]; then
    test_pass
else
    test_fail "explicit alias handling was lost: ${output:-<empty>}"
fi

test_case "router remains available as an explicit opt-in"
output="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"opt-in","prompt":"research options for OAuth"}' \
    | HOME="$home_dir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" OCTOPUS_AUTO_ROUTER_MODE=invoke \
        "$PROJECT_ROOT/hooks/user-prompt-submit.sh")"
if [[ "$output" == *"Opt-in auto-route: discover"* ]] \
   && [[ "$output" == *"commands/discover.md"* ]]; then
    test_pass
else
    test_fail "opt-in router did not route: ${output:-<empty>}"
fi

test_case "explicit router constrains command paths to a closed allowlist"
if python3 - "$PROJECT_ROOT/commands/auto.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
route_section = text.split("### STEP 3:", 1)[1].split("### STEP 4:", 1)[0]
emitted = set(re.findall(r"\| `octo:([^`]+)` \|", route_section))
allow_section = text.split("closed allowlist:", 1)[1].split("The token is control data", 1)[0]
allowed = set(re.findall(r"`([^`]+)`", allow_section))
raise SystemExit(0 if emitted and emitted == allowed else 1)
PY
then
    if grep -q 'Reject `\.\.`, `/`, `\\\\`, or non-allowlisted values' "$PROJECT_ROOT/commands/auto.md" \
        && grep -q 'commands/<validated-token>\.md' "$PROJECT_ROOT/commands/auto.md"; then
        test_pass
    else
        test_fail "smart router does not reject unsafe command paths"
    fi
else
    test_fail "smart router allowlist differs from the routes it can emit"
fi

test_case "manual composition contract separates model and hook roots"
if grep -q 'Manual composition contract' "$PROJECT_ROOT/docs/PLUGIN-ASSEMBLY-STANDARD.md" \
    && grep -q 'second plugin trust boundary' "$PROJECT_ROOT/docs/PLUGIN-ASSEMBLY-STANDARD.md" \
    && grep -q '`CLAUDE_PLUGIN_ROOT` for hooks and runtime scripts' "$PROJECT_ROOT/docs/PLUGIN-ASSEMBLY-STANDARD.md" \
    && ! rg '^[^#]*Skill\(' "$PROJECT_ROOT/commands"/*.md \
        | grep -vE '❌|Wrong|wrong|PROHIBITED|DO NOT|not resolvable|loops|INSTEAD' >/dev/null; then
    test_pass
else
    test_fail "manual composition contract is missing or a positive Skill() caller remains"
fi

test_case "SessionStart router reinforcement is silent by default"
output="$(printf '%s' '{"hook_event_name":"SessionStart","session_id":"plain"}' \
    | env -u OCTOPUS_AUTO_ROUTER_MODE -u OCTOPUS_AUTO_INVOKE \
        HOME="$home_dir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
        "$PROJECT_ROOT/hooks/auto-router-inject.sh")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "default SessionStart injected router context: $output"
fi

test_case "compound-task coaching is opt-in outside a workflow"
compound='{"hook_event_name":"UserPromptSubmit","session_id":"plain","prompt":"fix the parser and then update the tests"}'
output="$(printf '%s' "$compound" | HOME="$home_dir" "$PROJECT_ROOT/hooks/done-criteria.sh")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "default done-criteria hook engaged: $output"
fi

test_case "compound-task coaching remains available by explicit opt-in"
output="$(printf '%s' "$compound" | HOME="$home_dir" OCTO_DONE_CRITERIA=on "$PROJECT_ROOT/hooks/done-criteria.sh")"
if [[ "$output" == *"Compound task detected"* ]]; then
    test_pass
else
    test_fail "opt-in done criteria did not engage: ${output:-<empty>}"
fi

test_case "global context reinforcement is silent without an active matching workflow"
output="$(printf '%s' '{"hook_event_name":"SessionStart","session_id":"plain"}' \
    | HOME="$home_dir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$PROJECT_ROOT/hooks/context-reinforcement.sh")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "inactive session received workflow enforcement: $output"
fi

test_case "first-run message offers setup but never auto-invokes it"
first_home="$TEST_TMP_DIR/first-run-home"
mkdir -p "$first_home"
output="$(printf '%s' '{"hook_event_name":"SessionStart","session_id":"first"}' \
    | HOME="$first_home" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$PROJECT_ROOT/hooks/session-start-memory.sh")"
if [[ "$output" == *"/octo:setup"* ]] \
   && [[ "$output" != *"Invoke the octo:setup skill now"* ]] \
   && [[ "$output" != *"auto-runs"* ]]; then
    test_pass
else
    test_fail "first-run setup was not a manual offer: ${output:-<empty>}"
fi

test_case "provider validator is host-filtered to orchestrate.sh commands"
if python3 - "$PROJECT_ROOT/hooks/hooks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
matches = [h for group in d for h in group.get("hooks", [])
           if h.get("command", "").endswith("provider-routing-validator.sh")]
raise SystemExit(0 if len(matches) == 1 and "orchestrate.sh" in matches[0].get("if", "") else 1)
PY
then
    test_pass
else
    test_fail "provider validator still spawns for every Bash call"
fi

test_case "provider validator itself fast-exits on unrelated commands"
output="$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"pwd"}}' \
    | "$PROJECT_ROOT/hooks/provider-routing-validator.sh" 2>&1)"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "unrelated Bash command triggered provider validation: $output"
fi

test_case "quality gate is host-filtered and stale-client safe"
if jq -e '
    .hooks.PostToolUse[].hooks[]
    | select(.command == "${CLAUDE_PLUGIN_ROOT}/hooks/quality-gate.sh")
    | .if == "Bash(*orchestrate.sh*)"
' "$PROJECT_ROOT/hooks/hooks.json" >/dev/null 2>&1 \
    && [[ -z "$(printf '%s\n' '{"tool_name":"Bash","tool_input":{"command":"pwd"}}' \
        | HOME="$home_dir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/quality-gate.sh" 2>/dev/null)" ]]; then
    test_pass
else
    test_fail "quality gate can still run for unrelated Bash calls"
fi

test_case "direct-provider guard is host-filtered to provider commands"
if python3 - "$PROJECT_ROOT/hooks/hooks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
filters = sorted(h.get("if", "") for group in d for h in group.get("hooks", [])
                 if h.get("command", "").endswith("codex-exec-guard.sh"))
expected = ["Bash(codex *)", "Bash(gemini *)", "Bash(qwen *)"]
raise SystemExit(0 if filters == expected else 1)
PY
then
    test_pass
else
    test_fail "direct-provider guard still spawns for unrelated Bash commands"
fi

test_case "plugin subagents require an explicit Octopus workflow"
bad=""
for file in "$PROJECT_ROOT"/.claude/agents/*.md; do
    grep -q 'Delegate only when the user explicitly starts an Octopus workflow' "$file" || bad="$bad ${file##*/}"
done
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "subagents still advertise automatic delegation:$bad"
fi

test_case "Copilot agent adapters also require explicit selection"
bad=""
for file in "$PROJECT_ROOT"/.github/agents/*.agent.md; do
    grep -q 'Use only when the user explicitly selects this agent or starts an Octopus workflow' "$file" || bad="$bad ${file##*/}"
done
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "Copilot adapters still advertise automatic delegation:$bad"
fi

test_case "statusline repair does not install a statusline for ordinary users"
status_home="$TEST_TMP_DIR/statusline-default-off"
mkdir -p "$status_home/.claude"
printf '{}\n' > "$status_home/.claude/settings.json"
HOME="$status_home" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$PROJECT_ROOT/hooks/statusline-auto-repair.sh"
if [[ ! -e "$status_home/.claude-octopus/statusline.sh" ]]; then
    test_pass
else
    test_fail "SessionStart installed an unrequested Octopus statusline"
fi

test_case "inactive hook defense paths stay below the latency ceiling"
if python3 - "$PROJECT_ROOT" "$home_dir" <<'PY'
import json, os, subprocess, sys, time
root, home = sys.argv[1:]
env = os.environ.copy()
env.update(HOME=home, CLAUDE_PLUGIN_ROOT=root)
cases = [
    (root + "/hooks/user-prompt-submit.sh", {"session_id":"bench","prompt":"explain this function"}),
    (root + "/hooks/provider-routing-validator.sh", {"tool_name":"Bash","tool_input":{"command":"pwd"}}),
]
start = time.monotonic()
for path, payload in cases:
    data = json.dumps(payload).encode()
    for _ in range(25):
        result = subprocess.run([path], input=data, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=env, timeout=1)
        if result.returncode or result.stdout or result.stderr:
            raise SystemExit(1)
raise SystemExit(0 if time.monotonic() - start < 5 else 1)
PY
then
    test_pass
else
    test_fail "50 inactive hook calls exceeded five seconds or emitted output"
fi

test_summary
