#!/usr/bin/env bash
# Tests for skill-design-lineage: design document persistence, revision chains, cross-session discovery
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Design Lineage"

SKILL_FILE="$(resolve_claude_skill_path "skill-design-lineage")"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

assert_contains() {
  local output="$1" pattern="$2" label="$3"
  grep -qE "$pattern" <<< "$output" && pass "$label" || fail "$label" "missing: $pattern"
}

assert_not_contains() {
  local output="$1" pattern="$2" label="$3"
  grep -qE "$pattern" <<< "$output" && fail "$label" "should not contain: $pattern" || pass "$label"
}

# ── File exists ──────────────────────────────────────────────────────────────

if [[ -f "$SKILL_FILE" ]]; then
  pass "skill-design-lineage.md exists"
else
  fail "skill-design-lineage.md exists" "file not found at $SKILL_FILE"
  echo "FATAL: skill file not found, cannot continue"
  exit 1
fi

SKILL_CONTENT=$(<"$SKILL_FILE")

# ── YAML frontmatter structure ───────────────────────────────────────────────

FIRST_LINE=$(head -n 1 "$SKILL_FILE")
if [[ "$FIRST_LINE" == "---" ]]; then
  pass "frontmatter: opening delimiter present"
else
  fail "frontmatter: opening delimiter present" "first line is not ---"
fi

CLOSING_DELIM=$(tail -n +2 "$SKILL_FILE" | grep -c '^---$' || true)
if [[ "$CLOSING_DELIM" -ge 1 ]]; then
  pass "frontmatter: closing delimiter present"
else
  fail "frontmatter: closing delimiter present" "no closing --- found"
fi

# Extract frontmatter (between first and second ---)
FRONTMATTER=$(awk '/^---$/{if(++count==2) exit} count==1' "$SKILL_FILE")

# ── Required frontmatter fields ──────────────────────────────────────────────

assert_contains "$FRONTMATTER" "^name: skill-design-lineage" "frontmatter: name field is skill-design-lineage"

assert_contains "$FRONTMATTER" "design-lineage" "frontmatter: aliases include design-lineage"

assert_contains "$FRONTMATTER" "design-docs" "frontmatter: aliases include design-docs"

assert_contains "$FRONTMATTER" "design-history" "frontmatter: aliases include design-history"

assert_contains "$FRONTMATTER" "description:" "frontmatter: description field present"

assert_contains "$FRONTMATTER" "trigger:" "frontmatter: trigger field present"

# ── Trigger phrases ──────────────────────────────────────────────────────────

assert_contains "$FRONTMATTER" "save design" "frontmatter: trigger mentions save design"

assert_contains "$FRONTMATTER" "design document" "frontmatter: trigger mentions design document"

assert_contains "$FRONTMATTER" "design history" "frontmatter: trigger mentions design history"

assert_contains "$FRONTMATTER" "find prior designs" "frontmatter: trigger mentions find prior designs"

# ── Storage location documented ──────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "~/.claude-octopus/designs/" "storage: ~/.claude-octopus/designs/ location documented"

assert_contains "$SKILL_CONTENT" "project.slug" "storage: project-scoped via slug"

# ── Filename format documented ───────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "user.*branch.*design.*datetime" "filename: user-branch-design-datetime format documented"

assert_contains "$SKILL_CONTENT" "YYYYMMDD" "filename: datetime format includes date component"

# ── Design doc template sections ─────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "Problem Statement" "template: Problem Statement section present"

assert_contains "$SKILL_CONTENT" "Constraints" "template: Constraints section present"

assert_contains "$SKILL_CONTENT" "Approaches Considered" "template: Approaches Considered section present"

assert_contains "$SKILL_CONTENT" "Recommendation" "template: Recommendation section present"

assert_contains "$SKILL_CONTENT" "Open Questions" "template: Open Questions section present"

# ── Frontmatter metadata fields in template ──────────────────────────────────

assert_contains "$SKILL_CONTENT" "branch:" "template metadata: branch field documented"

assert_contains "$SKILL_CONTENT" "user:" "template metadata: user field documented"

assert_contains "$SKILL_CONTENT" "created:" "template metadata: created field documented"

assert_contains "$SKILL_CONTENT" "supersedes:" "template metadata: supersedes field documented"

# ── Revision chain (Supersedes) ──────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "[Ss]upersedes" "revision chain: supersedes concept documented"

assert_contains "$SKILL_CONTENT" "revision" "revision chain: revision concept mentioned"

