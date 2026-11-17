#!/usr/bin/env bash
# Exercise actual initialization when a file appears after the missing-file check.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "project initialization publication races"
helper="${OCTO_INIT_TEST_HELPER:-$PROJECT_ROOT/scripts/octo-state.sh}"
for template in state project roadmap config issues lessons; do
    for kind in file symlink directory; do
        test_case "initialization preserves a concurrent $kind for $template"
        case "$template" in config) filename=config.json ;; *) filename=$(printf '%s' "$template" | tr '[:lower:]' '[:upper:]').md ;; esac
        workspace="$TEST_TMP_DIR/$template-$kind"
        mkdir -p "$workspace"
        # The generator runs after init_project has admitted a missing path.
        # Publish another writer's file at exactly that point, without sleeps.
        status=0
        (cd "$workspace" && bash -euo pipefail -c '
            source "$1"
            race_file=$3 race_kind=$4
            generate_racing_template() {
                case "$race_kind" in
                    file) printf "%s\n" "concurrent content" > ".octo/$race_file" ;;
                    symlink) printf "%s\n" "external content" > external; ln -s ../external ".octo/$race_file" ;;
                    directory) mkdir ".octo/$race_file" ;;
                esac
                printf "%s\n" "unpublished template"
            }
            eval "generate_${2}_template() { generate_racing_template; }"
            init_project
        ' test "$helper" "$template" "$filename" "$kind" > init.log 2>&1) || status=$?
        preserved=false
        case "$kind" in
            file) [[ -f "$workspace/.octo/$filename" && $(cat "$workspace/.octo/$filename") == 'concurrent content' ]] && preserved=true ;;
            symlink) [[ -L "$workspace/.octo/$filename" && $(cat "$workspace/external") == 'external content' ]] && preserved=true ;;
            directory) [[ -d "$workspace/.octo/$filename" && -z $(ls -A "$workspace/.octo/$filename") ]] && preserved=true ;;
        esac
        if [[ "$status" -eq 0 && "$preserved" == true && -z $(find "$workspace/.octo" -name '*.tmp.*' -print) ]]; then test_pass
        else test_fail "status=$status preserved=$preserved"; fi
    done
done
test_summary
