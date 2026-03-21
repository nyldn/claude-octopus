#!/usr/bin/env bash
# Progressive synthesis monitoring — extracted from orchestrate.sh
# v7.19.0 P2.4: Progressive synthesis - start synthesis as results become available

progressive_synthesis_monitor() {
    local task_group="$1"
    local prompt="$2"
    local min_results="${3:-2}"  # Start synthesis with minimum 2 results
    local synthesis_file="${RESULTS_DIR}/probe-synthesis-${task_group}.md"
    local partial_synthesis="${RESULTS_DIR}/.partial-synthesis-${task_group}.md"

    log "DEBUG" "Progressive synthesis monitor started (min: $min_results results)"

    local last_count=0
    local synthesis_started=false

    while true; do
        # Count available results with meaningful content
        local result_count=0
        for result in "$RESULTS_DIR"/*-probe-${task_group}-*.md; do
            [[ ! -f "$result" ]] && continue
            local file_size
            file_size=$(wc -c < "$result" 2>/dev/null || echo "0")
            [[ $file_size -gt 500 ]] && ((result_count++)) || true
        done

        # If we have minimum results and haven't started synthesis yet
        if [[ $result_count -ge $min_results && ! $synthesis_started ]]; then
            log "INFO" "Progressive synthesis: $result_count results available, starting early synthesis"

            # Run partial synthesis in background
            (
                synthesize_probe_results_partial "$task_group" "$prompt" "$result_count" > "$partial_synthesis" 2>&1
            ) &

            synthesis_started=true
        fi

        # Update partial synthesis if more results arrived
        if [[ $synthesis_started && $result_count -gt $last_count ]]; then
            log "DEBUG" "Progressive synthesis: updating ($result_count results)"
            # Could update here, but for simplicity we'll just run once
        fi

        last_count=$result_count

        # Exit if synthesis file exists (main synthesis completed)
        [[ -f "$synthesis_file" ]] && break

        sleep 2
    done

    # Cleanup partial synthesis file
    rm -f "$partial_synthesis"
    log "DEBUG" "Progressive synthesis monitor stopped"
}

# Partial synthesis function (lighter version for progressive updates)
synthesize_probe_results_partial() {
    local task_group="$1"
    local original_prompt="$2"
    local expected_count="$3"

    # Quick synthesis with available results
    local results=""
    local result_count=0
    for result in "$RESULTS_DIR"/*-probe-${task_group}-*.md; do
        [[ ! -f "$result" ]] || continue
        local file_size
        file_size=$(wc -c < "$result" 2>/dev/null || echo "0")
        if [[ $file_size -gt 500 ]]; then
            results+="$(<"$result")\n\n---\n\n"
            ((result_count++)) || true
        fi
    done

    echo "# Partial Synthesis (${result_count}/${expected_count} results)"
    echo ""
    echo "Processing early results while remaining agents complete..."
    echo ""
    echo "## Available Insights"
    echo "$results" | head -500
    echo ""
    echo "_Final synthesis will be available when all agents complete_"
}
