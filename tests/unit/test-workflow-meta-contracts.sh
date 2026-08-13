#!/usr/bin/env bash
# Regression tests for workflow terminal-state and skill metadata contracts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="/tmp/octopus-tests-$$"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Workflow Meta Contracts"

DELIVER="$PROJECT_ROOT/skills/flow-deliver/SKILL.md"
DEVELOP="$PROJECT_ROOT/skills/flow-develop/SKILL.md"
DISCOVER="$PROJECT_ROOT/skills/flow-discover/SKILL.md"
DOCTOR="$PROJECT_ROOT/skills/skill-doctor/SKILL.md"
SECURITY_AUDIT="$PROJECT_ROOT/skills/octopus-security-audit/SKILL.md"
UI_UX_DESIGN="$PROJECT_ROOT/skills/octopus-ui-ux-design/SKILL.md"
CLAUDE_UI_UX_DESIGN="$PROJECT_ROOT/.claude/skills/skill-ui-ux-design/SKILL.md"
UI_UX_DESIGNS=("$UI_UX_DESIGN" "$CLAUDE_UI_UX_DESIGN")
VERIFY_GATE="$PROJECT_ROOT/skills/skill-verification-gate/SKILL.md"
ENFORCEMENT="$PROJECT_ROOT/skills/blocks/enforcement-patterns.md"
FABLE_RUNTIME="$PROJECT_ROOT/scripts/lib/fable5.sh"
CLAUDE_SDK_SHIM="$PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh"

delivery_block=$(sed -n '/^## Post-Delivery: Route to Ship/,/^\*\*Ready to validate!/p' "$DELIVER")
test_case "Review-only delivery stops without entering the shipping state"
if grep -q "route according to the user's explicit" <<< "$delivery_block" &&
   grep -q '^\- \*\*Ship requested:\*\*' <<< "$delivery_block" &&
   grep -q '^\- \*\*Branch wrap-up requested:\*\*' <<< "$delivery_block" &&
   grep -q '^\- \*\*Review only:\*\*' <<< "$delivery_block" &&
   grep -q 'Do not update the project' <<< "$delivery_block" &&
   grep -q 'Run this block only when the user explicitly requested shipping' <<< "$delivery_block" &&
   grep -q 'Read .*skill-ship/SKILL.md' <<< "$delivery_block" &&
   ! grep -q '^Suggest:' <<< "$delivery_block"; then
    test_pass
else
    test_fail "Post-Delivery must explicitly keep review-only requests out of shipping"
fi

develop_block=$(sed -n '/^## Post-Development: Checkpoint/,/^## /p' "$DEVELOP")
test_line=$(grep -n 'fresh targeted tests' <<< "$develop_block" | head -1 | cut -d: -f1 || true)
checkpoint_line=$(grep -n '^git tag ' <<< "$develop_block" | head -1 | cut -d: -f1 || true)
develop_complete_line=$(grep -n 'update_state' <<< "$develop_block" | head -1 | cut -d: -f1 || true)

test_case "Development verifies and checkpoints before completion state"
if [[ -n "$test_line" && -n "$checkpoint_line" && -n "$develop_complete_line" ]] &&
   (( test_line < checkpoint_line && checkpoint_line < develop_complete_line )); then
    test_pass
else
    test_fail "Post-Development must require fresh targeted tests and a checkpoint before update_state"
fi

discover_block=$(sed -n '/^## Post-Discovery: State Update/,/^## /p' "$DISCOVER")

