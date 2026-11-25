#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Factory workflow cost approval"

mkdir -p "$TEST_TMP_DIR/plugin/scripts" "$TEST_TMP_DIR/bin"
cat > "$TEST_TMP_DIR/plugin/scripts/orchestrate.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' invoked >> "$FACTORY_TEST_DISPATCH.count"
printf '%s\n' "$@" > "$FACTORY_TEST_DISPATCH"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMP_DIR/bin/codex"
chmod +x "$TEST_TMP_DIR/plugin/scripts/orchestrate.sh" "$TEST_TMP_DIR/bin/codex"

# Exercise the published Bash recipes using a spec and an inert dispatcher.
cd "$TEST_TMP_DIR"
printf '# Factory spec\n' > '<spec_path>'
export CLAUDE_PLUGIN_ROOT="$TEST_TMP_DIR/plugin"
export FACTORY_TEST_DISPATCH="$TEST_TMP_DIR/dispatched"
export PATH="$TEST_TMP_DIR/bin:$PATH"
for surface in .claude/skills/skill-factory/SKILL.md skills/skill-factory/SKILL.md \
    codex-skills/skill-factory/SKILL.md commands/factory.md .cursor-plugin/commands/octo-factory.md; do
    operations=(factory)
    [[ "$surface" == *SKILL.md ]] && operations+=(spawn)
    for operation in "${operations[@]}"; do
        recipe="$TEST_TMP_DIR/$operation.sh"
        awk -v operation="$operation" '
            /^\140\140\140bash$/ { body = ""; found = 0; in_block = 1; next }
            /^\140\140\140$/ && in_block { if (found) print body; in_block = 0; next }
            in_block {
                body = body $0 "\n"
                if (operation == "spawn" && /orchestrate\.sh.* spawn /) found = 1
                if (operation == "factory" && /factory --spec /) found = 1
            }
        ' "$PROJECT_ROOT/$surface" > "$recipe"
        for approval in decline '' skip approve approve-ci; do
            test_case "$surface $operation with approval '${approval:-missing}'"
            rm -f "$FACTORY_TEST_DISPATCH" "$FACTORY_TEST_DISPATCH.count"
            rc=0
            FACTORY_COST_APPROVAL="$approval" bash -e "$recipe" > output 2>&1 || rc=$?
            case "$approval" in
                approve|approve-ci)
                    expected_ci=false
                    actual_ci=false
                    [[ "$operation:$approval" == factory:approve-ci ]] && expected_ci=true
                    grep -qx -- --ci "$FACTORY_TEST_DISPATCH" 2>/dev/null && actual_ci=true
                    if [[ "$rc" == 0 && -s "$FACTORY_TEST_DISPATCH" &&
                          -s "$FACTORY_TEST_DISPATCH.count" &&
                          "$(cat "$FACTORY_TEST_DISPATCH.count")" == invoked &&
                          "$(head -n 1 "$FACTORY_TEST_DISPATCH")" == "$operation" &&
                          "$actual_ci" == "$expected_ci" ]]; then
                        test_pass
                    else
                        test_fail "expected one approved $operation dispatch and the matching CI flag"
                    fi
                    ;;
                *)
                    if [[ "$rc" != 0 && ! -e "$FACTORY_TEST_DISPATCH" &&
                          ! -e "$FACTORY_TEST_DISPATCH.count" ]]; then
                        test_pass
                    else
                        test_fail "expected the recipe to stop before dispatch"
                    fi
                    ;;
            esac
        done
    done
done
test_summary
