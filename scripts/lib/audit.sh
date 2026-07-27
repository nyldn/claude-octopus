#!/usr/bin/env bash
# audit.sh — Audit logging, review queue management
# Functions: audit_log, get_audit_trail, format_audit_entry,
#            queue_for_review, list_pending_reviews, approve_review,
#            reject_review, show_review
# Extracted from orchestrate.sh (v9.7.8)
# Source-safe: no main execution block.

# Write to audit log with structured format
audit_log() {
    local action="$1"
    local phase="$2"
    local decision="$3"
    local reason="${4:-}"
    local reviewer="${5:-${USER:-system}}"

    mkdir -p "$(dirname "$AUDIT_LOG")"

    local entry
    entry=$(cat << EOF
{"timestamp":"$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)","action":"$action","phase":"$phase","decision":"$decision","reason":"$reason","reviewer":"$reviewer","session":"${SESSION_ID:-unknown}"}
EOF
)
    echo "$entry" >> "$AUDIT_LOG"

    [[ "$VERBOSE" == "true" ]] && log DEBUG "Audit: $action $phase -> $decision" || true
}

# Get recent audit entries
get_audit_trail() {
    local count="${1:-20}"
    local filter="${2:-}"

    if [[ ! -f "$AUDIT_LOG" ]]; then
        echo -e "${YELLOW}No audit trail found.${NC}"
        echo "Audit entries are created when review decisions are made."
        echo "Use: $(basename "$0") review approve <id>"
        return 0
    fi

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Audit Trail - Recent Decisions                              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ -n "$filter" ]]; then
        tail -n "$count" "$AUDIT_LOG" | grep "$filter" | while read -r line; do
            format_audit_entry "$line"
        done
    else
        tail -n "$count" "$AUDIT_LOG" | while read -r line; do
            format_audit_entry "$line"
        done
    fi
}

format_audit_entry() {
    local line="$1"

    # Performance: Single-pass JSON extraction using bash regex (no subprocesses).
    # json_extract_multi uses Bash 3.x-safe printf -v assignments into each
    # dynamically named _<field> target, so declare those targets locally.
    local _timestamp="" _action="" _phase="" _decision="" _reviewer=""
    json_extract_multi "$line" timestamp action phase decision reviewer

    # Color-code decision
    local decision_color="$GREEN"
    [[ "$_decision" == "rejected" || "$_decision" == "failed" ]] && decision_color="$RED"
    [[ "$_decision" == "warning" ]] && decision_color="$YELLOW"

    echo -e "  ${CYAN}$_timestamp${NC} | $_action | $_phase | ${decision_color}$_decision${NC} | by $_reviewer"
}

# ═══════════════════════════════════════════════════════════════════════════════
# v4.4 FEATURE: REVIEW QUEUE SYSTEM
# Manage pending reviews and batch approvals
# ═══════════════════════════════════════════════════════════════════════════════

REVIEW_QUEUE="${WORKSPACE_DIR:-$HOME/.claude-octopus}/review-queue.json"

# Add item to review queue
queue_for_review() {
    local phase="$1"
    local status="$2"
    local output_file="$3"
    local prompt="$4"

    mkdir -p "$(dirname "$REVIEW_QUEUE")"

    local review_id
    review_id="review-$(date +%s)-$$"

    local entry
    entry=$(cat << EOF
{"id":"$review_id","phase":"$phase","status":"$status","output_file":"$output_file","prompt":"$(echo "$prompt" | tr '\n' ' ' | cut -c1-100)","created_at":"$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)","reviewed":false}
EOF
)

    # Append to queue file (one JSON object per line)
    echo "$entry" >> "$REVIEW_QUEUE"

    log INFO "Queued for review: $review_id ($phase)"
    echo "$review_id"
}

# List pending reviews
list_pending_reviews() {
    if [[ ! -f "$REVIEW_QUEUE" ]]; then
        echo -e "${YELLOW}No pending reviews.${NC}"
        return 0
    fi

    local pending
    pending=$(grep '"reviewed":false' "$REVIEW_QUEUE" 2>/dev/null || true)

    if [[ -z "$pending" ]]; then
        echo -e "${GREEN}No pending reviews.${NC}"
        return 0
    fi

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Pending Reviews                                              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local count=0
    echo "$pending" | while read -r line; do
        ((count++)) || true
        # Performance: Single-pass JSON extraction (no subprocesses).
        # Declare the printf -v targets locally so dynamically named assignments
        # do not create globals that persist across iterations.
        local _id="" _phase="" _status="" _output_file="" _created_at=""
        json_extract_multi "$line" id phase status output_file created_at

        local status_color="$GREEN"
        [[ "$_status" == "failed" ]] && status_color="$RED"
        [[ "$_status" == "warning" ]] && status_color="$YELLOW"

        echo -e "  ${YELLOW}$_id${NC}"
        echo -e "    Phase:   $_phase"
        echo -e "    Status:  ${status_color}$_status${NC}"
        echo -e "    Output:  $_output_file"
        echo -e "    Created: $_created_at"
        echo ""
    done

    echo -e "${CYAN}Commands:${NC}"
    echo -e "  orchestrate.sh review approve <id>    - Approve and continue"
    echo -e "  orchestrate.sh review reject <id>     - Reject with reason"
    echo -e "  orchestrate.sh review show <id>       - View output file"
    echo ""
}