extract_bash_fence() {
    awk '
        /^```bash$/ { if (!inside) { inside=1; next } }
        inside && /^```$/ { exit }
        inside { print }
    '
}
synthesis_line=$(grep -n 'if \[\[ ! -s' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
exit_line=$(grep -n '^[[:space:]]*exit 1$' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
present_line=$(grep -nF 'cat "$SYNTHESIS_FILE"' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
project_line=$(grep -n 'update_project' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
complete_line=$(grep -n 'update_state' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
opt_in_line=$(grep -n 'OCTOPUS_PROJECT_PERSISTENCE' <<< "$discover_block" | head -1 | cut -d: -f1 || true)

test_case "Discovery verifies and presents before optional project persistence"
if [[ -n "$synthesis_line" && -n "$exit_line" && -n "$present_line" && -n "$opt_in_line" && -n "$project_line" && -n "$complete_line" ]] &&
   (( synthesis_line < exit_line && exit_line < present_line && present_line < opt_in_line && opt_in_line < project_line && project_line < complete_line )) &&
   grep -Fq 'cat "$SYNTHESIS_FILE"' <<< "$discover_block" &&
   grep -Fq -- '--content-file "$SYNTHESIS_FILE"' <<< "$discover_block" &&
   ! grep -q -- '--content ' <<< "$discover_block" &&
   ! grep -Eq 'head -100|sed -n .1,100p.|See synthesis file' <<< "$discover_block" &&
   grep -q 'if ! .*update_project' <<< "$(tr '\n' ' ' <<< "$discover_block")"; then
    test_pass
else
    test_fail "Post-Discovery must present the complete synthesis and gate project persistence explicitly"
fi

test_case "Discovery terminal state makes PROJECT.md persistence explicit opt-in"
discover_terminal=$(sed -n '/^## Terminal State/,/^\*\*Ready to research!/p' "$DISCOVER")
if grep -q '\.octo/PROJECT\.md' <<< "$discover_terminal" &&
   grep -q 'OCTOPUS_PROJECT_PERSISTENCE=true' <<< "$discover_terminal"; then
    test_pass
else
    test_fail "Discover terminal state omitted the project persistence opt-in boundary"
fi

test_case "Discovery project persistence fails closed on every lifecycle write"
discover_pre=$(sed -n '/^## Pre-Discovery: Optional Project Persistence/,/^## /p' "$DISCOVER")
discover_pre_code=$(extract_bash_fence <<< "$discover_pre")
discover_post_code=$(extract_bash_fence <<< "$discover_block")
persistence_home="$TEST_TMP_DIR/persistence-home"
persistence_project="$TEST_TMP_DIR/persistence-project"
persistence_synthesis="$TEST_TMP_DIR/persistence-synthesis.md"
mkdir -p "$persistence_home/.claude-octopus/plugin/scripts" "$persistence_project"
printf '%s\n' fixture > "$persistence_synthesis"
cat > "$persistence_home/.claude-octopus/plugin/scripts/octo-state.sh" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "${OCTOPUS_TEST_FAIL_COMMAND:-}" ]] && exit 42
exit 0
EOF
chmod +x "$persistence_home/.claude-octopus/plugin/scripts/octo-state.sh"

persistence_baseline_ok=true
for lifecycle_code in "$discover_pre_code" "$discover_post_code"; do
    if ! (
        cd "$persistence_project"
        rm -rf .octo
        HOME="$persistence_home" \
        OCTOPUS_PROJECT_PERSISTENCE=true \
        SYNTHESIS_FILE="$persistence_synthesis" \
        bash -c "$lifecycle_code"
    ) >/dev/null 2>&1; then
        persistence_baseline_ok=false
        break
    fi
done

persistence_failed_closed=true
for lifecycle_case in init_project pre_update_state update_project post_update_state; do
    case "$lifecycle_case" in
        init_project) failure_command=init_project; lifecycle_code="$discover_pre_code" ;;
        pre_update_state) failure_command=update_state; lifecycle_code="$discover_pre_code" ;;
        update_project) failure_command=update_project; lifecycle_code="$discover_post_code" ;;
        post_update_state) failure_command=update_state; lifecycle_code="$discover_post_code" ;;
    esac
    if (
        cd "$persistence_project"
        rm -rf .octo
        HOME="$persistence_home" \
        OCTOPUS_PROJECT_PERSISTENCE=true \
        OCTOPUS_TEST_FAIL_COMMAND="$failure_command" \
        SYNTHESIS_FILE="$persistence_synthesis" \
        bash -c "$lifecycle_code"
    ) >/dev/null 2>&1; then
        persistence_failed_closed=false
        break
    fi
done
if [[ "$persistence_baseline_ok" != "true" ]]; then
    test_fail "Discover persistence fixture never succeeds; failure injection would prove nothing"
elif [[ "$persistence_failed_closed" == "true" ]]; then
    test_pass
else
    test_fail "Discover persistence continued after $lifecycle_case failed"
fi

test_case "Doctor quick-reference commands use the resolved plugin root"
doctor_quick_ref=$(sed -n '/^## Quick Reference/,$p' "$DOCTOR")
if grep -q '\$OCTO_PLUGIN_ROOT/scripts/orchestrate\.sh.*doctor auth --verbose' <<< "$doctor_quick_ref" &&
   grep -q '\$OCTO_PLUGIN_ROOT/scripts/orchestrate\.sh.*doctor --json' <<< "$doctor_quick_ref" &&
   ! grep -q '`bash scripts/orchestrate\.sh' <<< "$doctor_quick_ref"; then
    test_pass
