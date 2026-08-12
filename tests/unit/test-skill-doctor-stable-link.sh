#!/usr/bin/env bash
# Regression coverage for the skill-doctor stable-link resolver shipped to
# Claude Code and Codex. See #481 and #818.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Skill Doctor Stable-Link Resolver (#818)"

extract_first_bash_block() {
    local skill_file="$1"
    local output_file="$2"

    awk '
        /^```bash$/ && !found { found = 1; capture = 1; next }
        capture && /^```$/ { exit }
        capture { print }
    ' "$skill_file" > "$output_file"
}

assert_resolver_preserves_stable_link() {
    local label="$1"
    local skill_file="$2"
    local host="$3"
    local work="$TEST_TMP_DIR/${label// /-}"
    local fake_home="$work/home"
    local plugin_root="$work/cache/9.61.2"
    local stable_link="$fake_home/.claude-octopus/plugin"
    local resolver="$work/resolver.sh"
    local call_log="$work/doctor-call.log"

    test_case "$label preserves an existing stable symlink without creating a loop"

    mkdir -p "$plugin_root/scripts" "$fake_home/.claude-octopus"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\\n" "$*" > "$DOCTOR_CALL_LOG"' \
        > "$plugin_root/scripts/orchestrate.sh"
    chmod +x "$plugin_root/scripts/orchestrate.sh"
    ln -s "$plugin_root" "$stable_link"

    extract_first_bash_block "$skill_file" "$resolver"
    if ! grep -q 'pwd -P' "$resolver"; then
        test_fail "$label package is missing the physical-path guard"
        return
    fi

    if [[ "$host" == "claude" ]]; then
        env -u OCTO_PLUGIN_ROOT \
            "HOME=$fake_home" \
            "CLAUDE_PLUGIN_ROOT=$stable_link" \
            "DOCTOR_CALL_LOG=$call_log" \
            bash "$resolver"
    else
        # Codex does not provide CLAUDE_PLUGIN_ROOT. Exercise the packaged
        # resolver's stable-link discovery instead of its Claude host shortcut.
        env -u CLAUDE_PLUGIN_ROOT \
            "HOME=$fake_home" \
            "OCTO_PLUGIN_ROOT=$stable_link" \
            "DOCTOR_CALL_LOG=$call_log" \
            bash "$resolver"
    fi

    if [[ ! -L "$stable_link" ]]; then
        test_fail "$label resolver replaced the stable symlink"
    elif [[ "$(readlink "$stable_link")" != "$plugin_root" ]]; then
        test_fail "$label resolver rewrote the stable link to $(readlink "$stable_link")"
    elif [[ "$(cat "$call_log" 2>/dev/null || true)" != "doctor --verbose" ]]; then
        test_fail "$label resolver did not invoke doctor through the stable link"
    elif ! test -x "$stable_link/scripts/orchestrate.sh"; then
        test_fail "$label stable link no longer resolves to the plugin"
    else
        test_pass
    fi
}

test_codex_package_is_generated_from_guarded_source() {
    test_case "Codex skill package is synchronized with the guarded Claude source"

    if "$PROJECT_ROOT/scripts/build-codex-skills.sh" --check >/dev/null; then
        test_pass
    else
        test_fail "skills/ is stale; regenerate it before publishing the Codex package"
    fi
}

test_follow_up_commands_use_resolved_root() {
    test_case "Doctor follow-up commands reuse the resolved plugin root"

    local doctor_skill="$PROJECT_ROOT/.claude/skills/skill-doctor/SKILL.md"
    local category missing=""
    for category in providers companions auth config updates state smoke hooks scheduler skills conflicts agents recurrence cache; do
        grep -Fq "bash \"\$OCTO_PLUGIN_ROOT/scripts/orchestrate.sh\" doctor ${category}" "$doctor_skill" ||
            missing+="${category} "
    done
    grep -Fq 'bash "$OCTO_PLUGIN_ROOT/scripts/orchestrate.sh" doctor --verbose' "$doctor_skill" || missing+="verbose "
    grep -Fq 'bash "$OCTO_PLUGIN_ROOT/scripts/orchestrate.sh" doctor --json' "$doctor_skill" || missing+="json "

    if grep -q '${HOME}/.claude-octopus/plugin/scripts/' "$doctor_skill"; then
        test_fail "Doctor bypasses OCTO_PLUGIN_ROOT after resolving the installed plugin"
    elif [[ -n "$missing" ]]; then
        test_fail "Doctor omits resolved-root commands for: $missing"
    else
        test_pass
    fi
}

test_root_fallback_is_pipefail_safe() {
    test_case "Doctor root discovery tolerates an empty plugin search under pipefail"

    local doctor_skill="$PROJECT_ROOT/.claude/skills/skill-doctor/SKILL.md"
    if grep -Fq "{ grep -E '(nyldn-plugins|claude-octopus|/octo(/[0-9]|\$))' || true; }" \
        "$doctor_skill"; then
        test_pass
    else
        test_fail "Doctor root resolver can abort when grep finds no installed plugin"
    fi
}

test_remediation_fences_are_markdown_safe() {
    test_case "Doctor remediation fences have surrounding blank lines"

    if awk '
        closing && $0 != "" { bad = 1 }
        { closing = 0 }
        /^```javascript$/ {
            if (previous != "") bad = 1
            in_javascript = 1
        }
        in_javascript && /^```$/ {
            in_javascript = 0
            closing = 1
        }
        { previous = $0 }
        END { if (closing || in_javascript) bad = 1; exit bad }
    ' "$PROJECT_ROOT/.claude/skills/skill-doctor/SKILL.md"; then
        test_pass
    else
        test_fail "Doctor remediation fences violate MD031"
    fi
}

assert_resolver_preserves_stable_link \
    "Claude skill" \
    "$PROJECT_ROOT/.claude/skills/skill-doctor/SKILL.md" \
    "claude"
assert_resolver_preserves_stable_link \
    "Codex skill" \
    "$PROJECT_ROOT/skills/skill-doctor/SKILL.md" \
    "codex"
test_follow_up_commands_use_resolved_root
test_root_fallback_is_pipefail_safe
test_remediation_fences_are_markdown_safe
test_codex_package_is_generated_from_guarded_source

test_summary
