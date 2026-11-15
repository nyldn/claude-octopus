#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Plan artifact storage"

# These fixtures seed Claude sessions, including when another host launches them.
export OCTOPUS_HOST=claude

RESOLVER="$PROJECT_ROOT/scripts/plan-storage.sh"
HOOK="$PROJECT_ROOT/hooks/plan-mode-interceptor.sh"

case_root="$TEST_TMP_DIR/plan-artifact-storage"
mkdir -p "$case_root"
test_home="$case_root/home"
mkdir -p "$test_home"
test_home="$(cd "$test_home" && pwd -P)"
case_root="$(cd "$case_root" && pwd -P)"

test_case "home-directory plans use octo-owned storage, never global Claude config"
home_plan_dir="$(env "HOME=$test_home" "CLAUDE_CODE_SESSION_ID=home-session" \
    "$RESOLVER" create "$test_home")"
if [[ -d "$home_plan_dir" && "$home_plan_dir" == "$test_home/.claude-octopus/"* &&
      "$home_plan_dir" != "$test_home/.claude/"* ]]; then
    test_pass
else
    test_fail "unexpected plan directory: $home_plan_dir"
fi

test_case "sequential plans in one non-project session never overwrite"
home_plan_dir_2="$(env "HOME=$test_home" "CLAUDE_CODE_SESSION_ID=home-session" \
    "$RESOLVER" create "$test_home")"
if [[ -d "$home_plan_dir_2" && "$home_plan_dir_2" != "$home_plan_dir" ]]; then
    test_pass
else
    test_fail "resolver reused a run directory: $home_plan_dir_2"
fi

test_case "current returns the latest directory for the same session and workspace"
current_plan_dir="$(env "HOME=$test_home" "CLAUDE_CODE_SESSION_ID=home-session" \
    "$RESOLVER" current "$test_home")"
if [[ "$current_plan_dir" == "$home_plan_dir_2" ]]; then
    test_pass
else
    test_fail "expected $home_plan_dir_2, got $current_plan_dir"
fi

test_case "git projects store plans under a project-owned namespace"
project="$case_root/project"
mkdir -p "$project/subdir"
git -C "$project" init -q
project_plan_dir="$(env "HOME=$test_home" "CLAUDE_CODE_SESSION_ID=project-session" \
    "$RESOLVER" create "$project/subdir")"
if [[ -d "$project_plan_dir" && "$project_plan_dir" == "$project/.octo/plans/"* ]]; then
    test_pass
else
    test_fail "unexpected project plan directory: $project_plan_dir"
fi

test_case "marker-file projects resolve from nested directories"
marker_project="$case_root/marker-project"
mkdir -p "$marker_project/app/src"
: > "$marker_project/package.json"
marker_plan_dir="$(env "HOME=$test_home" "CLAUDE_CODE_SESSION_ID=marker-session" \
    "$RESOLVER" create "$marker_project/app/src")"
if [[ -d "$marker_plan_dir" && "$marker_plan_dir" == "$marker_project/.octo/plans/"* ]]; then
    test_pass
else
    test_fail "unexpected marker plan directory: $marker_plan_dir"
fi

test_case "home-directory marker files cannot redirect plans into global Claude config"
: > "$test_home/package.json"
guarded_home_dir="$(env "HOME=$test_home" "CLAUDE_CODE_SESSION_ID=guard-session" \
    "$RESOLVER" create "$test_home")"
if [[ "$guarded_home_dir" == "$test_home/.claude-octopus/"* &&
      "$guarded_home_dir" != "$test_home/.claude/"* ]]; then
    test_pass
else
    test_fail "home guard failed: $guarded_home_dir"
fi

test_case "relative configured roots fail closed"
if env "HOME=$test_home" "OCTOPUS_SESSION_PLANS=relative/plans" \
    "CLAUDE_CODE_SESSION_ID=bad-root" "$RESOLVER" create "$case_root" >/dev/null 2>&1; then
    test_fail "relative OCTOPUS_SESSION_PLANS was accepted"
else
    test_pass
fi

test_case "configured roots cannot target the global Claude config directory"
mkdir -p "$test_home/.claude"
if env "HOME=$test_home" "OCTOPUS_SESSION_PLANS=$test_home/.claude/plans" \
    "CLAUDE_CODE_SESSION_ID=bad-global-root" "$RESOLVER" create "$case_root" >/dev/null 2>&1; then
    test_fail "global Claude config storage was accepted"
elif [[ -e "$test_home/.claude/plans" ]]; then
    test_fail "rejected storage still created a directory in global Claude config"
else
    test_pass
fi

test_case "configured roots cannot reach global Claude config through a symlink"
ln -s "$test_home/.claude" "$case_root/global-config-link"
if env "HOME=$test_home" "OCTOPUS_SESSION_PLANS=$case_root/global-config-link/plans" \
    "CLAUDE_CODE_SESSION_ID=bad-symlink-root" "$RESOLVER" create "$case_root" >/dev/null 2>&1; then
    test_fail "symlinked global Claude config storage was accepted"
