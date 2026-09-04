#!/usr/bin/env bash
# Shared result-file framing helpers.

# Length-prefix the exact dispatched prompt so prompt content can contain any
# Markdown heading, including the legacy `# Started:` delimiter.
write_agent_result_prompt() {
    local result_file="$1"
    local prompt="$2"
    local prompt_bytes
    prompt_bytes=$(LC_ALL=C printf '%s' "$prompt" | wc -c | tr -d '[:space:]') || return 1
    [[ "$prompt_bytes" =~ ^[0-9]+$ ]] || return 1
    printf '# Prompt-Format: octopus-length-v1\n' >> "$result_file" || return 1
    printf '# Prompt-Bytes: %s\n' "$prompt_bytes" >> "$result_file" || return 1
    printf '%s\n' "$prompt" >> "$result_file"
}
