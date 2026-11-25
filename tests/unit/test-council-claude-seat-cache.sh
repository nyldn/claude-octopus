#!/usr/bin/env bash
# Council Claude seats start with project and local settings only.
#
# A council Claude seat loaded the user's plugins, hooks and MCP servers, which
# made Claude Code's system prompt differ from call to call, so every seat
# re-wrote 10-30k tokens of prompt cache. Measured on claude-haiku-4-5: two
# identical calls with user settings re-wrote 10-12k tokens each; with
# --setting-sources project,local --strict-mcp-config the second call read the
# whole 21k prefix from cache and cost about a tenth as much.
set -euo pipefail

unset _OCTOPUS_COUNCIL_SEAT OCTOPUS_COUNCIL_CLAUDE_USER_SETTINGS OCTOPUS_COUNCIL_SEAT_USAGE _OCTOPUS_SEAT_USAGE_FILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Council Claude seat cache isolation"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/secure.sh"

WORK="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/seat-cache.XXXXXX")"
export CLAUDE_CONFIG_DIR="$WORK/config"
mkdir -p "$CLAUDE_CONFIG_DIR"
printf '{"enabledPlugins":{"x@y":true}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"

args() { OCTOPUS_COUNCIL_CLAUDE_USER_SETTINGS=0 octo_council_claude_isolation_args "$@" | tr '\n' ' '; }

test_case "default keeps user plugins and MCP servers in the seat"
rc_default=0
_OCTOPUS_COUNCIL_SEAT=1 octo_council_claude_isolation_args claude claude --print >/dev/null || rc_default=$?
if [[ "$rc_default" == 1 ]]; then test_pass; else test_fail "rc=$rc_default"; fi

test_case "a council claude seat gets project/local settings and no MCP servers"
got="$(_OCTOPUS_COUNCIL_SEAT=1 args claude claude --print --model m)"
if [[ "$got" == "--setting-sources project,local --strict-mcp-config " ]]; then test_pass; else test_fail "got=[$got]"; fi

test_case "flags already present are not repeated"
got="$(_OCTOPUS_COUNCIL_SEAT=1 args claude claude --setting-sources project,local --print)"
got2="$(_OCTOPUS_COUNCIL_SEAT=1 args claude claude --mcp-config x.json --print)"
if [[ "$got" == "--strict-mcp-config " && "$got2" == "--setting-sources project,local " ]]; then
    test_pass
else
    test_fail "got=[$got] got2=[$got2]"
fi

test_case "non-council dispatches, other providers and the opt-out run unchanged"
rc_none=0; args claude claude --print >/dev/null || rc_none=$?
rc_sdk=0; _OCTOPUS_COUNCIL_SEAT=1 args claude-sdk claude --print >/dev/null || rc_sdk=$?
rc_codex=0; _OCTOPUS_COUNCIL_SEAT=1 args codex codex exec >/dev/null || rc_codex=$?
rc_noprint=0; _OCTOPUS_COUNCIL_SEAT=1 args claude claude --version >/dev/null || rc_noprint=$?
rc_opt=0; _OCTOPUS_COUNCIL_SEAT=1 OCTOPUS_COUNCIL_CLAUDE_USER_SETTINGS=1 octo_council_claude_isolation_args claude claude --print >/dev/null || rc_opt=$?
if [[ "$rc_none$rc_sdk$rc_codex$rc_noprint$rc_opt" == 11111 ]]; then
    test_pass
else
    test_fail "rc none=$rc_none sdk=$rc_sdk codex=$rc_codex noprint=$rc_noprint opt-out=$rc_opt"
fi

test_case "user settings that affect seat behavior are kept"
kept=""
for settings in '{"apiKeyHelper":"/bin/key"}' '{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}' \
                '{"env":{"ANTHROPIC_BASE_URL":"https://proxy"}}' '{"env":{"AWS_PROFILE":"p"}}' \
                '{"env":{"MAX_THINKING_TOKENS":"1000"}}' '{"permissions":{"deny":["Write"]}}' \
                '{"hooks":{"PreToolUse":[]}}' 'not json' '{} {}' ''; do
    printf '%s\n' "$settings" > "$CLAUDE_CONFIG_DIR/settings.json"
    _OCTOPUS_COUNCIL_SEAT=1 args claude claude --print >/dev/null && kept+=n || kept+=y
done
printf '{}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
plain=0; _OCTOPUS_COUNCIL_SEAT=1 args claude claude --print >/dev/null || plain=$?
rm -f "$CLAUDE_CONFIG_DIR/settings.json"
missing=0; _OCTOPUS_COUNCIL_SEAT=1 args claude claude --print >/dev/null || missing=$?
if [[ "$kept" == yyyyyyyyyy && "$plain" == 0 && "$missing" == 0 ]]; then
    test_pass
else
    test_fail "kept=$kept plain=$plain missing=$missing"
fi

test_case "run_agent_sync records and executes the same isolation and usage flags"
argv_file="$WORK/argv"
(
    fake="$WORK/claude"
    cat > "$fake" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "\$@" > "$argv_file"
printf '%s\n' '{"type":"result","result":"answer","total_cost_usd":0.01}'
EOF
    chmod 755 "$fake"
    export RESULTS_DIR="$WORK/results"; mkdir -p "$RESULTS_DIR"
    log() { :; }
    classify_task() { printf 'standard\n'; }
    get_role_for_context() { printf 'reviewer\n'; }
    apply_persona() { printf '%s\n' "$2"; }
    load_earned_skills() { :; }
    build_provider_context() { :; }
    enforce_context_budget() { printf '%s\n' "$1"; }
    get_agent_model() { printf 'fixture-model\n'; }
    estimate_agent_call_cost() { printf '0.000000\n'; }
    check_provider_health() { return 0; }
    record_agent_call() { :; }
    get_agent_command() { printf '%s --print --model m\n' "$fake"; }
    build_provider_env() { PROVIDER_ENV_ARRAY=(); }
    run_with_timeout() { shift; "$@"; }
    stop_quota_watcher() { :; }
    update_agent_status() { :; }
    octo_estimate_tokens_for_file() { printf '0\n'; }
    write_agent_status() { :; }
    _OCTOPUS_COUNCIL_SEAT=1 OCTOPUS_COUNCIL_CLAUDE_USER_SETTINGS=0 \
        OCTOPUS_PERSISTENCE_AVAILABLE=true _OCTOPUS_SEAT_USAGE_FILE="$WORK/usage.jsonl" \
        run_agent_sync claude 'review this change' 30 reviewer council >/dev/null 2>&1
)
expected=$'--print\n--model\nm\n--setting-sources\nproject,local\n--strict-mcp-config\n--output-format\njson'
if [[ "$(cat "$argv_file")" == "$expected" && \
      "$(jq -r '.plan.argv[1:][]' "$WORK/results/dispatch-plans.jsonl")" == "$expected" ]] && \
   jq -e '.cost_usd == 0.01' "$WORK/usage.jsonl" >/dev/null; then
    test_pass
else
    test_fail "argv=$(cat "$argv_file" 2>/dev/null)"
fi

test_summary
