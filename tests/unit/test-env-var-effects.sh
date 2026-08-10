#!/usr/bin/env bash
# Every documented OCTOPUS_* variable must be accounted for (#749).
#
# Four variables shipped inert in a single release cycle and no test noticed:
#
#   #720  OCTOPUS_REVIEWER_FLIP                 octo_features_choice only forwards
#                                               values matching a declared choice,
#                                               so =1 was dropped — while a comment
#                                               promised it worked
#   #710  OCTOPUS_COMMANDCODE_PERMISSION_MODE   the shim accepted it, but dispatch
#                                               always passed a positional argument
#                                               that overrode it
#   —     invocation: human_only                custom key stripped at build time;
#                                               enforcement was a hardcoded list
#
# These share one root cause. Every one had passing tests around it.
# The failure was never "nobody tested this function" — it was that the
# documentation and the enforcement live in different files with nothing linking
# them. This suite is the link: it derives its work list FROM the documentation.
#
# It deliberately does not try to assert all 41 variables. It asserts that none is
# unaccounted for, which is the property that rots silently.
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Documented env-var accountability (#749)"

MANIFEST="$SCRIPT_DIR/fixtures/env-var-effects.tsv"

# Same harvest the manifest was generated from. Kept here rather than in a helper
# so the sources being treated as "documentation" are visible at the assertion.
documented_vars() {
    grep -rhoE 'OCTOPUS_[A-Z0-9_]+' \
        "$PROJECT_ROOT/CLAUDE.md" \
        "$PROJECT_ROOT"/docs/*.md \
        "$PROJECT_ROOT/config/features.json" 2>/dev/null | sort -u
}

manifest_vars() { grep -vE '^\s*(#|$)' "$MANIFEST" 2>/dev/null | cut -f1 | sort -u; }
manifest_kind() { grep -m1 -E "^$1	" "$MANIFEST" 2>/dev/null | cut -f2; }
manifest_detail() { grep -m1 -E "^$1	" "$MANIFEST" 2>/dev/null | cut -f3; }

test_case "the manifest exists and parses"
if [[ -f "$MANIFEST" ]] && [[ -n "$(manifest_vars)" ]]; then
    test_pass
else
    test_fail "missing or empty $MANIFEST"
fi

test_case "documentation actually yields variables (guards a vacuous pass)"
n="$(documented_vars | grep -c . || true)"
if [[ "${n:-0}" -ge 20 ]]; then
    test_pass
else
    test_fail "harvested only ${n} variables — the sources or the pattern changed, so every assertion below would be vacuous"
fi

# The assertion that matters. A variable added to the docs without a manifest
# entry fails here, which is what makes this self-maintaining.
test_case "every documented variable has a manifest entry"
missing="$(comm -23 <(documented_vars) <(manifest_vars) || true)"
count="$(printf '%s' "$missing" | grep -c . || true)"
if [[ "${count:-0}" -eq 0 ]]; then
    test_pass
else
    test_fail "${count} documented variable(s) unaccounted for: $(printf '%s' "$missing" | tr '\n' ' ')— add a covered-by, skip or placeholder entry to $(basename "$MANIFEST")"
fi

# The other direction: a manifest entry for a variable no longer documented is
# stale, and a stale entry hides the fact that coverage is no longer needed.
test_case "the manifest names no variable that is no longer documented"
stale="$(comm -13 <(documented_vars) <(manifest_vars) || true)"
count="$(printf '%s' "$stale" | grep -c . || true)"
if [[ "${count:-0}" -eq 0 ]]; then
    test_pass
else
    test_fail "${count} stale entr(ies): $(printf '%s' "$stale" | tr '\n' ' ')— remove them from $(basename "$MANIFEST")"
fi

test_case "every kind is one of covered-by, skip or placeholder"
bad=""
while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    case "$(manifest_kind "$v")" in
        covered-by|skip|placeholder) ;;
        *) bad="$bad $v" ;;
    esac
done < <(manifest_vars)
if [[ -z "$bad" ]]; then test_pass; else test_fail "unknown kind for:$bad"; fi

# A covered-by pointing at a file that does not exist, or that never mentions the
# variable, is coverage on paper only — exactly the state the four bugs above were
# in before they were found.
test_case "every covered-by target exists and mentions its variable"
bad=""
while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    [[ "$(manifest_kind "$v")" == "covered-by" ]] || continue
    f="$SCRIPT_DIR/$(manifest_detail "$v")"
    if [[ ! -f "$f" ]]; then bad="$bad ${v}(no-file)"; continue; fi
    grep -q -- "$v" "$f" || bad="$bad ${v}(not-mentioned)"
done < <(manifest_vars)
if [[ -z "$bad" ]]; then test_pass; else test_fail "broken covered-by entries:$bad"; fi

# Skips must justify themselves. An unexplained skip is indistinguishable from an
# oversight six months later.
test_case "every skip carries a reason"
bad=""
while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    [[ "$(manifest_kind "$v")" == "skip" ]] || continue
    d="$(manifest_detail "$v")"
    if [[ -z "$d" || "$d" == TODO* ]]; then bad="$bad $v"; fi
done < <(manifest_vars)
if [[ -z "$bad" ]]; then test_pass; else test_fail "skip without a reason (or still TODO):$bad"; fi

# Ratchet: coverage may improve, never regress. The floor decreases only when a
# covered variable is deliberately retired; direct Gemini routing removed one.
test_case "covered-by count has not fallen below its recorded floor"
FLOOR=26
now="$(grep -c $'\tcovered-by\t' "$MANIFEST" || true)"
if [[ "${now:-0}" -ge "$FLOOR" ]]; then
    test_pass
else
    test_fail "covered-by fell from ${FLOOR} to ${now} — a variable lost its assertion; raise the floor only when it increases"
fi

# A placeholder is a claim that the harvester matched documentation prose rather
# than a variable. Verify: a real variable is read somewhere in the codebase.
test_case "no placeholder is actually read by the code"
bad=""
while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    [[ "$(manifest_kind "$v")" == "placeholder" ]] || continue
    if grep -rq -- "\${${v}[:-]" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/hooks" 2>/dev/null; then
        bad="$bad $v"
    fi
done < <(manifest_vars)
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "marked placeholder but read as a variable:$bad — reclassify as covered-by or skip"
fi

test_summary