assert_contains "$SKILL_CONTENT" "prior design|prior document|prior version" "revision chain: links to prior design"

# ── Cross-session discovery ──────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "grep -li" "discovery: grep-based keyword search documented"

assert_contains "$SKILL_CONTENT" "head -10" "discovery: search limited to 10 results"

assert_contains "$SKILL_CONTENT" "deliver.*review.*develop" "discovery: downstream commands mentioned"

assert_contains "$SKILL_CONTENT" "flow-discover" "discovery: integration with flow-discover"

assert_contains "$SKILL_CONTENT" "flow-define" "discovery: integration with flow-define"

assert_contains "$SKILL_CONTENT" "flow-develop" "discovery: integration with flow-develop"

# ── Branch tracking ──────────────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "git rev-parse --abbrev-ref HEAD" "branch tracking: git branch detection documented"

assert_contains "$SKILL_CONTENT" "slashes replaced with dashes" "branch tracking: slash sanitization documented"

# ── Immutability rule ────────────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "read-only after creation" "immutability: read-only after creation documented"

# ── Caps and limits ──────────────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "50 design docs|Max 50" "caps: 50 design doc limit documented"

assert_contains "$SKILL_CONTENT" "10 results" "caps: 10 result search limit documented"

assert_contains "$SKILL_CONTENT" "500 lines" "caps: 500 line template limit documented"

# ── Description length check (must be <= 120 chars per superpowers hardening) ─

