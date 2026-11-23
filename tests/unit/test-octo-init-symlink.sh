#!/usr/bin/env bash
# Existing .octo links must not redirect project initialization (#1304).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Project initialization symlink boundary"

sandbox="$(mktemp -d "$TEST_TMP_DIR/init-symlink.XXXXXX")"
initializer="${1:-$PROJECT_ROOT/scripts/octo-state.sh}"

snapshot() {
    python3 - "$1" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
print(root.exists())
if root.exists():
    for path in sorted(root.rglob('*')):
        print(path.relative_to(root), path.stat().st_mode,
              hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else 'directory')
PY
}

run_initializer() (
    local caller="$1" checkout="$2"
    shift 2
    cd "$checkout" || return $?
    case "$caller" in
        cli) bash "$initializer" init_project "$@" ;;
        sourced) bash -c 'source "$1"; shift; init_project "$@"' _ "$initializer" "$@" ;;
        conditional) bash -c '
            source "$1"; shift
            if init_project "$@"; then
                exit 0
            else
                rc=$?
                printf "caller retained control\n"
                exit "$rc"
            fi
        ' _ "$initializer" "$@" ;;
    esac
)

for caller in cli sourced conditional; do
    for link in relative absolute; do
        for target_state in empty partial initialized dangling; do
            case_root="$sandbox/$caller-$link-$target_state"
            checkout="$case_root/project"
            destination="$case_root/external"
            mkdir -p "$checkout"
            if [[ "$target_state" != dangling ]]; then
                mkdir -p "$destination"
                if [[ "$target_state" == partial || "$target_state" == initialized ]]; then
                    printf 'Retain saved project content\n' > "$destination/PROJECT.md"
                fi
                if [[ "$target_state" == initialized ]]; then
                    printf 'Retain saved state\n' > "$destination/STATE.md"
                fi
            fi
            link_target="$destination"
            [[ "$link" != relative ]] || link_target='../external'
            ln -s "$link_target" "$checkout/.octo"
            before="$(snapshot "$destination")"

            for operation in actual preview; do
                set --
                [[ "$operation" != preview ]] || set -- --dry-run
                test_case "$caller $operation refuses $link link to $target_state target"
                rc=0
                output="$(run_initializer "$caller" "$checkout" "$@" 2>&1)" || rc=$?
                after="$(snapshot "$destination")"
                if [[ "$rc" -ne 0 && "$output" == *"symbolic link"* &&
                      "$after" == "$before" && -L "$checkout/.octo" &&
                      "$(readlink "$checkout/.octo")" == "$link_target" ]]; then
                    if [[ "$caller" != conditional || "$output" == *"caller retained control"* ]]; then
                        test_pass
                    else
                        test_fail "initializer exited the sourced caller: $output"
                    fi
                else
                    test_fail "rc=$rc; linked target changed or refusal missing: $output"
                fi
            done

            test_case "$caller $link $target_state can initialize after removing link"
            rm "$checkout/.octo"
            if (cd "$checkout" && bash "$initializer" init_project >/dev/null) &&
               [[ -f "$checkout/.octo/STATE.md" && ! -L "$checkout/.octo" &&
                  "$(snapshot "$destination")" == "$before" ]]; then
                test_pass
            else
                test_fail "retry failed or modified the old link destination"
            fi
        done
    done
done

test_case "ordinary initialized directory preserves saved state on retry"
printf 'Saved session\n' > "$checkout/.octo/STATE.md"
before="$(snapshot "$checkout/.octo")"
if (cd "$checkout" && bash "$initializer" init_project >/dev/null) &&
   [[ "$(snapshot "$checkout/.octo")" == "$before" ]]; then
    test_pass
else
    test_fail "repeat initialization changed saved state"
fi

test_summary