elif [[ -e "$test_home/.claude/plans" ]]; then
    test_fail "rejected symlink storage still created a global config directory"
else
    test_pass
fi

test_case "configured roots reject redundant separators before directory creation"
if env "HOME=$test_home" "OCTOPUS_SESSION_PLANS=$test_home//.claude/plans" \
    "CLAUDE_CODE_SESSION_ID=bad-empty-component-root" "$RESOLVER" create "$case_root" >/dev/null 2>&1; then
    test_fail "storage root with an empty path component was accepted"
elif [[ -e "$test_home/.claude/plans" ]]; then
    test_fail "rejected storage still created a directory in global Claude config"
else
    test_pass
fi

test_case "configured roots cannot reach global Claude config through dot-dot traversal"
mkdir -p "$test_home/work"
if env "HOME=$test_home" "OCTOPUS_SESSION_PLANS=$test_home/work/../.claude/plans" \
    "CLAUDE_CODE_SESSION_ID=bad-traversal-root" "$RESOLVER" create "$case_root" >/dev/null 2>&1; then
    test_fail "dot-dot traversal into global Claude config was accepted"
elif [[ -e "$test_home/.claude/plans" ]]; then
    test_fail "rejected dot-dot storage still created a global config directory"
else
    test_pass
fi

test_case "pointer metadata cannot reach global Claude config through a symlink"
pointer_attack_home="$case_root/pointer-attack-home"
pointer_attack_project="$case_root/pointer-attack-project"
mkdir -p "$pointer_attack_home/.claude" "$pointer_attack_project"
: > "$pointer_attack_project/package.json"
ln -s "$pointer_attack_home/.claude" "$pointer_attack_home/.claude-octopus"
pointer_failure=""
if env "HOME=$pointer_attack_home" "CLAUDE_CODE_SESSION_ID=pointer-attack" \
    "$RESOLVER" create "$pointer_attack_project" >/dev/null 2>&1; then
    pointer_failure="symlinked pointer storage was accepted"
elif [[ -e "$pointer_attack_home/.claude/state" ]]; then
    pointer_failure="rejected pointer storage still wrote into global Claude config"
fi
pointer_attack_checksum="$(printf '%s' "$pointer_attack_project" | cksum | awk '{print $1}')"
pointer_attack_file="$pointer_attack_home/.claude/state/plan-artifacts/pointer-attack/$pointer_attack_checksum.path"
pointer_attack_plan="$pointer_attack_project/.octo/plans/seeded-current-plan"
mkdir -p "${pointer_attack_file%/*}" "$pointer_attack_plan"
printf '%s\n%s\n' "$pointer_attack_project" "$pointer_attack_plan" > "$pointer_attack_file"
if [[ -n "$pointer_failure" ]]; then
    test_fail "$pointer_failure"
elif env "HOME=$pointer_attack_home" "CLAUDE_CODE_SESSION_ID=pointer-attack" \
    "$RESOLVER" current "$pointer_attack_project" >/dev/null 2>&1; then
    test_fail "current accepted a valid-looking pointer through a symlinked namespace"
else
    test_pass
fi

test_case "interrupted pointer writes remove their temporary file"
interrupt_bin="$case_root/interrupt-bin"
interrupt_home="$case_root/interrupt-home"
interrupt_project="$case_root/interrupt-project"
mkdir -p "$interrupt_bin" "$interrupt_home" "$interrupt_project"
apply_fixture="$interrupt_bin/mv"
printf '%s\n' '#!/bin/sh' 'kill -TERM "$PPID"' 'sleep 1' 'exit 143' > "$apply_fixture"
chmod +x "$apply_fixture"
interrupt_status=0
env "PATH=$interrupt_bin:$PATH" "HOME=$interrupt_home" \
    "CLAUDE_CODE_SESSION_ID=pointer-interrupt" \
    "$RESOLVER" create "$interrupt_project" >/dev/null 2>&1 || interrupt_status=$?
if [[ "$interrupt_status" -eq 143 ]] &&
   [[ -d "$interrupt_home/.claude-octopus/state/plan-artifacts/pointer-interrupt" ]] &&
   [[ -z "$(find "$interrupt_home/.claude-octopus/state/plan-artifacts/pointer-interrupt" \
       -type f -name '*.tmp.*' -print -quit)" ]]; then
    test_pass
else
    test_fail "interrupted write exited $interrupt_status or left temporary pointer metadata"
fi

