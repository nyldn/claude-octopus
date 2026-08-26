#!/usr/bin/env bash
# semantic-cache.sh — Semantic caching, result deduplication, cache cleanup
#
# Functions:
#   check_cache_semantic    — Bigram-based fuzzy cache lookup
#   save_to_cache_semantic  — Save cache entry with bigrams for semantic matching
#   deduplicate_results     — Heading-based duplicate detection across result files
#   get_cache_key           — SHA-256 cache key from prompt text
#   check_cache             — Check if cached result exists and is within TTL
#   get_cached_result       — Read cached result file
#   save_to_cache           — Write result file to cache with timestamp
#   cleanup_cache           — Remove expired cache entries beyond TTL
#   cleanup_old_results     — Age-based cleanup of per-agent result files
#
# Extracted from orchestrate.sh (v9.7.8)
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE: Semantic probe cache (v8.7.0)
# Bigram-based fuzzy matching for cache lookups
# Config: OCTOPUS_SEMANTIC_CACHE=false, OCTOPUS_CACHE_SIMILARITY_THRESHOLD=0.7
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_SEMANTIC_CACHE="${OCTOPUS_SEMANTIC_CACHE:-false}"
OCTOPUS_CACHE_SIMILARITY_THRESHOLD="${OCTOPUS_CACHE_SIMILARITY_THRESHOLD:-0.7}"
CACHE_TTL="${CACHE_TTL:-3600}"

# session.sh normally owns this helper. Keep semantic-cache.sh independently
# sourceable for focused tests and third-party integrations.
if ! type octo_probe_cache_dir >/dev/null 2>&1; then
    octo_probe_cache_dir() {
        local workspace="${WORKSPACE_DIR:-}"
        if [[ -z "$workspace" ]] && type resolve_octopus_workspace >/dev/null 2>&1; then
            workspace="$(resolve_octopus_workspace 2>/dev/null || true)"
        fi
        [[ -n "$workspace" ]] || workspace="${HOME:-${TMPDIR:-/tmp}}/.claude-octopus"
        printf '%s/.cache/probe-results\n' "${workspace%/}"
    }
fi

check_cache_semantic() {
    local prompt="$1"
    local cache_dir
    cache_dir="$(octo_probe_cache_dir)" || return 1

    [[ "$OCTOPUS_SEMANTIC_CACHE" != "true" ]] && return 1
    [[ ! -d "$cache_dir" ]] && return 1

    # Try exact match first
    local cache_key
    cache_key=$(echo "$prompt" | shasum -a 256 | awk '{print $1}')
    if check_cache "$cache_key" 2>/dev/null; then
        echo "$cache_key"
        return 0
    fi

    # Scan bigram files for fuzzy matches
    local best_key=""
    local best_sim="0"
    for bigram_file in "${cache_dir}"/*.bigrams; do
        [[ ! -f "$bigram_file" ]] && continue

        local cached_prompt
        cached_prompt=$(cat "$bigram_file" 2>/dev/null || true)
        [[ -z "$cached_prompt" ]] && continue

        local sim
        sim=$(bigram_similarity "$prompt" "$cached_prompt")

        if awk -v s="$sim" -v t="$OCTOPUS_CACHE_SIMILARITY_THRESHOLD" -v b="$best_sim" \
           'BEGIN { exit !(s >= t && s > b) }'; then
            best_sim="$sim"
            best_key="${bigram_file%.bigrams}"
            best_key="${best_key##*/}"
        fi
    done

    if [[ -n "$best_key" ]] && check_cache "$best_key" >/dev/null 2>&1; then
        log "DEBUG" "Semantic cache hit: similarity=$best_sim for key=$best_key"
        echo "$best_key"
        return 0
    fi

    return 1
}

