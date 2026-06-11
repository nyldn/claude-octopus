#!/bin/bash
set -euo pipefail

# tests/unit/test-orchestrate-cwd-routing.sh
# Behavioral coverage for the orchestrate.sh dispatch fixes (bug report 260609):
#   1. Bare provider names in routing.roles/.phases must never be returned as a
#      MODEL name for another provider (codex was dispatched --model perplexity).
#   2. Spawned claude --print subprocesses must pre-approve read tools so Read
#      is not denied in headless permission mode.
#   3. PROJECT_ROOT falls back to CLAUDE_PROJECT_DIR (or warns) when callers
#      invoke orchestrate.sh from inside the plugin install.
#   4. Command docs no longer instruct `cd` into the plugin before dispatch.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Orchestrate cwd + model routing (bug 260609)"

# dispatch.sh / model-resolver.sh call log() outside orchestrate.sh; stub it.
log() { :; }
export _BARE_OPT=""
export OCTOPUS_PLATFORM="${OCTOPUS_PLATFORM:-Linux}"
export PLUGIN_DIR="${PLUGIN_DIR:-$PROJECT_ROOT}"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/dispatch.sh" 2>/dev/null || true

if ! declare -f resolve_octopus_model >/dev/null 2>&1; then
    test_case "resolve_octopus_model() is defined"
    test_fail "resolve_octopus_model not sourced from model-resolver.sh"
    test_summary
    exit 1
fi
if ! declare -f get_agent_command >/dev/null 2>&1; then
    test_case "get_agent_command() is defined"
    test_fail "get_agent_command not sourced from dispatch.sh"
    test_summary
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Fixture: temp HOME with a providers.json whose role routing uses a bare
# provider name — the exact config shape that produced `--model perplexity`.
# ═══════════════════════════════════════════════════════════════════════════════

# Use the framework's shared temp dir (created by test_suite, cleaned by its
# EXIT trap) instead of a private mktemp + trap.
FIXTURE_HOME="$TEST_TMP_DIR/fixture-home"
mkdir -p "$FIXTURE_HOME/.claude-octopus/config"
cat > "$FIXTURE_HOME/.claude-octopus/config/providers.json" << 'EOF'
{
  "version": "3.0",
  "providers": {},
  "routing": {
    "phases": {},
    "roles": {
      "researcher": "perplexity"
    }
  }
}
EOF

# resolve_octopus_model reads ${HOME}/.claude-octopus/config/providers.json and
# memoizes per cache_key; use a unique CLAUDE_CODE_SESSION per call so the
# /tmp persistent cache never bleeds between assertions.
resolve_with_fixture() {
    local provider="$1" agent_type="$2" phase="$3" role="$4"
    HOME="$FIXTURE_HOME" CLAUDE_CODE_SESSION="cwdtest-$$-$RANDOM" \
        bash -c '
            log() { :; }
            export PLUGIN_DIR="'"$PROJECT_ROOT"'"
            source "'"$PROJECT_ROOT"'/scripts/lib/model-resolver.sh" 2>/dev/null
            resolve_octopus_model "$@"
        ' _ "$provider" "$agent_type" "$phase" "$role"
}

test_role_route_not_leaked_to_codex() {
    test_case "routing.roles researcher=perplexity is not returned as a codex model"
    local got
    got="$(resolve_with_fixture codex codex probe researcher)"
    if [[ "$got" != "perplexity" ]]; then
        test_pass
    else
        test_fail "codex resolved model 'perplexity' — would dispatch 'codex exec --model perplexity'"
    fi
}

test_role_route_not_leaked_to_gemini() {
    test_case "routing.roles researcher=perplexity is not returned as a gemini model"
    local got
    got="$(resolve_with_fixture gemini gemini probe researcher)"
    if [[ "$got" != "perplexity" ]]; then
        test_pass
    else
        test_fail "gemini resolved model 'perplexity' — would 404 and burn a fallback retry"
    fi
}

test_role_route_not_a_model_for_perplexity_itself() {
    test_case "perplexity provider falls through to a real model, not the literal 'perplexity'"
    local got
    got="$(resolve_with_fixture perplexity perplexity probe researcher)"
    if [[ -n "$got" && "$got" != "perplexity" ]]; then
        test_pass
    else
        test_fail "expected a concrete model (e.g. sonar), got: '$got'"
    fi
}

