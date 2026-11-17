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
for template in state project roadmap config issues lessons; do
    for conditional in false true; do
        test_case "failed $template generation remains recoverable, conditional=$conditional"
        case "$template" in config) filename=config.json ;; *) filename=$(printf '%s' "$template" | tr '[:lower:]' '[:upper:]').md ;; esac
        workspace="$TEST_TMP_DIR/generator-$template-$conditional"
        mkdir -p "$workspace"
        # Begin with real saved templates, then remove just the failed target.
        (cd "$workspace" && OCTOPUS_PROJECT_PERSISTENCE=true bash "$helper" init_project >/dev/null)
        rm "$workspace/.octo/$filename"
        cp -R "$workspace/.octo" "$workspace/before"
        status=0
        (cd "$workspace" && OCTOPUS_PROJECT_PERSISTENCE=true bash -c '
            source "$1"
            generate_failed_template() { printf "%s" "incomplete output"; return 23; }
            eval "$2() { generate_failed_template; }"
            if [[ "$3" == true ]]; then
                if init_project; then exit 0; else exit $?; fi
            else
                set +e
                init_project
                exit $?
            fi
        ' test "$helper" "generate_${template}_template" "$conditional") >"$workspace/result" 2>&1 || status=$?
        if [[ "$status" -ne 0 && ! -e "$workspace/.octo/$filename" ]] &&
            diff -r "$workspace/before" "$workspace/.octo" >/dev/null &&
            ! grep -q 'Initialized .octo/' "$workspace/result" &&
            (cd "$workspace" && OCTOPUS_PROJECT_PERSISTENCE=true bash "$helper" init_project >/dev/null) &&
            [[ -s "$workspace/.octo/$filename" ]]; then
            test_pass
        else
            test_fail "generation failure published partial state or prevented retry"
        fi
    done
done
for mask in 0022 0077; do
    test_case "initial templates retain the access policy of umask $mask"
    workspace="$TEST_TMP_DIR/umask-$mask"
    mkdir -p "$workspace"
    if (cd "$workspace" && umask "$mask" && OCTOPUS_PROJECT_PERSISTENCE=true bash "$helper" init_project >/dev/null) &&
        python3 -I - "$workspace/.octo" "$mask" <<'PY_MODE'
from pathlib import Path
import stat
import sys
expected = 0o666 & ~int(sys.argv[2], 8)
files = [p for p in Path(sys.argv[1]).iterdir() if p.is_file()]
assert len(files) == 6
assert all(stat.S_IMODE(p.stat().st_mode) == expected for p in files)
PY_MODE
    then test_pass; else test_fail "initialization changed the caller's file access policy"; fi
done
test_summary
