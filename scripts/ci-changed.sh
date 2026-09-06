#!/usr/bin/env bash
# Select a proportional local gate from changed paths, failing closed to ci-local.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$PROJECT_ROOT/tests/changed-scope.tsv"

LIST_ONLY=false
UNIT_ONLY=false
SKIP_SMOKE=false
COMMITTED_ONLY=false
BASE_REF="${OCTOPUS_CHANGED_BASE:-}"
declare -a EXPLICIT_CHANGED=()
declare -a CHANGED_FILES=()
declare -a SELECTED_SUITES=()
declare -a MAPPING_LINES=()
declare -a FULL_REASONS=()
FULL_MATRIX=false

usage() {
    cat <<'EOF'
Usage: scripts/ci-changed.sh [--list] [--base REF] [--changed PATH ...]

Select and run a fail-closed local test gate from the changed files.
  --list          Print the deterministic plan without running it
  --base REF      Compare committed changes against REF
  --changed PATH  Test an explicit changed path instead of reading Git (repeatable)
  --unit-only     Fail closed to the unit suite instead of the complete local matrix
  --skip-smoke    Do not repeat the smoke gate (for CI jobs that run it separately)
  --committed-only Ignore worktree-only changes (for clean-checkout CI callers)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)
            LIST_ONLY=true
            shift
            ;;
        --base)
            [[ $# -ge 2 ]] || { echo "ERROR: --base requires a ref" >&2; exit 2; }
            BASE_REF="$2"
            shift 2
            ;;
        --changed)
            [[ $# -ge 2 ]] || { echo "ERROR: --changed requires a path" >&2; exit 2; }
            EXPLICIT_CHANGED+=("$2")
            shift 2
            ;;
        --unit-only)
            UNIT_ONLY=true
            shift
            ;;
        --skip-smoke)
            SKIP_SMOKE=true
            shift
            ;;
        --committed-only)
            COMMITTED_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

cd "$PROJECT_ROOT"

