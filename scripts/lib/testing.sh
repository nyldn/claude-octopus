#!/usr/bin/env bash
# testing.sh — Extracted from orchestrate.sh
# Contains: validate_tangle_results, squeeze_test

# Validate tangle results with quality gate
# v3.0: Supports configurable threshold and loop-until-approved retry logic

extract_explicit_file_refs() {
    local text="$1"

    printf '%s\n' "$text" \
        | grep -oE '(src|lib|app|test|tests|docs|pkg|cmd|internal|scripts|config|public|assets|components|pages|utils|hooks|services|models|controllers|routes|middleware|api)/[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,5}|\./[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,5}' 2>/dev/null \
        | sed 's#^\./##' \
        | head -100 \
        | sort -u || true
}

extract_tangle_result_output() {
    local result_file="$1"

    awk '
        /^## Output[[:space:]]*$/ { capture = 1; next }
        /^## Status:/ { capture = 0 }
        capture { print }
    ' "$result_file" 2>/dev/null || true
}

check_explicit_file_coverage() {
    local original_prompt="$1"
    local output_corpus="$2"
    local missing=""
    local output_refs=""
    local ref

    output_refs="$(extract_explicit_file_refs "$output_corpus")"

    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        case $'\n'"$output_refs"$'\n' in
            *$'\n'"$ref"$'\n'*) ;;
            *) missing+="${ref}"$'\n' ;;
        esac
    done <<< "$(extract_explicit_file_refs "$original_prompt")"

    printf '%s' "$missing"
}

snapshot_tangle_worktree_paths() {
    local repo_root=""

    if [[ -n "${PROJECT_ROOT:-}" ]]; then
        if [[ -d "$PROJECT_ROOT" ]]; then
            repo_root=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)
            [[ -n "$repo_root" ]] || return 0
        else
            repo_root=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)
        fi
    else
        repo_root=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)
    fi
    [[ -n "$repo_root" ]] || return 0

    {
        git -C "$repo_root" diff --name-only 2>/dev/null || true
        git -C "$repo_root" diff --cached --name-only 2>/dev/null || true
        git -C "$repo_root" ls-files --others --exclude-standard 2>/dev/null || true
    } | sed /^$/d | sort -u
}

tangle_prompt_requires_worktree_changes() {
    local original_prompt="$1"
    local mode="${OCTOPUS_TANGLE_REQUIRE_WORKTREE_CHANGES:-auto}"

    case "$mode" in
        false|off|0|no)
            return 1
            ;;
        true|on|1|yes)
            return 0
            ;;
    esac

    if [[ -n "$(extract_explicit_file_refs "$original_prompt")" ]]; then
        return 0
    fi

    local impl_hits
    impl_hits=$(printf '%s\n' "$original_prompt" \
        | grep -Eic '\b(implement|build|create|add|update|modify|edit|fix|refactor|wire|integrate|feature|component|command|route|hook|template|test|tests|typescript|javascript|code|app|ui)\b' 2>/dev/null || true)
    impl_hits=${impl_hits%%$'\n'*}
    [[ ${impl_hits:-0} -gt 0 ]]
}

check_tangle_worktree_changes() {
    local before_file="$1"
    local current_file
    current_file=$(mktemp "${TMPDIR:-/tmp}/octo-tangle-worktree-after.XXXXXX") || return 0

    snapshot_tangle_worktree_paths > "$current_file" 2>/dev/null || true
    if [[ -f "$before_file" ]]; then
        comm -13 <(sort -u "$before_file") <(sort -u "$current_file")
    fi
    rm -f "$current_file"
}

