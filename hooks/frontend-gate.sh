#!/bin/bash
# Claude Octopus Frontend Gate Hook (v8.6.0, enhanced v8.8.0)
# Domain-specific quality gate for frontend-developer persona
# Validates: Accessibility (ARIA/semantic), responsive design (breakpoint/viewport)
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}
# v8.8: Writes human-readable stderr on block (displayed by Claude Code v2.1.41+)
set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Read tool output from stdin
output=$(cat 2>/dev/null || true)

# If no output or very short, continue (likely non-analysis command)
if [[ ${#output} -lt 100 ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

issues=()

# Check 1: Accessibility considerations
a11y_found=false
for pattern in "aria" "semantic" "accessibility" "a11y" "screen.reader" "alt.text" \
               "role=" "tabindex" "focus" "keyboard" "wcag" "contrast" "label"; do
    if echo "$output" | grep -qiE "$pattern"; then
        a11y_found=true
        break
    fi
done

if [[ "$a11y_found" != "true" ]]; then
    issues+=("Missing accessibility considerations (ARIA, semantic HTML, screen reader support)")
fi

# Check 2: Responsive design awareness
responsive_found=false
for pattern in "responsive" "breakpoint" "viewport" "mobile" "tablet" "desktop" \
               "media.query" "@media" "flex" "grid" "container.query" "rem" "em" \
               "min-width" "max-width" "clamp("; do
    if echo "$output" | grep -qiE "$pattern"; then
        responsive_found=true
        break
    fi
done

if [[ "$responsive_found" != "true" ]]; then
    issues+=("Missing responsive design considerations (breakpoints, viewport, mobile-first)")
fi

# Check 3: Component structure or React patterns
component_found=false
for pattern in "component" "props" "state" "hook" "useEffect" "useState" "render" \
               "jsx" "tsx" "className" "style" "css" "tailwind" "module"; do
    if echo "$output" | grep -qiE "$pattern"; then
        component_found=true
        break
    fi
done

if [[ "$component_found" != "true" ]]; then
    issues+=("Missing component structure references (props, state, hooks, styling)")
fi

# Decision
if [[ ${#issues[@]} -gt 1 ]]; then
    reason=$(printf '%s; ' "${issues[@]}")
    reason="${reason%; }"
    # v8.8: Write stderr so Claude Code v2.1.41+ displays blocking reason to user
    echo "🎨 Frontend gate BLOCKED: ${reason}" >&2
    echo "   Fix: Address accessibility (ARIA/semantic HTML), responsive design (breakpoints), and component structure." >&2
    echo "{\"decision\": \"block\", \"reason\": \"Frontend review incomplete: ${reason}\"}"
elif [[ ${#issues[@]} -eq 1 ]]; then
    echo "🎨 Frontend gate warning: ${issues[0]}" >&2
    echo "{\"decision\": \"continue\", \"reason\": \"Warning: ${issues[0]}\"}"
else
    echo '{"decision": "continue"}'
fi

exit 0