test_colon_route_still_resolves() {
    test_case "provider:type routing (codex:mini) still resolves for the matching provider"
    mkdir -p "$FIXTURE_HOME/.claude-octopus/config"
    cat > "$FIXTURE_HOME/.claude-octopus/config/providers.json" << 'EOF'
{
  "version": "3.0",
  "providers": {"codex": {"mini": "gpt-5.4-mini"}},
  "routing": {"phases": {}, "roles": {"researcher": "codex:codex-mini"}}
}
EOF
    local got
    got="$(resolve_with_fixture codex codex probe researcher)"
    if [[ "$got" == "gpt-5.4-mini" ]]; then
        test_pass
    else
        test_fail "colon-form route should resolve to gpt-5.4-mini, got: '$got'"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Claude subprocess permission flags (Read blocked in headless --print mode)
# ═══════════════════════════════════════════════════════════════════════════════

test_claude_grants_read_tools() {
    test_case "get_agent_command claude → pre-approves Read,Glob,Grep"
    local got; got="$(get_agent_command claude probe researcher)"
    [[ "$got" == *"--allowed-tools Read,Glob,Grep"* ]] && test_pass || test_fail "missing --allowed-tools, got: $got"
}

test_claude_sonnet_grants_read_tools() {
    test_case "get_agent_command claude-sonnet → pre-approves Read,Glob,Grep"
    local got; got="$(get_agent_command claude-sonnet probe researcher)"
    [[ "$got" == *"--allowed-tools Read,Glob,Grep"* ]] && test_pass || test_fail "missing --allowed-tools, got: $got"
}

test_claude_implementer_accepts_edits() {
    test_case "get_agent_command claude (implementer) → acceptEdits + write tools"
    local got; got="$(get_agent_command claude tangle implementer)"
    if [[ "$got" == *"--permission-mode acceptEdits"* && "$got" == *"Edit,Write"* ]]; then
        test_pass
    else
        test_fail "implementer role missing write grants, got: $got"
    fi
}


test_claude_developer_accepts_edits() {
    test_case "get_agent_command claude (developer) → acceptEdits + write tools"
    local got; got="$(get_agent_command claude develop developer)"
    if [[ "$got" == *"--permission-mode acceptEdits"* && "$got" == *"--allowed-tools Read,Glob,Grep,Edit,Write"* ]]; then
        test_pass
    else
        test_fail "developer role missing write grants, got: $got"
    fi
}

test_claude_researcher_no_write_grant() {
    test_case "get_agent_command claude (researcher) → no acceptEdits/write grant"
    local got; got="$(get_agent_command claude probe researcher)"
    if [[ "$got" != *"acceptEdits"* && "$got" != *"Edit,Write"* ]]; then
        test_pass
    else
        test_fail "researcher role unexpectedly write-capable: $got"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Gemini external directory whitelisting
# ═══════════════════════════════════════════════════════════════════════════════

test_gemini_include_dirs_flag() {
    test_case "OCTOPUS_GEMINI_INCLUDE_DIRS adds --include-directories to gemini dispatch"
    # gemini branch calls get_agent_model → stub to avoid full resolver deps
    local got
    got="$(
        get_agent_model() { echo "gemini-3-flash-preview"; }
        OCTOPUS_GEMINI_INCLUDE_DIRS="/tmp/staging" get_agent_command gemini probe researcher
    )"
    [[ "$got" == *"--include-directories /tmp/staging"* ]] && test_pass || test_fail "flag missing, got: $got"
}

test_gemini_no_include_dirs_by_default() {
    test_case "gemini dispatch has no --include-directories when env unset"
    local got
    got="$(
        get_agent_model() { echo "gemini-3-flash-preview"; }
        unset OCTOPUS_GEMINI_INCLUDE_DIRS
        get_agent_command gemini probe researcher
    )"
    [[ "$got" != *"--include-directories"* ]] && test_pass || test_fail "unexpected flag: $got"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT_ROOT resolution when invoked from inside the plugin install
# ═══════════════════════════════════════════════════════════════════════════════

test_warns_when_cwd_is_plugin() {
    test_case "orchestrate.sh warns when invoked from the plugin dir without CLAUDE_PROJECT_DIR"
    local stderr_out
    stderr_out="$(cd "$PROJECT_ROOT" && env -u CLAUDE_PROJECT_DIR -u OCTOPUS_PROJECT_DIR \
        bash scripts/orchestrate.sh version 2>&1 >/dev/null || true)"
    if [[ "$stderr_out" == *"invoked from inside the plugin install"* ]]; then
        test_pass
    else
        test_fail "expected plugin-cwd warning on stderr"
    fi
}

test_no_warn_with_claude_project_dir() {
    test_case "orchestrate.sh silently redirects PROJECT_ROOT when CLAUDE_PROJECT_DIR is set"
    local stderr_out
    stderr_out="$(cd "$PROJECT_ROOT" && env -u OCTOPUS_PROJECT_DIR CLAUDE_PROJECT_DIR="$FIXTURE_HOME" \
        bash scripts/orchestrate.sh version 2>&1 >/dev/null || true)"
    if [[ "$stderr_out" != *"invoked from inside the plugin install"* ]]; then
        test_pass
    else
        test_fail "warning fired despite CLAUDE_PROJECT_DIR fallback"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Docs regression: no `cd` into the plugin before orchestrate.sh
# ═══════════════════════════════════════════════════════════════════════════════

test_docs_do_not_cd_into_plugin() {
    test_case "no tracked doc instructs 'cd .claude-octopus/plugin && bash scripts/'"
    local hits
    hits="$(cd "$PROJECT_ROOT" && git grep -l 'cd "\${HOME}/.claude-octopus/plugin" && bash scripts/' -- '*.md' 2>/dev/null || true)"
    if [[ -z "$hits" ]]; then
        test_pass
    else
        test_fail "cd-into-plugin pattern reintroduced in: $hits"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

test_role_route_not_leaked_to_codex
test_role_route_not_leaked_to_gemini
test_role_route_not_a_model_for_perplexity_itself
test_colon_route_still_resolves

test_claude_grants_read_tools
test_claude_sonnet_grants_read_tools
test_claude_implementer_accepts_edits
test_claude_developer_accepts_edits
test_claude_researcher_no_write_grant

test_gemini_include_dirs_flag
test_gemini_no_include_dirs_by_default

test_warns_when_cwd_is_plugin
test_no_warn_with_claude_project_dir

test_docs_do_not_cd_into_plugin

test_summary
