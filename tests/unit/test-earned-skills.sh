#!/bin/bash
# tests/unit/test-earned-skills.sh
# Tests earned skills system (v8.18.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Earned Skills System"

TEST_WORKSPACE="/tmp/octopus-test-skills-$$"

setup_skills_env() {
    rm -rf "$TEST_WORKSPACE"
    mkdir -p "$TEST_WORKSPACE"
    WORKSPACE_DIR="$TEST_WORKSPACE"
    log() { :; }
}

cleanup_skills_env() {
    rm -rf "$TEST_WORKSPACE"
}

# Define functions inline for unit testing
earn_skill() {
    local name="$1"
    local source="$2"
    local pattern="$3"
    local context="${4:-}"
    local example="${5:-}"

    local skills_dir="${WORKSPACE_DIR}/.octo/skills/earned"
    mkdir -p "$skills_dir"

    local safe_name
    safe_name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    local skill_file="$skills_dir/${safe_name}.md"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local occurrence=1
    if [[ -f "$skill_file" ]]; then
        occurrence=$(( $(grep -c "^#### Occurrence" "$skill_file" 2>/dev/null || echo "0") + 1 ))
    fi

    local confidence="low"
    [[ $occurrence -ge 3 ]] && confidence="medium"
    [[ $occurrence -ge 5 ]] && confidence="high"

    cat >> "$skill_file" << SKILLEOF
#### Occurrence $occurrence | $timestamp | source: $source
**Pattern:** ${pattern:0:300}
**Context:** ${context:-General}
**Example:** ${example:-None provided}
**Confidence:** $confidence
---
SKILLEOF

    if [[ $occurrence -eq 1 ]]; then
        local tmp_file="${skill_file}.tmp"
        {
            echo "# Earned Skill: $name"
            echo "**Confidence:** $confidence | **Occurrences:** $occurrence"
            echo ""
            cat "$skill_file"
        } > "$tmp_file" && mv "$tmp_file" "$skill_file"
    else
        if grep -q "^\*\*Confidence:\*\*" "$skill_file"; then
            sed -i.bak "s/^\*\*Confidence:\*\*.*/\*\*Confidence:\*\* $confidence | \*\*Occurrences:\*\* $occurrence/" "$skill_file"
            rm -f "${skill_file}.bak"
        fi
    fi

    local skill_count
    skill_count=$(ls -1 "$skills_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$skill_count" -gt 20 ]]; then
        local lowest_file="" lowest_count=999
        for sf in "$skills_dir"/*.md; do
            local sc
            sc=$(grep -c "^#### Occurrence" "$sf" 2>/dev/null || echo "0")
            if [[ $sc -lt $lowest_count ]]; then
                lowest_count=$sc
                lowest_file="$sf"
            fi
        done
        if [[ -n "$lowest_file" && "$lowest_file" != "$skill_file" ]]; then
            local archive_dir="$skills_dir/archived"
            mkdir -p "$archive_dir"
            mv "$lowest_file" "$archive_dir/"
        fi
    fi
}

load_earned_skills() {
    local skills_dir="${WORKSPACE_DIR}/.octo/skills/earned"
    if [[ ! -d "$skills_dir" ]]; then
        return
    fi
    local skills_content=""
    for skill_file in "$skills_dir"/*.md; do
        [[ -f "$skill_file" ]] || continue
        local header
        header=$(head -3 "$skill_file")
        local latest
        latest=$(grep -A 5 "^#### Occurrence" "$skill_file" | tail -6)
        skills_content="${skills_content}
${header}
${latest}
"
    done
    if [[ -n "$skills_content" ]]; then
        echo "$skills_content"
    fi
}

# ── Tests ──

test_skill_creation() {
    test_case "earn_skill creates skill file in .octo/skills/earned/"
    setup_skills_env

    earn_skill "test-pattern" "test" "A test pattern" "Testing" "example"

    if [[ -f "$TEST_WORKSPACE/.octo/skills/earned/test-pattern.md" ]]; then
        test_pass
    else
        test_fail "Skill file not created"
    fi
    cleanup_skills_env
}

test_skill_header() {
    test_case "New skill has correct header"
    setup_skills_env

    earn_skill "my-skill" "test" "A pattern"

    local content
    content=$(head -2 "$TEST_WORKSPACE/.octo/skills/earned/my-skill.md")

    if echo "$content" | grep -q "# Earned Skill: my-skill" && \
       echo "$content" | grep -q "Confidence.*low"; then
        test_pass
    else
        test_fail "Header wrong: $content"
    fi
    cleanup_skills_env
}

test_confidence_lifecycle_low() {
    test_case "First occurrence has low confidence"
    setup_skills_env

    earn_skill "conf-test" "test" "pattern"

    if grep -q "Confidence.*low" "$TEST_WORKSPACE/.octo/skills/earned/conf-test.md"; then
        test_pass
    else
        test_fail "Expected low confidence"
    fi
    cleanup_skills_env
}

test_confidence_lifecycle_medium() {
    test_case "3+ occurrences reach medium confidence"
    setup_skills_env

    for i in 1 2 3; do
        earn_skill "conf-test" "test" "pattern $i"
    done

    if grep -q "Confidence.*medium" "$TEST_WORKSPACE/.octo/skills/earned/conf-test.md"; then
        test_pass
    else
        local content
        content=$(cat "$TEST_WORKSPACE/.octo/skills/earned/conf-test.md")
        test_fail "Expected medium confidence: $content"
    fi
    cleanup_skills_env
}

test_confidence_lifecycle_high() {
    test_case "5+ occurrences reach high confidence"
    setup_skills_env

    for i in 1 2 3 4 5; do
        earn_skill "conf-test" "test" "pattern $i"
    done

    if grep -q "Confidence.*high" "$TEST_WORKSPACE/.octo/skills/earned/conf-test.md"; then
        test_pass
    else
        test_fail "Expected high confidence"
    fi
    cleanup_skills_env
}

test_max_limit_archival() {
    test_case "Exceeding 20 skills archives lowest-confidence"
    setup_skills_env

    # Create 21 unique skills (first 20 with 1 occurrence, 21st triggers archival)
    for i in $(seq 1 21); do
        earn_skill "skill-$(printf '%02d' $i)" "test" "pattern $i"
    done

    local active_count
    active_count=$(ls -1 "$TEST_WORKSPACE/.octo/skills/earned/"*.md 2>/dev/null | wc -l | tr -d ' ')
    local archived
    archived=$(ls -1 "$TEST_WORKSPACE/.octo/skills/earned/archived/"*.md 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$active_count" -le 20 && "$archived" -ge 1 ]]; then
        test_pass
    else
        test_fail "Expected <=20 active ($active_count) and >=1 archived ($archived)"
    fi
    cleanup_skills_env
}

test_load_earned_skills() {
    test_case "load_earned_skills returns content"
    setup_skills_env

    earn_skill "load-test" "test" "A pattern to load"
    local result
    result=$(load_earned_skills)

    if [[ -n "$result" ]] && echo "$result" | grep -q "load-test"; then
        test_pass
    else
        test_fail "Failed to load skills: $result"
    fi
    cleanup_skills_env
}

test_load_empty() {
    test_case "load_earned_skills returns empty when no skills"
    setup_skills_env

    local result
    result=$(load_earned_skills)

    if [[ -z "$result" ]]; then
        test_pass
    else
        test_fail "Expected empty, got: $result"
    fi
    cleanup_skills_env
}

test_name_sanitization() {
    test_case "Skill names are sanitized for filenames"
    setup_skills_env

    earn_skill "My Skill! @#$% 123" "test" "pattern"

    if [[ -f "$TEST_WORKSPACE/.octo/skills/earned/my-skill-123.md" ]]; then
        test_pass
    else
        local files
        files=$(ls "$TEST_WORKSPACE/.octo/skills/earned/" 2>/dev/null)
        test_fail "Sanitized filename not found. Files: $files"
    fi
    cleanup_skills_env
}

test_dry_run_no_crash() {
    test_case "Dry-run probe works with earned skills code"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed: $exit_code"
    fi
}

# Run all tests
test_skill_creation
test_skill_header
test_confidence_lifecycle_low
test_confidence_lifecycle_medium
test_confidence_lifecycle_high
test_max_limit_archival
test_load_earned_skills
test_load_empty
test_name_sanitization
test_dry_run_no_crash

test_summary