else
    test_fail "Doctor quick reference bypasses its plugin-root resolver"
fi

test_case "Security audit fallback matches the runtime safety contract"
runtime_default=$(env -u OCTOPUS_FABLE5_FALLBACK_MODEL bash -c \
    'log(){ :; }; source "$1"; fable5_fallback_model' _ "$FABLE_RUNTIME")
runtime_invalid=$(env OCTOPUS_FABLE5_FALLBACK_MODEL=claude-fable-5 bash -c \
    'log(){ :; }; source "$1"; fable5_fallback_model' _ "$FABLE_RUNTIME")
if [[ "$runtime_default" == "claude-opus-5" && "$runtime_invalid" == "claude-opus-5" ]] &&
   grep -q 'OCTOPUS_FABLE5_FALLBACK_MODEL' "$SECURITY_AUDIT" &&
   grep -q 'OCTOPUS_FABLE5_NO_RETRY=1' "$SECURITY_AUDIT" &&
   grep -qi 'reject.*claude-fable-5\|claude-fable-5.*reject' "$SECURITY_AUDIT" &&
   grep -q 'OCTOPUS_FABLE5_NO_RETRY.*!=.*"1"' "$CLAUDE_SDK_SHIM" &&
   grep -q 'fallback_model.*claude-fable-5' "$CLAUDE_SDK_SHIM"; then
    test_pass
else
    test_fail "Security audit fallback, runtime default, invalid-target guard, or no-retry path drifted"
fi

test_case "UI/UX workflow resolves dials and stops on failed preflight"
ui_contract_ok=true
for ui_skill in "${UI_UX_DESIGNS[@]}"; do
    ui_flat=$(tr '\n' ' ' < "$ui_skill")
    if ! grep -q 'explicit user answer takes precedence' "$ui_skill" ||
       ! grep -q 'skip the Dials question' <<< "$ui_flat" ||
       ! grep -q 'integers from 1 through 10' "$ui_skill" ||
       ! grep -Eq '^\| Corporate / enterprise .*\| 3 \| 2 \| 4 \|' "$ui_skill" ||
       ! grep -Eq '^\| Brutalist / maximal .*\| 9 \| 8 \| 6 \|' "$ui_skill" ||
       ! grep -q 'Only continue to Step 4 when preflight returns `READY`' <<< "$ui_flat"; then
        ui_contract_ok=false
        break
    fi
done
if [[ "$ui_contract_ok" == true ]]; then
    test_pass
else
    test_fail "UI/UX dial or preflight branches are incomplete"
fi

test_case "UI/UX examples and critique obey the design-taste contract"
variant_contract_ok=true
for ui_skill in "${UI_UX_DESIGNS[@]}"; do
    comparison=$(sed -n '/comparison board using those actual values:/,/^\*\*Then ask the user/p' "$ui_skill")
    critique=$(sed -n '/^Critique dimensions:/,/^For each issue found/p' "$ui_skill")
    if grep -qE 'Alpine Signal|Bold Industrial|Cobalt Editorial|#EDF6F3|Azeret Mono' <<< "$comparison" ||
       ! grep -q 'VARIANT_A_PROVIDER' <<< "$comparison" ||
       ! grep -q 'VARIANT_B_PROVIDER' <<< "$comparison" ||
       ! grep -q 'VARIANT_C_PROVIDER' <<< "$comparison" ||
       ! grep -q 'VARIANT_A_RESULT' <<< "$comparison" ||
       ! grep -q 'VARIANT_B_RESULT' <<< "$comparison" ||
       ! grep -q 'VARIANT_C_RESULT' <<< "$comparison" ||
       ! grep -q '^```text$' <<< "$comparison" ||
       ! grep -q 'all five dimensions' "$ui_skill" ||
       [[ "$(grep -cE '^[1-5]\. (ACCESSIBILITY|PRACTICALITY|FIT|GAPS|SLOP)' <<< "$critique")" -ne 5 ]]; then
        variant_contract_ok=false
        break
    fi
done
if [[ "$variant_contract_ok" == true ]]; then
    test_pass
else
    test_fail "UI/UX example or five-dimension critique contradicts its hard constraints"
fi