save_to_cache_semantic() {
    local cache_key="$1"
    local result_file="$2"
    local prompt="$3"

    # Save regular cache entry
    save_to_cache "$cache_key" "$result_file" || return 1

    # Save bigrams file for semantic matching
    if [[ "$OCTOPUS_SEMANTIC_CACHE" == "true" ]]; then
        local cache_dir bigram_file bigram_tmp
        cache_dir="$(octo_probe_cache_dir)" || return 1
        bigram_file="${cache_dir}/${cache_key}.bigrams"
        bigram_tmp="$(mktemp "${bigram_file}.tmp.XXXXXX")" || return 1
        if ! printf '%s\n' "$prompt" > "$bigram_tmp" || ! mv "$bigram_tmp" "$bigram_file"; then
            rm -f "$bigram_tmp"
            return 1
        fi
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE: Result deduplication and context budget (v8.7.0)
# Dedup: Heading-based duplicate detection (log-only in v8.7.0)
# Context budget: Truncate prompts to token limit before sending to agents
# Config: OCTOPUS_DEDUP_ENABLED=false, OCTOPUS_CONTEXT_BUDGET=12000
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_DEDUP_ENABLED="${OCTOPUS_DEDUP_ENABLED:-false}"
OCTOPUS_CONTEXT_BUDGET="${OCTOPUS_CONTEXT_BUDGET:-12000}"

deduplicate_results() {
    local files=("$@")

    [[ "$OCTOPUS_DEDUP_ENABLED" != "true" ]] && return 0
    [[ ${#files[@]} -lt 2 ]] && return 0

    local i j
    for (( i=0; i < ${#files[@]}; i++ )); do
        [[ ! -f "${files[$i]}" ]] && continue
        for (( j=i+1; j < ${#files[@]}; j++ )); do
            [[ ! -f "${files[$j]}" ]] && continue
            local headings_a headings_b sim
            headings_a=$(extract_headings "${files[$i]}")
            headings_b=$(extract_headings "${files[$j]}")
            sim=$(jaccard_similarity "$headings_a" "$headings_b")
            if awk -v s="$sim" 'BEGIN { exit !(s >= 0.9) }'; then
                log "INFO" "DEDUP: High similarity ($sim) between ${files[$i]##*/} and ${files[$j]##*/} (log-only in v8.7.0)"
            fi
        done
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# CACHE: Core cache operations (v8.0.0)
# Key generation, freshness checks, storage, and cleanup
# Config: runtime octo_probe_cache_dir(), CACHE_TTL
# ═══════════════════════════════════════════════════════════════════════════════

get_cache_key() {
    local prompt="$1"
    echo -n "$prompt" | shasum -a 256 | cut -d' ' -f1
}

# Check if cached result exists and is fresh
check_cache() {
    local cache_key="$1"
    local cache_dir cache_file cache_meta
    cache_dir="$(octo_probe_cache_dir)" || return 1
    cache_file="${cache_dir}/${cache_key}.md"
    cache_meta="${cache_dir}/${cache_key}.meta"

    # Check if cache files exist
    [[ ! -f "$cache_file" ]] && return 1
    [[ ! -f "$cache_meta" ]] && return 1

    # Check if cache is still valid (within TTL)
    local cache_time
    cache_time=$(cat "$cache_meta" 2>/dev/null || echo "0")
    local current_time age
    current_time=$(date +%s)
    age=$((current_time - cache_time))

    if [[ $age -lt $CACHE_TTL ]]; then
        log "INFO" "Cache hit! Age: ${age}s (TTL: ${CACHE_TTL}s)"
        return 0
    else
        log "DEBUG" "Cache expired. Age: ${age}s > TTL: ${CACHE_TTL}s"
        return 1
    fi
}

# Get cached result
get_cached_result() {
    local cache_key="$1"
    local cache_dir cache_file
    cache_dir="$(octo_probe_cache_dir)" || return 1
    cache_file="${cache_dir}/${cache_key}.md"
    cat "$cache_file"
}

# Save result to cache
save_to_cache() {
    local cache_key="$1"
    local result_file="$2"
    local cache_dir cache_file cache_meta cache_tmp meta_tmp
    cache_dir="$(octo_probe_cache_dir)" || return 1
    cache_file="${cache_dir}/${cache_key}.md"
    cache_meta="${cache_dir}/${cache_key}.meta"

    [[ -f "$result_file" ]] || return 1
    mkdir -p "$cache_dir" 2>/dev/null || return 1
    cache_tmp="$(mktemp "${cache_file}.tmp.XXXXXX")" || return 1
    meta_tmp="$(mktemp "${cache_meta}.tmp.XXXXXX")" || {
        rm -f "$cache_tmp"
        return 1
    }

    if ! cp "$result_file" "$cache_tmp" 2>/dev/null ||
       ! date +%s > "$meta_tmp" 2>/dev/null; then
        rm -f "$cache_tmp" "$meta_tmp"
        return 1
    fi
    if ! mv "$cache_tmp" "$cache_file" 2>/dev/null; then
        rm -f "$cache_tmp" "$meta_tmp"
        return 1
    fi
    if ! mv "$meta_tmp" "$cache_meta" 2>/dev/null; then
        rm -f "$cache_file" "$meta_tmp"
        return 1
    fi

    log "DEBUG" "Saved to cache: $cache_key"
    return 0
}

# Clean up expired cache entries
cleanup_cache() {
    local cache_dir
    cache_dir="$(octo_probe_cache_dir)" || return 0
    [[ ! -d "$cache_dir" ]] && return 0

    local current_time
    current_time=$(date +%s)
    local cleaned=0

    for meta_file in "$cache_dir"/*.meta; do
        [[ ! -f "$meta_file" ]] && continue

        local cache_time
        cache_time=$(cat "$meta_file" 2>/dev/null || echo "0")
        local age=$((current_time - cache_time))

        if [[ $age -gt $CACHE_TTL ]]; then
            local base="${meta_file%.meta}"
            rm -f "$base.md" "$base.bigrams" "$meta_file"
            ((cleaned++)) || true
        fi
    done

    [[ $cleaned -gt 0 ]] && log "INFO" "Cleaned $cleaned expired cache entries" || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# RESULT FILE CLEANUP (v8.49.0)
# Age-based cleanup of per-agent result files after synthesis.
# Keeps synthesis files; removes ephemeral per-agent outputs older than retention.
# Config: OCTOPUS_RESULT_RETENTION_HOURS (default: 24)
# ═══════════════════════════════════════════════════════════════════════════════

cleanup_old_results() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    [[ ! -d "$RESULTS_DIR" ]] && return 0

    local retention_hours="${OCTOPUS_RESULT_RETENTION_HOURS:-24}"
    local retention_mins=$((retention_hours * 60))
    local cleaned=0

    # Clean per-agent result files (not synthesis files)
    while IFS= read -r -d '' file; do
        local basename
        basename=$(basename "$file")
        # Keep synthesis, consensus, validation, delivery files
        case "$basename" in
            probe-synthesis-*|grasp-consensus-*|tangle-validation-*|delivery-*) continue ;;
            .session-id|.created-at) continue ;;
        esac
        rm -f "$file"
        ((cleaned++)) || true
    done < <(find "$RESULTS_DIR" -name "*.md" -mmin "+$retention_mins" -print0 2>/dev/null)

    # Clean marker files
    find "$RESULTS_DIR" -name "*.marker" -mmin "+$retention_mins" -delete 2>/dev/null || true

    [[ $cleaned -gt 0 ]] && log "INFO" "Cleaned $cleaned expired result files (retention: ${retention_hours}h)" || true
}
