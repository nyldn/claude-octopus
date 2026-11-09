#!/usr/bin/env bash
# lib/similarity.sh — Convergence detection and text similarity functions
# Extracted from orchestrate.sh (Wave 1). Pure computation, no global mutations.

[[ -n "${_OCTOPUS_SIMILARITY_LOADED:-}" ]] && return 0
_OCTOPUS_SIMILARITY_LOADED=true

# Extract markdown headings from a file (lowercased, sorted, deduped)
extract_headings() {
    local file="$1"
    grep '^#' "$file" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u || true
}

# Jaccard similarity using loops (bash 3.2 compatible - no comm/paste)
jaccard_similarity() {
    local set_a="$1"
    local set_b="$2"

    [[ -z "$set_a" || -z "$set_b" ]] && echo "0" && return

    local -a arr_a arr_b
    local intersection=0
    local union_count=0

    # Read sets into arrays
    while IFS= read -r line; do arr_a+=("$line"); done <<< "$set_a"
    while IFS= read -r line; do arr_b+=("$line"); done <<< "$set_b"

    # Count intersection
    for a in "${arr_a[@]}"; do
        for b in "${arr_b[@]}"; do
            if [[ "$a" == "$b" ]]; then
                intersection=$((intersection + 1))
                break
            fi
        done
    done

    # Union = |A| + |B| - |intersection|
    union_count=$(( ${#arr_a[@]} + ${#arr_b[@]} - intersection ))
    [[ $union_count -eq 0 ]] && echo "0" && return

    awk -v i="$intersection" -v u="$union_count" 'BEGIN { printf "%.2f", i / u }'
}

# Check if parallel agent results are converging
# Uses heading extraction + jaccard similarity
check_convergence() {
    local signature="${OCTOPUS_CONVERGENCE_THRESHOLD:-0.8}" f part

    [[ "${OCTOPUS_CONVERGENCE_ENABLED:-false}" != "true" ]] && return 1

    local files=()
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        files+=("$f")
        part=$(cksum < "$f" 2>/dev/null) || return 1
        signature+="${#f}:$f:$part;"
    done

    [[ ${#files[@]} -lt 2 ]] && return 1

    if [[ "${_OCTO_CONVERGENCE_SIGNATURE:-}" == "$signature" ]]; then
        return "${_OCTO_CONVERGENCE_RC:-1}"
    fi
    _OCTO_CONVERGENCE_SIGNATURE="$signature"
    _OCTO_CONVERGENCE_RC=1
    local headings=()
    for f in "${files[@]}"; do
        headings+=("$(extract_headings "$f")")
    done
    local converged=0
    local i j
    for (( i=0; i < ${#files[@]}; i++ )); do
        for (( j=i+1; j < ${#files[@]}; j++ )); do
            local headings_a headings_b sim
            headings_a="${headings[$i]}"
            headings_b="${headings[$j]}"
            sim=$(jaccard_similarity "$headings_a" "$headings_b")
            if awk -v s="$sim" -v t="${OCTOPUS_CONVERGENCE_THRESHOLD:-0.8}" 'BEGIN { exit !(s >= t) }'; then
                converged=$((converged + 1))
            fi
        done
    done

    if [[ $converged -ge 1 ]]; then
        _OCTO_CONVERGENCE_RC=0
        return 0
    fi
    return 1
}

# Generate word bigrams from text (lowercased, punctuation stripped)
generate_bigrams() {
    local text="$1"
    local words
    words=$(echo "$text" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ' | tr -s ' ')

    local -a word_arr
    read -ra word_arr <<< "$words"

    local i
    for (( i=0; i < ${#word_arr[@]} - 1; i++ )); do
        echo "${word_arr[$i]} ${word_arr[$((i+1))]}"
    done
}

# Bigram-based text similarity (uses jaccard on bigram sets)
bigram_similarity() {
    local text_a="$1"
    local text_b="$2"

    local bigrams_a bigrams_b
    bigrams_a=$(generate_bigrams "$text_a")
    bigrams_b=$(generate_bigrams "$text_b")

    jaccard_similarity "$bigrams_a" "$bigrams_b"
}