test_case "UI/UX persistence atomically writes unique branch-scoped lineage"
persistence_contract_ok=true
for ui_skill in "${UI_UX_DESIGNS[@]}"; do
    persistence=$(sed -n '/^### STEP 8: Present Results and Persist/,/^\*\*Offer next steps:/p' "$ui_skill")
    lock_line=$(grep -nF 'exec 9>"$LOCK_FILE"' <<< "$persistence" | head -1 | cut -d: -f1 || true)
    prior_line=$(grep -n '^PRIOR=""$' <<< "$persistence" | head -1 | cut -d: -f1 || true)
    temp_line=$(grep -n 'TEMP_PATH=.*mktemp' <<< "$persistence" | head -1 | cut -d: -f1 || true)
    write_guard_line=$(grep -n '^if ! {$' <<< "$persistence" | head -1 | cut -d: -f1 || true)
    temp_check_line=$(grep -nF '[[ ! -s "$TEMP_PATH" ]]' <<< "$persistence" | head -1 | cut -d: -f1 || true)
    move_line=$(grep -nF 'mv "$TEMP_PATH" "$FILEPATH"' <<< "$persistence" | head -1 | cut -d: -f1 || true)
    unlock_line=$(grep -nF 'exec 9>&-' <<< "$persistence" | tail -1 | cut -d: -f1 || true)
    if [[ -z "$lock_line" || -z "$prior_line" || -z "$temp_line" || -z "$write_guard_line" || -z "$temp_check_line" || -z "$move_line" || -z "$unlock_line" ]] ||
       ! (( lock_line < prior_line && prior_line < temp_line && temp_line < write_guard_line && write_guard_line < temp_check_line && temp_check_line < move_line && move_line < unlock_line )) ||
       ! grep -Fq 'sha256sum' <<< "$persistence" ||
       ! grep -Fq 'shasum -a 256' <<< "$persistence" ||
       ! grep -Fq 'printf '\''%s'\'' "$RAW_BRANCH" | sha256sum' <<< "$persistence" ||
       ! grep -q 'no supported SHA-256 utility' <<< "$persistence" ||
       ! grep -Fq 'LOCK_FILE="${DESIGNS_DIR}/.${LOCK_DIGEST}.lineage.lock"' <<< "$persistence" ||
       grep -Fq 'LOCK_FILE="${DESIGNS_DIR}/.${BRANCH_KEY}.lineage.lock"' <<< "$persistence" ||
       ! grep -Fq 'flock -n 9' <<< "$persistence" ||
       ! grep -Fq 'lockf -s -t 0 9' <<< "$persistence" ||
       ! grep -q 'no supported file-lock utility' <<< "$persistence" ||
       ! grep -Fq 'LOCK_HELD=true' <<< "$persistence" ||
       ! grep -q 'another revision is being persisted' <<< "$persistence" ||
       grep -Fq 'mkdir "$LOCK_DIR"' <<< "$persistence" ||
       ! grep -q 'git_revision:' <<< "$persistence" ||
       ! grep -q 'supersedes:' <<< "$persistence" ||
       ! grep -q 'DESIGN_BODY' <<< "$persistence" ||
       ! grep -q 'XXXXXX' <<< "$persistence" ||
       ! grep -Fq '[[ -e "$FILEPATH" ]]' <<< "$persistence" ||
       ! grep -q 'must not supersede itself' <<< "$persistence" ||
       grep -Fq '} > "$FILEPATH"' <<< "$persistence" ||
       ! grep -q 'matches the current Git branch' <<< "$(tr '\n' ' ' <<< "$persistence")" ||
       ! grep -q 'detached HEAD' <<< "$persistence"; then
        persistence_contract_ok=false
        break
    fi
done
if [[ "$persistence_contract_ok" == true ]]; then
    test_pass
else
    test_fail "UI/UX persisted-design contract lacks a complete write, verification, or branch filter"
fi

run_documented_ui_persistence() {
    local test_home="$1"
    local design_body="$2"

    (
        cd "$PROJECT_ROOT"
        awk '
            /^### STEP 8: Present Results and Persist$/ { in_step = 1; next }
            in_step && /^```bash$/ { in_code = 1; next }
            in_code && /^```$/ { exit }
            in_code { print }
        ' "$CLAUDE_UI_UX_DESIGN" |
            env "HOME=${test_home}" "USER=octopus-test" "DESIGN_BODY=${design_body}" bash
    )
}

