#!/usr/bin/env bash
# Regression coverage for persona names accepted by `orchestrate.sh spawn`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_LIB="$PROJECT_ROOT/scripts/lib/agents.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
# shellcheck source=/dev/null
source "$AGENTS_LIB"

test_suite "persona spawn routing"

run_orchestrate() {
    (cd "$PROJECT_ROOT" && bash scripts/orchestrate.sh --dry-run "$@" 2>&1)
}

test_case "spawn resolves backend-architect to its configured provider and preserves the persona role"
agy_bin="$TEST_TMP_DIR/persona-primary-bin"
mkdir -p "$agy_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$agy_bin/agy"
chmod +x "$agy_bin/agy"
out="$(PATH="$agy_bin:$PATH" run_orchestrate spawn backend-architect "Design a durable coordinator")" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && \
   [[ "$out" == *"[DRY-RUN] Would execute:"* ]] && \
   [[ "$out" == *"agy-exec.sh"* ]] && \
   [[ "$out" == *"role=backend-architect"* ]] && \
   [[ "$out" != *"Unknown agent type: backend-architect"* ]]; then
    test_pass
else
    test_fail "expected persona dispatch dry-run; got exit=$rc, output: $out"
fi

test_case "persona resolver keeps an available configured primary provider"
get_agent_config() {
    case "$2" in
        cli) printf '%s\n' 'agy # configured primary' ;;
        fallback_cli) printf '%s\n' 'codex' ;;
    esac
}
is_agent_available_v2() { [[ "$1" == "agy" ]]; }
out="$(resolve_persona_spawn_target backend-architect)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == "agy" ]]; then
    test_pass
else
    test_fail "expected available primary agy; got exit=$rc, output: $out"
fi

test_case "persona resolver uses configured fallback only when primary is unavailable"
is_agent_available_v2() { [[ "$1" == "codex" ]]; }
out="$(resolve_persona_spawn_target backend-architect)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == "codex" ]]; then
    test_pass
else
    test_fail "expected fallback codex; got exit=$rc, output: $out"
fi

test_case "persona resolver preserves the primary when no configured provider is available"
is_agent_available_v2() { return 1; }
out="$(resolve_persona_spawn_target backend-architect)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == "agy" ]]; then
    test_pass
else
    test_fail "expected unavailable primary agy for concrete dispatch diagnostics; got exit=$rc, output: $out"
fi

test_case "persona resolver never reinterprets a direct provider listed in AVAILABLE_AGENTS"
AVAILABLE_AGENTS="codex agy"
config_marker="$TEST_TMP_DIR/direct-provider-config-called"
rm -f "$config_marker"
get_agent_config() { touch "$config_marker"; printf '%s\n' 'agy'; }
resolve_persona_spawn_target codex >/dev/null 2>&1 && rc=0 || rc=$?
unset AVAILABLE_AGENTS
if [[ "$rc" -ne 0 && ! -e "$config_marker" ]]; then
    test_pass
else
    test_fail "direct provider was reinterpreted through persona config"
fi

test_case "persona resolver rejects unsafe target names before config lookup"
config_marker="$TEST_TMP_DIR/persona-config-called"
rm -f "$config_marker"
get_agent_config() { touch "$config_marker"; printf '%s\n' 'agy'; }
resolve_persona_spawn_target 'backend.*' >/dev/null 2>&1 && rc=0 || rc=$?
if [[ "$rc" -ne 0 && ! -e "$config_marker" ]]; then
    test_pass
else
    test_fail "unsafe target reached config lookup or resolved successfully"
fi

test_case "direct provider spawn remains provider-oriented"
out="$(run_orchestrate spawn codex "Review a durable coordinator")" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && \
   [[ "$out" == *"[DRY-RUN] Would execute: codex"* ]] && \
   [[ "$out" != *"role=backend-architect"* ]]; then
    test_pass
else
    test_fail "expected unchanged direct provider dry-run; got exit=$rc, output: $out"
fi

test_case "unknown persona target still fails closed"
out="$(run_orchestrate spawn not-a-persona "Review a durable coordinator")" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"Unknown agent type: not-a-persona"* ]]; then
    test_pass
else
    test_fail "expected unknown target rejection; got exit=$rc, output: $out"
fi

test_case "direct agy dry-run preserves the legacy none role without live dispatch"
out="$(PATH="$agy_bin:$PATH" run_orchestrate spawn agy "Review a durable coordinator")" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && \
   [[ "$out" == *"[DRY-RUN] Would execute:"* ]] && \
   [[ "$out" == *"agy-exec.sh"* ]] && \
   [[ "$out" == *"role=none"* ]] && \
   [[ "$out" != *"Running agy synchronously"* ]]; then
    test_pass
else
    test_fail "expected safe legacy-role AGY dry-run; got exit=$rc, output: $out"
fi

test_summary
