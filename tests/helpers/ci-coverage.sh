#!/usr/bin/env bash
# Category discovery shared by the CI reachability checks. Exact shard coverage
# is tested separately against the real runner by test-ci-tiers.sh.

# List test Make targets named by the workflow without evaluating its text.
ci_make_targets() {
    local root="$1"
    sed 's/#.*//' "$root/.github/workflows/test.yml" |
        grep -ohE 'make test-[a-z0-9-]+' |
        awk '{print $2}' | sort -u
}

# Combine Make recipes and direct runner commands into one category inventory.
ci_test_categories() {
    local root="$1" target
    {
        while IFS= read -r target; do
            [[ -n "$target" ]] || continue
            awk -v target="$target" '
                $0 ~ "^" target ":" { in_target = 1; next }
                in_target && /^[[:alnum:]_.-]+:/ { exit }
                in_target && /run-all\.sh/ {
                    command = $0
                    sub(/^.*run-all\.sh[[:space:]]+/, "", command)
                    split(command, args, /[[:space:]]+/)
                    print args[1]
                    exit
                }
            ' "$root/Makefile"
        done < <(ci_make_targets "$root")
        sed 's/#.*//' "$root/.github/workflows/test.yml" |
            grep -oE 'run-all\.sh[[:space:]]+(smoke|unit|integration|root|live)([[:space:]]|$)' |
            awk '{print $2}'
    } | sort -u
}