test_case "plan-mode hook loads the latest intent contract from the shared resolver"
printf '%s\n' "unique intent contract body" > "$home_plan_dir_2/session-intent.md"
hook_output="$(cd "$case_root" && \
    printf '%s' '{"session_id":"home-session","cwd":"'"$test_home"'"}' | \
    env "HOME=$test_home" "CLAUDE_CODE_SESSION_ID=" "CLAUDE_SESSION_ID=" \
    "CLAUDE_CODE_SESSION=" "CLAUDE_PLUGIN_ROOT=$PROJECT_ROOT" \
    "CODEX_SESSION_ID=foreign-codex-session" "$HOOK")"
if [[ "$hook_output" == *"$home_plan_dir_2/session-intent.md"* &&
      "$hook_output" == *"unique intent contract body"* ]]; then
    test_pass
else
    test_fail "hook did not load the current resolved intent contract"
fi

test_case "plan command and review skills use the shared resolver"
if grep -Fc 'scripts/plan-storage.sh' "$PROJECT_ROOT/commands/plan.md" >/dev/null &&
   grep -Fc 'scripts/plan-storage.sh' "$PROJECT_ROOT/.cursor-plugin/commands/octo-plan.md" >/dev/null &&
   grep -Fc 'scripts/plan-storage.sh' "$PROJECT_ROOT/.claude/skills/skill-intent-contract/SKILL.md" >/dev/null &&
   grep -Fc 'scripts/plan-storage.sh' "$PROJECT_ROOT/.claude/skills/skill-staged-review/SKILL.md" >/dev/null &&
   grep -Fc 'scripts/plan-storage.sh' "$PROJECT_ROOT/skills/skill-intent-contract/SKILL.md" >/dev/null &&
   grep -Fc 'scripts/plan-storage.sh' "$PROJECT_ROOT/skills/skill-staged-review/SKILL.md" >/dev/null; then
    test_pass
else
    test_fail "one or more plan consumers bypass the shared resolver"
fi

test_case "plan commands check degraded plan mode before creating storage"
plan_guard_line="$(awk '/MANDATORY: Detect Plan Mode Write Conflict Before Starting/ { print NR; exit }' \
    "$PROJECT_ROOT/commands/plan.md")"
plan_storage_line="$(awk '/Resolve Plan Storage Location/ { print NR; exit }' \
    "$PROJECT_ROOT/commands/plan.md")"
plan_provider_line="$(awk '/^### Provider preflight$/ { print NR; exit }' \
    "$PROJECT_ROOT/commands/plan.md")"
cursor_guard_line="$(awk '/MANDATORY: Detect Plan Mode Write Conflict Before Starting/ { print NR; exit }' \
    "$PROJECT_ROOT/.cursor-plugin/commands/octo-plan.md")"
cursor_storage_line="$(awk '/Resolve Plan Storage Location/ { print NR; exit }' \
    "$PROJECT_ROOT/.cursor-plugin/commands/octo-plan.md")"
cursor_provider_line="$(awk '/^### Provider preflight$/ { print NR; exit }' \
    "$PROJECT_ROOT/.cursor-plugin/commands/octo-plan.md")"
if [[ -n "$plan_guard_line" && -n "$plan_storage_line" &&
      -n "$plan_provider_line" && -n "$cursor_guard_line" &&
      -n "$cursor_storage_line" && -n "$cursor_provider_line" &&
      "$plan_guard_line" -lt "$plan_storage_line" &&
      "$plan_guard_line" -lt "$plan_provider_line" &&
      "$cursor_guard_line" -lt "$cursor_storage_line" &&
      "$cursor_guard_line" -lt "$cursor_provider_line" ]]; then
    test_pass
else
    test_fail "one or more plan commands perform setup before checking degraded mode"
fi

test_case "plan completion messages use bullets and typed text fences"
completion_contract_failed=false
for plan_command in \
    "$PROJECT_ROOT/commands/plan.md" \
    "$PROJECT_ROOT/.cursor-plugin/commands/octo-plan.md"; do
    completion_block="$(sed -n '/^- \*\*Show completion message/,/^### Step 6:/p' "$plan_command")"
    if ! grep -Fc -- '- **Save plan to `${OCTO_PLAN_DIR}/session-plan.md`:**' "$plan_command" >/dev/null ||
       ! grep -Fc -- '- **Display the plan to the user**' "$plan_command" >/dev/null ||
       [[ "$completion_block" != *'- **Show completion message with the resolved absolute path:**'* ]] ||
       [[ "$completion_block" != *'```text'* ]]; then
        completion_contract_failed=true
        break
    fi
done
if [[ "$completion_contract_failed" == "false" ]]; then
    test_pass
else
    test_fail "one or more plan completion sections regressed its Markdown structure"
fi

test_case "plan examples do not advertise the obsolete project .claude path"
if grep -c '/path/to/project/.claude/session-plan.md' "$PROJECT_ROOT/commands/plan.md" >/dev/null; then
    test_fail "plan example still reports the obsolete project .claude path"
else
    test_pass
fi

test_summary