# [EXTRACTED to lib/review.sh]
# Functions: parse_review_md, build_review_fleet, print_provider_report,
#            review_run, post_inline_comments, render_terminal_report,
#            render_review_summary

# Approve a review
approve_review() {
    local review_id="$1"
    local reason="${2:-Approved}"

    # Sanitize review ID to prevent injection
    review_id=$(sanitize_review_id "$review_id") || {
        echo -e "${RED}Invalid review ID format${NC}"
        return 1
    }

    if [[ ! -f "$REVIEW_QUEUE" ]]; then
        echo -e "${RED}No review queue found.${NC}"
        return 1
    fi

    # Check if review exists
    if ! grep -q "\"id\":\"$review_id\"" "$REVIEW_QUEUE"; then
        echo -e "${RED}Review not found: $review_id${NC}"
        return 1
    fi

    # Mark as reviewed using secure temp file
    local temp_file
    temp_file=$(secure_tempfile "review-approve")
    sed "s/\"id\":\"$review_id\",\\(.*\\)\"reviewed\":false/\"id\":\"$review_id\",\\1\"reviewed\":true,\"decision\":\"approved\",\"reviewed_at\":\"$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)\"/" "$REVIEW_QUEUE" > "$temp_file"
    mv "$temp_file" "$REVIEW_QUEUE"

    # Get phase for audit (fast extraction)
    local review_line phase
    review_line=$(grep "\"id\":\"$review_id\"" "$REVIEW_QUEUE")
    json_extract "$review_line" "phase" && phase="$REPLY" || phase=""

    # Log to audit trail
    audit_log "review" "$phase" "approved" "$reason" "${USER:-unknown}"

    echo -e "${GREEN}✓ Approved: $review_id${NC}"
    echo -e "  Reason: $reason"
}

# Reject a review
reject_review() {
    local review_id="$1"
    local reason="${2:-Rejected}"

    # Sanitize review ID to prevent injection
    review_id=$(sanitize_review_id "$review_id") || {
        echo -e "${RED}Invalid review ID format${NC}"
        return 1
    }

    if [[ ! -f "$REVIEW_QUEUE" ]]; then
        echo -e "${RED}No review queue found.${NC}"
        return 1
    fi

    # Check if review exists
    if ! grep -q "\"id\":\"$review_id\"" "$REVIEW_QUEUE"; then
        echo -e "${RED}Review not found: $review_id${NC}"
        return 1
    fi

    # Mark as reviewed using secure temp file
    local temp_file
    temp_file=$(secure_tempfile "review-reject")
    sed "s/\"id\":\"$review_id\",\\(.*\\)\"reviewed\":false/\"id\":\"$review_id\",\\1\"reviewed\":true,\"decision\":\"rejected\",\"reviewed_at\":\"$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)\"/" "$REVIEW_QUEUE" > "$temp_file"
    mv "$temp_file" "$REVIEW_QUEUE"

    # Get phase for audit (fast extraction)
    local review_line phase
    review_line=$(grep "\"id\":\"$review_id\"" "$REVIEW_QUEUE")
    json_extract "$review_line" "phase" && phase="$REPLY" || phase=""

    # Log to audit trail
    audit_log "review" "$phase" "rejected" "$reason" "${USER:-unknown}"

    echo -e "${RED}✗ Rejected: $review_id${NC}"
    echo -e "  Reason: $reason"
}

# Show review output
show_review() {
    local review_id="$1"

    if [[ ! -f "$REVIEW_QUEUE" ]]; then
        echo -e "${RED}No review queue found.${NC}"
        return 1
    fi

    local review_line output_file validated_file
    review_line=$(grep "\"id\":\"$review_id\"" "$REVIEW_QUEUE")
    json_extract "$review_line" "output_file" && output_file="$REPLY" || output_file=""

    if [[ -z "$output_file" ]]; then
        echo -e "${RED}Review not found: $review_id${NC}"
        return 1
    fi

    # Validate path to prevent traversal attacks
    validated_file=$(validate_output_file "$output_file") || {
        echo -e "${RED}Invalid or inaccessible output file: $output_file${NC}"
        return 1
    }

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Review: $review_id${NC}"
    echo -e "${CYAN}File: $validated_file${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    cat "$validated_file"
}