DESC_LINE=$(grep '^description:' "$SKILL_FILE" | head -1)
DESC_VALUE=${DESC_LINE#description: }
DESC_VALUE=${DESC_VALUE#\"}
DESC_VALUE=${DESC_VALUE%\"}
DESC_LEN=${#DESC_VALUE}
if [[ "$DESC_LEN" -le 120 ]]; then
  pass "description length <= 120 chars (actual: $DESC_LEN)"
else
  fail "description length <= 120 chars" "actual: $DESC_LEN"
fi

# ── No banned words in description ───────────────────────────────────────────

assert_not_contains "$DESC_VALUE" "independent|compound|team of teams|claude instances" "description: no banned words"

# ── No attribution to external sources ───────────────────────────────────────

assert_not_contains "$SKILL_CONTENT" "gstack" "no attribution: does not reference gstack"

assert_not_contains "$SKILL_CONTENT" "office-hours" "no attribution: does not reference office-hours"

assert_not_contains "$SKILL_CONTENT" "github\.com/[a-z].*source" "no attribution: no source repo references"
# Execute the actual revision-selection recipe with two distinct branches
# whose legacy filename slugs are identical.
fixture="$TEST_TMP_DIR/branch-identity"
mkdir -p "$fixture/project" "$fixture/home"
git -C "$fixture/project" init -q
git -C "$fixture/project" symbolic-ref HEAD refs/heads/feature/auth
git -C "$fixture/project" -c user.name=Test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit -q --allow-empty -m "Initial commit"
mkdir -p "$fixture/plain" "$fixture/unborn"
git -C "$fixture/unborn" init -q
designs_dir="$fixture/home/.claude-octopus/designs/project"
mkdir -p "$designs_dir"
write_design() {
    printf '%s\n' '---' "branch: $2" '---' "$3" > "$designs_dir/$1"
}
older="reviewer-feature-auth-design-20260101-010101.md"
current="reviewer-feature-auth-design-20260102-010101.md"
other="reviewer-feature-auth-design-20260103-010101.md"
write_design "$older" 'feature/auth' 'Older design'
write_design "$current" 'feature/auth' 'Latest matching design'
write_design "$other" 'feature-auth' $'Unrelated design\nbranch: feature/auth'
touch -t 202601010101 "$designs_dir/$older"
touch -t 202601020101 "$designs_dir/$current"
touch -t 202601030101 "$designs_dir/$other"

design_recipe() {
    awk -v step="$2" -v recipe="${3:-1}" '
        /^## Step / {
            if (section) exit
            section = index($0, "## Step " step ":") == 1
        }
        section && /^```bash$/ { block = ++count == recipe; next }
        block && /^```$/ { exit }
        block { print }
    ' "$1"
}

for tree in skills .claude/skills codex-skills; do
    skill="$PROJECT_ROOT/$tree/skill-design-lineage/SKILL.md"
    save=$(design_recipe "$skill" 1)
    lookup=$(design_recipe "$skill" 3)
    walk=$(design_recipe "$skill" 3 2)
    discovery=$(design_recipe "$skill" 4)

    for project in plain unborn project; do
        expected_branch=no-branch
        if [[ "$project" == project ]]; then
            expected_branch=feature/auth
        fi
        expected_slug=${expected_branch//\//-}
        test_case "$tree saves and finds a design on $expected_branch ($project fixture)"
        if (
            cd "$fixture/$project" || exit 1
            export HOME="$fixture/$tree-$project-home" USER=reviewer
            export GIT_CEILING_DIRECTORIES="$fixture"
            output=$(bash -c "$save") || exit 1
            saved_path=${output#Design saved to }
            expected_prefix="$HOME/.claude-octopus/designs/$project/reviewer-$expected_slug-design-"
            [[ "$saved_path" == "$expected_prefix"*.md ]] || exit 1
            grep -Fxq "branch: $expected_branch" "$saved_path" || exit 1
            chosen=$(bash -c "$lookup"$'\nprintf "%s" "$SUPERSEDES"') || exit 1
            [[ "$chosen" == "${saved_path##*/}" ]]
        ); then
            test_pass
        else
            test_fail "expected a filename for $expected_branch and matching revision lookup"
        fi
    done

    test_case "$tree preserves all designs when saves share a timestamp"
    if (
        cd "$fixture/project" || exit 1
        export HOME="$fixture/$tree-save-home" USER=reviewer
        export DESIGNS_DIR="$HOME/.claude-octopus/designs/project"
        first="$DESIGNS_DIR/reviewer-feature-auth-design-20260401-010101.md"
        date() {
            case "$2" in
                +%Y%m%d-%H%M%S) printf '%s\n' '20260401-010101' ;;
                +%Y-%m-%dT%H:%M:%SZ) printf '%s\n' '2026-04-01T01:01:01Z' ;;
                *) command date "$@" ;;
            esac
        }
        export -f date
        output=$(bash -c "$save") || exit 1
        [[ "$output" == "Design saved to $first" ]] || exit 1
        original=$(cat "$first") || exit 1
        save_and_walk="$save"$'\n'"$walk"
        SUPERSEDES="${first##*/}" bash -c "$save_and_walk" > "$HOME/first-history" &
        save_pid=$!
        SUPERSEDES="${first##*/}" bash -c "$save_and_walk" > "$HOME/second-history"
        second_status=$?
        wait "$save_pid" && [[ "$second_status" -eq 0 ]] || exit 1
        [[ $(cat "$first") == "$original" ]] || exit 1
        set -- "$DESIGNS_DIR"/*.md
        [[ $# -eq 3 ]] || exit 1
        for design in "$@"; do
            [[ "$design" == "$first" ]] && continue
            grep -Fxq "supersedes: ${first##*/}" "$design" || exit 1
            grep -Fxq '## Open Questions' "$design" || exit 1
        done
        for history in "$HOME/first-history" "$HOME/second-history"; do
            saved_path=$(sed -n '1s/^Design saved to //p' "$history")
            [[ -f "$saved_path" && "$saved_path" != "$first" ]] || exit 1
            expected_history="${saved_path##*/}"$'\n'"${first##*/}"
            [[ $(tail -n +2 "$history") == "$expected_history" ]] || exit 1
        done
        set -- "$DESIGNS_DIR"/.design-*
        [[ ! -e "$1" ]]
    ); then
        test_pass
    else
        test_fail "same-timestamp saves lost a revision or walked the wrong history"
    fi

    test_case "$tree links the newest design on the exact branch"
    if chosen=$(cd "$fixture/project" &&
        HOME="$fixture/home" DESIGNS_DIR="$designs_dir" bash -c "$lookup"$'\nprintf "%s" "${SUPERSEDES:-}"') &&
        [[ "$chosen" == "$current" ]]; then
        test_pass
    else
        test_fail "expected $current, got ${chosen:-<none>}"
    fi

    test_case "$tree reads only same-branch design context in newest-first order"
    if discovered=$(cd "$fixture/project" &&
        HOME="$fixture/home" bash -c "$lookup"$'\n'"$discovery"$'\nprintf "%s" "${DESIGN_CONTEXT:-}"') &&
        [[ "$discovered" == *"$current"*"$older"*'Latest matching design'* && "$discovered" != *"$other"* ]]; then
        test_pass
    else
        test_fail "workflow context included the wrong designs"
    fi
done

test_summary