array_contains() {
    local needle="$1"
    shift
    local item=""
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

append_unique_changed() {
    local path="$1"
    [[ -n "$path" ]] || return 0
    if ! array_contains "$path" ${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}; then
        CHANGED_FILES+=("$path")
    fi
}

append_selected_suite() {
    local suite="$1"
    local changed="$2"
    local pattern="$3"
    if [[ ! -f "$suite" ]]; then
        FULL_MATRIX=true
        FULL_REASONS+=("mapping '$pattern' for '$changed' names missing suite '$suite'")
        return 0
    fi
    if ! array_contains "$suite" ${SELECTED_SUITES[@]+"${SELECTED_SUITES[@]}"}; then
        SELECTED_SUITES+=("$suite")
    fi
}

if [[ ${#EXPLICIT_CHANGED[@]} -gt 0 ]]; then
    for changed in "${EXPLICIT_CHANGED[@]}"; do
        append_unique_changed "$changed"
    done
else
    if [[ -z "$BASE_REF" ]]; then
        if git rev-parse --verify --quiet upstream/main >/dev/null; then
            BASE_REF="upstream/main"
        elif git rev-parse --verify --quiet origin/main >/dev/null; then
            BASE_REF="origin/main"
        fi
    fi

    committed_changed=""
    unstaged_changed=""
    staged_changed=""
    untracked_changed=""
    if [[ -z "$BASE_REF" ]] || ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
        FULL_MATRIX=true
        FULL_REASONS+=("no valid comparison base is available")
    elif ! git merge-base "$BASE_REF" HEAD >/dev/null 2>&1; then
        FULL_MATRIX=true
        FULL_REASONS+=("comparison base '$BASE_REF' has no merge base with HEAD")
    else
        if ! committed_changed="$(git diff --name-only "${BASE_REF}...HEAD" 2>/dev/null)"; then
            FULL_MATRIX=true
            FULL_REASONS+=("failed to diff committed changes from '$BASE_REF'")
        fi
    fi
    if [[ "$COMMITTED_ONLY" == "false" ]]; then
        if ! unstaged_changed="$(git diff --name-only 2>/dev/null)"; then
            FULL_MATRIX=true
            FULL_REASONS+=("failed to inspect unstaged changes")
        fi
        if ! staged_changed="$(git diff --cached --name-only 2>/dev/null)"; then
            FULL_MATRIX=true
            FULL_REASONS+=("failed to inspect staged changes")
        fi
        if ! untracked_changed="$(git ls-files --others --exclude-standard 2>/dev/null)"; then
            FULL_MATRIX=true
            FULL_REASONS+=("failed to inspect untracked changes")
        fi
    fi
    while IFS= read -r changed; do append_unique_changed "$changed"; done < <(
        printf '%s\n' "$committed_changed" "$unstaged_changed" "$staged_changed" "$untracked_changed" |
            sed '/^$/d' | LC_ALL=C sort -u
    )
fi

if [[ ! -f "$MANIFEST" ]]; then
    FULL_MATRIX=true
    FULL_REASONS+=("changed-scope manifest is missing")
fi

if [[ ${#CHANGED_FILES[@]} -gt 1 ]]; then
    declare -a SORTED_CHANGED=()
    while IFS= read -r changed; do SORTED_CHANGED+=("$changed"); done < <(
        printf '%s\n' "${CHANGED_FILES[@]}" | LC_ALL=C sort -u
    )
    CHANGED_FILES=("${SORTED_CHANGED[@]}")
fi

if [[ "$FULL_MATRIX" == "false" ]]; then
    for changed in ${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}; do
        matched=false
        while IFS=$'\t' read -r pattern suite_spec; do
            pattern="${pattern%$'\r'}"
            suite_spec="${suite_spec%$'\r'}"
            [[ -n "$pattern" && "$pattern" != \#* ]] || continue
            # Manifest entries are intentional globs, not literal strings.
            # shellcheck disable=SC2053
            if [[ "$changed" == $pattern ]]; then
                matched=true
                MAPPING_LINES+=("$changed <= $pattern => $suite_spec")
                if [[ -z "$suite_spec" ]]; then
                    FULL_MATRIX=true
                    FULL_REASONS+=("mapping '$pattern' for '$changed' has no suite policy")
                    continue
                fi
                case "$suite_spec" in
                    @full)
                        FULL_MATRIX=true
                        FULL_REASONS+=("'$changed' matches full-matrix rule '$pattern'")
                        ;;
                    @ignore)
                        ;;
                    @self)
                        append_selected_suite "$changed" "$changed" "$pattern"
                        ;;
                    *)
                        for suite_glob in $suite_spec; do
                            found_suite=false
                            while IFS= read -r suite; do
                                [[ -n "$suite" ]] || continue
                                found_suite=true
                                append_selected_suite "$suite" "$changed" "$pattern"
                            done < <(compgen -G "$suite_glob" | LC_ALL=C sort || true)
                            if [[ "$found_suite" == "false" ]]; then
                                FULL_MATRIX=true
                                FULL_REASONS+=("mapping '$pattern' for '$changed' matched no suite for '$suite_glob'")
                            fi
                        done
                        ;;
                esac
            fi
        done < "$MANIFEST"
        if [[ "$matched" == "false" ]]; then
            FULL_MATRIX=true
            FULL_REASONS+=("unmapped changed path '$changed'")
        fi
    done
fi

if [[ "$FULL_MATRIX" == "false" ]]; then
    append_selected_suite "tests/unit/test-suite-reachability.sh" "always" "always"
fi

# The PR unit lane is intentionally unit-only. Integration mappings remain
# covered by the separate integration gate, while local `make ci-changed` keeps
# its broader focused selection when this flag is not set.
if [[ "$UNIT_ONLY" == "true" && ${#SELECTED_SUITES[@]} -gt 0 ]]; then
    declare -a UNIT_SUITES=()
    for suite in "${SELECTED_SUITES[@]}"; do
        if [[ "$suite" == tests/unit/* ]]; then
            UNIT_SUITES+=("$suite")
        fi
    done
    SELECTED_SUITES=()
    if [[ ${#UNIT_SUITES[@]} -gt 0 ]]; then
        SELECTED_SUITES=("${UNIT_SUITES[@]}")
    fi
fi

if [[ "$FULL_MATRIX" == "false" && ${#SELECTED_SUITES[@]} -gt 1 ]]; then
    declare -a SORTED_SUITES=()
    while IFS= read -r suite; do SORTED_SUITES+=("$suite"); done < <(
        printf '%s\n' "${SELECTED_SUITES[@]}" | LC_ALL=C sort -u
    )
    SELECTED_SUITES=("${SORTED_SUITES[@]}")
fi

if [[ "$FULL_MATRIX" == "true" ]]; then
    echo "Mode: full"
else
    echo "Mode: focused"
fi
echo "Changed files:"
if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
    echo "  - (none)"
else
    for changed in "${CHANGED_FILES[@]}"; do echo "  - $changed"; done
fi

if [[ ${#MAPPING_LINES[@]} -gt 0 ]]; then
    echo "Mappings:"
    for mapping in "${MAPPING_LINES[@]}"; do echo "  - $mapping"; done
fi

if [[ "$FULL_MATRIX" == "true" ]]; then
    echo "Reasons:"
    for reason in ${FULL_REASONS[@]+"${FULL_REASONS[@]}"}; do echo "  - $reason"; done
    if [[ "$UNIT_ONLY" == "true" ]]; then
        echo "Command: make test-unit"
    else
        echo "Command: make ci-local"
    fi
    [[ "$LIST_ONLY" == "true" ]] && exit 0
    make sync-check
    if [[ "$SKIP_SMOKE" != "true" ]]; then
        make test-smoke
    fi
    if [[ "$UNIT_ONLY" == "true" ]]; then
        exec make test-unit
    fi
    exec make ci-local
fi

if [[ "$SKIP_SMOKE" == "true" ]]; then
    echo "Always: make sync-check"
else
    echo "Always: make sync-check, make test-smoke"
fi
echo "Selected suites:"
for suite in "${SELECTED_SUITES[@]}"; do echo "  - $suite"; done
[[ "$LIST_ONLY" == "true" ]] && exit 0

make sync-check
if [[ "$SKIP_SMOKE" != "true" ]]; then
    make test-smoke
fi

declare -a SUITE_ARGS=()
for suite in "${SELECTED_SUITES[@]}"; do
    SUITE_ARGS+=("--suite=$suite")
done
bash tests/run-all-tests.sh "${SUITE_ARGS[@]}"