test_case "UI/UX OS lock blocks live writers and recovers after SIGKILL"
lock_fixture="$TEST_TMP_DIR/ui-lock-runtime"
lock_home="$lock_fixture/home"
lock_ready="$lock_fixture/ready"
lock_slug=$(basename "$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)")
lock_branch=$(git -C "$PROJECT_ROOT" branch --show-current || true)
lock_revision=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
if [[ -n "$lock_branch" ]]; then
    lock_raw_branch="$lock_branch"
else
    lock_raw_branch="detached:${lock_revision}"
fi
lock_designs_dir="$lock_home/.claude-octopus/designs/$lock_slug"
if command -v sha256sum >/dev/null 2>&1; then
    lock_digest=$(printf '%s' "$lock_raw_branch" | sha256sum | awk '{print $1}')
else
    lock_digest=$(printf '%s' "$lock_raw_branch" | shasum -a 256 | awk '{print $1}')
fi
lock_file="$lock_designs_dir/.${lock_digest}.lineage.lock"
mkdir -p "$lock_designs_dir"

(
    exec 9>"$lock_file" || exit 1
    if command -v flock >/dev/null 2>&1; then
        flock -n 9 || exit 1
    elif command -v lockf >/dev/null 2>&1; then
        lockf -s -t 0 9 || exit 1
    else
        exit 1
    fi
    : > "$lock_ready"
    while :; do
        # The child must not inherit fd 9; otherwise it could retain the lock
        # briefly after the holder is killed and make recovery timing flaky.
        sleep 1 9>&-
    done
) &
lock_holder_pid=$!

for lock_attempt in {1..50}; do
    [[ -f "$lock_ready" ]] && break
    sleep 0.1
done

set +e
lock_contention_output=$(run_documented_ui_persistence "$lock_home" "blocked design" 2>&1)
lock_contention_status=$?
set -e

kill -9 "$lock_holder_pid" 2>/dev/null || true
wait "$lock_holder_pid" 2>/dev/null || true

set +e
lock_recovery_output=$(run_documented_ui_persistence "$lock_home" "recovered design" 2>&1)
lock_recovery_status=$?
set -e
lock_document_count=$(find "$lock_designs_dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

if [[ -f "$lock_ready" ]] &&
   [[ "$lock_contention_status" -eq 1 ]] &&
   grep -q 'another revision is being persisted' <<< "$lock_contention_output" &&
   [[ "$lock_recovery_status" -eq 0 ]] &&
   grep -q 'Persisted design:' <<< "$lock_recovery_output" &&
   [[ "$lock_document_count" -eq 1 ]]; then
    test_pass
else
    test_fail "descriptor lock did not block a live writer or recover after SIGKILL"
fi

iron_law_count=$(grep -c '^NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE$' "$VERIFY_GATE" || true)
test_case "Verification gate states its Iron Law exactly once"
if [[ "$iron_law_count" -eq 1 ]]; then
    test_pass
else
    test_fail "found $iron_law_count copies"
fi

test_case "Enforcement pattern examples use language-tagged fences"
if awk '
    /^```/ {
        if (!inside && $0 == "```") bad = 1
        inside = !inside
    }
    END { exit (bad || inside) ? 1 : 0 }
' "$ENFORCEMENT"; then
    test_pass
else
    test_fail "found an untagged fenced code block"
fi

trigger_only_contracts=(
    'skill-intent-contract|Use when starting a complex or ambiguous task that risks scope drift'
    'skill-native-escalation-routing|Use when choosing native or multi-LLM handling for init, review, or security requests'
    'skill-review-response|Use when a reviewer, CI bot, or another AI leaves feedback to address'
    'skill-staged-review|Use when a PR or feature needs both specification and code-quality review'
    'skill-verification-gate|Use when about to declare work complete, fixed, passing, or done'
    'skill-verify|Use when a nontrivial change needs end-to-end verification before committing or shipping'
)

metadata_ok=true
for contract in "${trigger_only_contracts[@]}"; do
    skill=${contract%%|*}
    expected=${contract#*|}
    description=$(sed -n 's/^description: *"\(.*\)"$/\1/p' \
        "$PROJECT_ROOT/skills/$skill/SKILL.md" | head -1 || true)
    if [[ "$description" != "$expected" ]]; then
        metadata_ok=false
        break
    fi
done

test_case "Trigger-only skill descriptions state when to use the skill"
if [[ "$metadata_ok" == true ]]; then
    test_pass
else
    test_fail "$skill description must be the exact trigger-only contract"
fi

test_summary