validate_tangle_results() {
    local task_group="$1"
    local original_prompt="$2"
    local worktree_before_file="${3:-}"
    local validation_file="${RESULTS_DIR}/tangle-validation-${task_group}.md"
    local quality_retry_count=0

    while true; do
        # Collect all results
        local results=""
        local result_outputs=""
        local success_count=0
        local fail_count=0
        FAILED_SUBTASKS=""  # Reset for this validation pass (string-based)

        for result in "$RESULTS_DIR"/*-tangle-${task_group}*.md; do
            [[ -f "$result" ]] || continue
            [[ "$result" == *validation* ]] && continue

            # v8.20.0: Run file path validation (non-blocking warnings)
            if [[ "${OCTOPUS_FILE_VALIDATION:-true}" == "true" ]] && type run_file_validation &>/dev/null 2>&1; then
                local agent_from_file
                agent_from_file=$(basename "$result" .md | sed 's/tangle-[0-9]*-//')
                run_file_validation "$agent_from_file" "$(cat "$result" 2>/dev/null)" 2>/dev/null || true
            fi

            if grep -q "Status: SUCCESS" "$result" 2>/dev/null; then
                ((success_count++)) || true
            else
                ((fail_count++)) || true
                # Store the failed result file for retry (if loop-until-approved enabled).
                # The retry path reconstructs the original prompt plus failure feedback from
                # the result artifact. This preserves multiline task context and avoids
                # treating output-quality failures as provider-unavailability failures.
                if [[ "$LOOP_UNTIL_APPROVED" == "true" ]]; then
                    FAILED_SUBTASKS="${FAILED_SUBTASKS}result:${result}"$'\n'
                fi
            fi
            results+="$(<"$result")\n\n---\n\n"
            result_outputs+="$(extract_tangle_result_output "$result")"$'\n'
        done

        local missing_explicit_files
        missing_explicit_files=$(check_explicit_file_coverage "$original_prompt" "$result_outputs")
        local worktree_changes=""
        local requires_worktree_changes=false
        if [[ -n "$worktree_before_file" && -f "$worktree_before_file" ]] && \
           tangle_prompt_requires_worktree_changes "$original_prompt"; then
            requires_worktree_changes=true
            worktree_changes=$(check_tangle_worktree_changes "$worktree_before_file")
        fi

        # Quality gate check (using configurable per-phase threshold - v8.19.0)
        local tangle_threshold
        tangle_threshold=$(get_gate_threshold "tangle")
        local total=$((success_count + fail_count))
        local success_rate=0
        [[ $total -gt 0 ]] && success_rate=$((success_count * 100 / total))

        local gate_status="PASSED"
        local gate_color="${GREEN}"
        if [[ $success_rate -lt $tangle_threshold ]]; then
            gate_status="FAILED"
            gate_color="${RED}"
        elif [[ $success_rate -lt 90 ]]; then
            gate_status="WARNING"
            gate_color="${YELLOW}"
        fi

        if [[ -n "$missing_explicit_files" ]]; then
            gate_status="FAILED"
            gate_color="${RED}"
            log WARN "Tangle missing explicit file coverage: $(echo "$missing_explicit_files" | tr '\n' ' ')" 2>/dev/null || true
        fi

        if [[ "$requires_worktree_changes" == "true" && -z "$worktree_changes" ]]; then
            gate_status="FAILED"
            gate_color="${RED}"
            log WARN "Tangle produced no new worktree changes for an implementation task" 2>/dev/null || true
        fi

        # v8.20.1: Record quality gate metric
        record_task_metric "quality_gate" "$success_rate" 2>/dev/null || true

        # v8.19.0: Log threshold applied
        write_structured_decision \
            "quality-gate" \
            "validate_tangle_results" \
            "Quality gate ${gate_status}: ${success_rate}% success rate (threshold: ${tangle_threshold}%)" \
            "tangle-${task_group}" \
            "$(if [[ $success_rate -ge 90 ]]; then echo "high"; elif [[ $success_rate -ge $tangle_threshold ]]; then echo "medium"; else echo "low"; fi)" \
            "Success: ${success_count}/${total}, failures: ${fail_count}, threshold: ${tangle_threshold}%" \
            "" 2>/dev/null || true

        # ═══════════════════════════════════════════════════════════════════════
        # v8.31.0: Anti-sycophancy challenge — devil's advocate on high-pass results
        # Runs silently when results pass too easily (90%+), forcing a critical look
        # ═══════════════════════════════════════════════════════════════════════
        if [[ "$gate_status" == "PASSED" && $success_rate -ge 90 && "${OCTOPUS_ANTISYCOPHANCY:-true}" != "false" ]]; then
            echo -e "  ${DIM}Running anti-sycophancy check...${NC}"
            # Randomized bypass token prevents prompt injection from LLM-generated results
            local clean_token="GENUINELY_CLEAN_${RANDOM}${RANDOM}"
            local challenge_result=""
            challenge_result=$(run_agent_sync "claude-sonnet" "
IMPORTANT: Do NOT read, explore, or modify any files. Do NOT run any shell commands. Output TEXT only.

You are a DEVIL'S ADVOCATE reviewer. This implementation passed quality gates with ${success_rate}% success.

YOUR JOB: Find problems the initial review MISSED. Assume the reviewers were too lenient.
Identify at least 2 concrete issues or risks.

If you genuinely cannot find real issues, respond with exactly: ${clean_token}
and explain why each concern is actually handled correctly.

Do NOT say 'looks good' without specific evidence.
Do NOT invent problems that don't exist — but be genuinely critical.

Original task: ${original_prompt}

Results to challenge:
$(head -c 3000 <<< "$results")
" 60 "code-reviewer" "quality-gate") || true

            if [[ -n "$challenge_result" ]] && ! echo "$challenge_result" | grep -Fc "$clean_token" >/dev/null 2>&1; then
                gate_status="CHALLENGED"
                gate_color="${YELLOW}"
                echo -e "  ${YELLOW}⚠ Anti-sycophancy challenge raised concerns — review recommended${NC}"
                log WARN "Anti-sycophancy challenge raised concerns on ${success_rate}% pass rate"
                results+="
---
## Anti-Sycophancy Challenge (v8.31.0)
$challenge_result
"
            else
                echo -e "  ${GREEN}✓ Anti-sycophancy check passed — results confirmed${NC}"
            fi
        fi

        # ═══════════════════════════════════════════════════════════════════════
        # CONDITIONAL BRANCHING - Quality gate decision tree
        # ═══════════════════════════════════════════════════════════════════════
        local quality_branch
        quality_branch=$(evaluate_quality_branch "$success_rate" "$quality_retry_count")

        # Write validation report before branching so abort/escalate/retry paths
        # still leave an actionable artifact for embrace and post-run diagnosis.
        cat > "$validation_file" << EOF
# TANGLE Phase Validation Report
## Task: $original_prompt
## Generated: $(date)

### Quality Gate: ${gate_status}
- Success Rate: ${success_rate}% (threshold: ${tangle_threshold}%)
- Successful: ${success_count}/${total} result files
- Failed: ${fail_count}/${total} result files
- Decision Branch: ${quality_branch}
- Retry Attempts: ${quality_retry_count}/$(quality_retry_limit)

### Explicit File Coverage
$(if [[ -n "$missing_explicit_files" ]]; then
    echo "#### Missing Explicit File Coverage"
    echo "$missing_explicit_files" | sed '/^$/d; s/^/- /'
else
    echo "All explicit file references from the task were covered by tangle outputs."
fi)

### Worktree Change Evidence
$(if [[ "$requires_worktree_changes" == "true" ]]; then
    if [[ -n "$worktree_changes" ]]; then
        echo "Tangle produced worktree changes:"
        echo "$worktree_changes" | sed '/^$/d; s/^/- /'
    else
        echo "#### Missing Worktree Changes"
        echo "This prompt was classified as implementation work, but tangle produced no new modified, staged, or untracked paths. Agents likely returned analysis/plans instead of applying edits."
    fi
else
    echo "Not required for this prompt."
fi)

### Subtask Results
$results
EOF

        case "$quality_branch" in
            proceed|proceed_warn)
                # Quality gate passed - continue to delivery
                ;;
            retry)
                # Retry failed tasks
                if ! quality_retry_limit_reached "$quality_retry_count"; then
                    ((quality_retry_count++)) || true
                    local retry_limit_display
                    retry_limit_display=$(quality_retry_limit)
                    echo ""
                    echo -e "${YELLOW}${_BOX_TOP}${NC}"
                    echo -e "${YELLOW}║  🐙 Branching: Retry Path (attempt $quality_retry_count/$retry_limit_display)                    ║${NC}"
                    echo -e "${YELLOW}${_BOX_BOT}${NC}"
                    log WARN "Quality gate at ${success_rate}%, below ${tangle_threshold}%. Retrying..."
                    # v8.18.0: Lock providers that failed quality gate
                    while IFS= read -r failed_task; do
                        [[ -z "$failed_task" ]] && continue
                        local failed_agent=""
                        if [[ "$failed_task" == result:* ]]; then
                            local failed_result="${failed_task#result:}"
                            failed_agent=$(awk '/^# Agent: / { sub(/^# Agent: /, ""); print; exit }' "$failed_result" 2>/dev/null || true)
                            failed_agent="${failed_agent%% *}"
                            if [[ -z "$failed_agent" ]]; then
                                local failed_base
                                failed_base=$(basename "$failed_result" .md)
                                if [[ "$failed_base" == *-tangle-* ]]; then
                                    failed_agent="${failed_base%%-tangle-*}"
                                fi
                            fi
                            # Result-file retries are output-quality retries, not provider
                            # availability failures. Keep the same provider by default.
                            [[ "${OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER:-false}" == "true" && -n "$failed_agent" ]] && lock_provider "$failed_agent"
                        else
                            failed_agent="${failed_task%%:*}"
                            [[ -n "$failed_agent" ]] && lock_provider "$failed_agent"
                        fi
                    done <<< "$FAILED_SUBTASKS"
                    retry_failed_subtasks "$task_group" "$quality_retry_count"
                    sleep 3
                    continue  # Re-validate
                else
                    log ERROR "Max retries ($(quality_retry_limit)) exceeded. Proceeding with ${success_rate}%"
                fi
                ;;
            escalate)
                # Human decision required
                echo ""
                echo -e "${YELLOW}${_BOX_TOP}${NC}"
                echo -e "${YELLOW}║  🐙 Branching: Escalate Path (human review)               ║${NC}"
                echo -e "${YELLOW}${_BOX_BOT}${NC}"
                echo -e "${YELLOW}Quality gate FAILED. Manual review required.${NC}"
                echo -e "${YELLOW}Results at: ${RESULTS_DIR}/tangle-validation-${task_group}.md${NC}"
                # Claude Code v2.1.9: CI mode auto-fails on escalation
                if [[ "$CI_MODE" == "true" ]]; then
                    log ERROR "CI mode: Quality gate FAILED - aborting (no human review available)"
                    echo "::error::Quality gate failed in tangle phase - manual review required"
                    return 1
                fi
                read -p "Continue anyway? (y/n) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log ERROR "User declined to continue after quality gate failure"
                    return 1
                fi
                ;;
            abort)
                # Abort workflow
                echo ""
                echo -e "${RED}${_BOX_TOP}${NC}"
                echo -e "${RED}║  🐙 Branching: Abort Path (quality gate failed)           ║${NC}"
                echo -e "${RED}${_BOX_BOT}${NC}"
                log ERROR "Quality gate FAILED with ${success_rate}%. Aborting workflow."
                return 1
                ;;
        esac

        echo ""
        echo -e "${gate_color}${_BOX_TOP}${NC}"
        echo -e "${gate_color}║  Quality Gate: ${gate_status} (${success_rate}% of tangle results succeeded)${NC}"
        echo -e "${gate_color}${_BOX_BOT}${NC}"

        if [[ "$gate_status" == "FAILED" ]]; then
            log WARN "Quality gate failed. Review failures before proceeding to delivery."
            echo -e "${RED}Review results at: $validation_file${NC}"
        fi

        log INFO "Validation complete: $validation_file"
        echo ""

        # Exit loop - validation complete
        break
    done

    # Return non-zero if gate failed (but don't exit)
    [[ "$gate_status" != "FAILED" ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# RED TEAM - Adversarial Security Review
# Octopus squeezes prey to test for weaknesses
# ═══════════════════════════════════════════════════════════════════════════

squeeze_test() {
    local prompt="$1"
    local task_group
    task_group=$(date +%s)

    echo ""
    echo -e "${RED}${_BOX_TOP}${NC}"
    echo -e "${RED}║  🦑 SQUEEZE - Adversarial Security Review                 ║${NC}"
    echo -e "${RED}║  Blue Team defends, Red Team attacks                      ║${NC}"
    echo -e "${RED}${_BOX_BOT}${NC}"
    echo ""

    log INFO "Starting red team security review"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would squeeze test: $prompt"
        log INFO "[DRY-RUN] Phase 1: Blue Team implements secure solution (Codex)"
        log INFO "[DRY-RUN] Phase 2: Red Team finds vulnerabilities (Gemini)"
        log INFO "[DRY-RUN] Phase 3: Remediation of found issues (Codex)"
        log INFO "[DRY-RUN] Phase 4: Validation of fixes (Codex-Review)"
        return 0
    fi

    # Pre-flight validation
    preflight_check || return 1

    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    # Constraint to prevent agentic file exploration
    local no_explore_constraint="IMPORTANT: Do NOT read, explore, or modify any files. Do NOT run any shell commands. Just output your response as TEXT directly. This is a security review exercise, not a coding session."

    # ═══════════════════════════════════════════════════════════════════════
    # Phase 1: Blue Team Implementation
    # ═══════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${BLUE}[Phase 1/4] Blue Team: Implementing secure solution...${NC}"
    echo ""

    local blue_impl
    blue_impl=$(run_agent_sync "codex" "
$no_explore_constraint

You are BLUE TEAM (defender). Implement this with security as top priority:
$prompt

Focus on these security measures:
- Input validation and sanitization
- Authentication and authorization checks
- SQL injection prevention (parameterized queries)
- XSS prevention (output encoding)
- CSRF protection where applicable
- Secure defaults (fail closed, not open)
- Least privilege principle
- Proper error handling (no sensitive info leakage)

Output production-ready secure code with security comments." 180 "backend-architect" "squeeze") || {
        log WARN "Codex failed for blue team implementation, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Codex unavailable — falling back to Claude"
        blue_impl=$(run_agent_sync "claude-sonnet" "
$no_explore_constraint

You are BLUE TEAM (defender). Implement this with security as top priority:
$prompt

Focus on: input validation, auth checks, SQL injection prevention, XSS prevention, CSRF protection, secure defaults, least privilege, proper error handling.

Output production-ready secure code with security comments." 180 "backend-architect" "squeeze") || true
    }

    # ═══════════════════════════════════════════════════════════════════════
    # Phase 2: Red Team Attack
    # ═══════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${RED}[Phase 2/4] Red Team: Finding vulnerabilities...${NC}"
    echo ""

    local red_attack
    red_attack=$(run_agent_sync "gemini" "
$no_explore_constraint

You are RED TEAM (attacker/penetration tester). Find security vulnerabilities in this code:

$blue_impl

For EACH vulnerability found, document:
VULN: [Vulnerability type - e.g., SQL Injection, XSS, CSRF, etc.]
CWE: [CWE ID if applicable - e.g., CWE-89]
LOCATION: [Specific line/function affected]
ATTACK: [How to exploit this vulnerability]
PROOF: [Example malicious input or attack payload]
SEVERITY: [Critical|High|Medium|Low]

Find at least 5 issues. If the code is genuinely secure, explain specifically why each common vulnerability is mitigated.

Be thorough - check for:
- Injection flaws (SQL, NoSQL, OS command, LDAP)
- Broken authentication/session management
- Sensitive data exposure
- XML/XXE attacks
- Broken access control
- Security misconfiguration
- XSS (stored, reflected, DOM)
- Insecure deserialization
- Using components with known vulnerabilities
- Insufficient logging/monitoring" 180 "security-auditor" "squeeze") || {
        log WARN "Gemini failed for red team attack, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Gemini unavailable — falling back to Claude"
        red_attack=$(run_agent_sync "claude-sonnet" "
$no_explore_constraint

You are RED TEAM (attacker/penetration tester). Find security vulnerabilities in this code:

$blue_impl

For EACH vulnerability, document: VULN, CWE, LOCATION, ATTACK vector, PROOF (payload), SEVERITY.
Find at least 5 issues. Check for injection, auth, XSS, CSRF, access control, misconfig." 180 "security-auditor" "squeeze") || true
    }

    # ═══════════════════════════════════════════════════════════════════════
    # Phase 3: Remediation
    # ═══════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${YELLOW}[Phase 3/4] Remediation: Fixing vulnerabilities...${NC}"
    echo ""

    local remediation
    remediation=$(run_agent_sync "codex" "
$no_explore_constraint

Fix ALL vulnerabilities found by Red Team.

ORIGINAL CODE:
$blue_impl

VULNERABILITIES FOUND BY RED TEAM:
$red_attack

For EACH vulnerability:
1. Apply the fix
2. Add a comment explaining the fix: // FIXED: [vulnerability] - [what was changed]

Output the COMPLETE fixed code with all security improvements applied." 180 "implementer" "squeeze") || {
        log WARN "Codex failed for remediation, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Codex unavailable for remediation — falling back to Claude"
        remediation=$(run_agent_sync "claude-sonnet" "
$no_explore_constraint

Fix ALL vulnerabilities found by Red Team.

ORIGINAL CODE:
$blue_impl

VULNERABILITIES FOUND:
$red_attack

For EACH vulnerability: apply the fix and add a comment. Output the COMPLETE fixed code." 180 "implementer" "squeeze") || true
    }

    # ═══════════════════════════════════════════════════════════════════════
    # Phase 4: Validation
    # ═══════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${GREEN}[Phase 4/4] Validation: Verifying all fixes...${NC}"
    echo ""

    local validation
    validation=$(run_agent_sync "codex-review" "
$no_explore_constraint

Verify all vulnerabilities have been properly fixed.

ORIGINAL VULNERABILITIES FOUND:
$red_attack

REMEDIATED CODE:
$remediation

For each original vulnerability, verify:
- [ ] FIXED - vulnerability is properly mitigated
- [ ] STILL PRESENT - vulnerability still exists (explain why)

Create a checklist showing the status of each fix.

FINAL VERDICT:
- SECURE: All vulnerabilities fixed
- NEEDS MORE WORK: Some vulnerabilities remain (list them)

If any issues remain, provide specific guidance on how to fix them." 120 "code-reviewer" "squeeze") || {
        log WARN "Codex-review failed for validation, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Codex-review unavailable — falling back to Claude"
        validation=$(run_agent_sync "claude-sonnet" "
$no_explore_constraint

Verify all vulnerabilities have been properly fixed. VULNERABILITIES: $red_attack

REMEDIATED CODE: $remediation

Create a checklist: FIXED or STILL PRESENT for each. Give FINAL VERDICT: SECURE or NEEDS MORE WORK." 120 "code-reviewer" "squeeze") || true
    }

    # ═══════════════════════════════════════════════════════════════════════
    # Save results
    # ═══════════════════════════════════════════════════════════════════════
    local result_file="$RESULTS_DIR/squeeze-${task_group}.md"
    cat > "$result_file" << EOF
# Red Team Security Review

**Generated:** $(date)

---

## Task
$prompt

---

## Phase 1: Blue Team Implementation
$blue_impl

---

## Phase 2: Red Team Findings
$red_attack

---

## Phase 3: Remediation
$remediation

---

## Phase 4: Validation
$validation
EOF

    echo ""
    echo -e "${GREEN}${_BOX_TOP}${NC}"
    echo -e "${GREEN}║  ✓ Red Team exercise complete                            ║${NC}"
    echo -e "${GREEN}${_BOX_BOT}${NC}"
    echo ""
    echo -e "  Result: ${CYAN}$result_file${NC}"
    echo ""

    # v8.18.0: Record security finding
    write_structured_decision \
        "security-finding" \
        "squeeze_test" \
        "Red team exercise completed: ${prompt:0:80}" \
        "" \
        "high" \
        "Blue Team defense + Red Team attack + Remediation + Validation" \
        "" 2>/dev/null || true

    # v8.18.0: Earn skill from security exercise
    earn_skill \
        "security-${prompt:0:30}" \
        "squeeze_test" \
        "Red team security review pattern" \
        "When implementing security-sensitive features" \
        "Blue→Red→Remediate→Validate for: ${prompt:0:60}" 2>/dev/null || true

    # Record usage
    record_agent_call "squeeze" "multi-model" "$prompt" "squeeze" "red-team" "0"
}
