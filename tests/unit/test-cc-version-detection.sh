#!/usr/bin/env bash
# Tests for Claude Code version detection and SUPPORTS_* feature flags
# Consolidated from: test-claude-2114-features.sh, test-cc-v2174-sync.sh,
#                     test-cc-v2176-sync.sh, test-cc-v2177-sync.sh
#
# Validates: flag declarations, detection blocks, wiring, doctor checks,
#            logging, skill frontmatter, and cumulative flag/block counts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Claude Code version detection and SUPPORTS_* feature flags"

ORCH_MAIN="$PROJECT_ROOT/scripts/orchestrate.sh"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ORCH=$(mktemp)
trap 'rm -f "$ORCH"' EXIT
cat "$ORCH_MAIN" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ORCH" 2>/dev/null

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ╔══════════════════════════════════════════════════════════════════════╗
# ║  1. Minimum version requirement                                     ║
# ╚══════════════════════════════════════════════════════════════════════╝
echo "=== 1. Minimum Version ==="

if grep -q 'min_version="2.1.14"' "$ORCH_MAIN"; then
    pass "orchestrate.sh has min_version=2.1.14"
else
    fail "min_version" "expected 2.1.14 in orchestrate.sh"
fi

# ╔══════════════════════════════════════════════════════════════════════╗
# ║  2. Flag declarations                                               ║
# ╚══════════════════════════════════════════════════════════════════════╝
echo ""
echo "=== 2. Flag Declarations ==="

# v2.1.72 flags
for flag in SUPPORTS_PARALLEL_TOOL_RESILIENCE; do
    if grep -c "${flag}=false" "$ORCH" >/dev/null 2>&1; then
        pass "Declaration: $flag"
    else
        fail "Declaration: $flag" "missing ${flag}=false"
    fi
done

# v2.1.74 flags
for flag in SUPPORTS_AUTO_MEMORY_DIR SUPPORTS_FULL_MODEL_IDS \
            SUPPORTS_CONTEXT_SUGGESTIONS SUPPORTS_PLUGIN_DIR_OVERRIDE; do
    if grep -c "${flag}=false" "$ORCH" >/dev/null 2>&1; then
        pass "Declaration: $flag"
    else
        fail "Declaration: $flag" "missing ${flag}=false"
    fi
done

# v2.1.76 flags
for flag in SUPPORTS_MCP_ELICITATION SUPPORTS_WORKTREE_SPARSE_PATHS \
            SUPPORTS_EFFORT_COMMAND SUPPORTS_BG_PARTIAL_RESULTS; do
    if grep -c "${flag}=false" "$ORCH" >/dev/null 2>&1; then
        pass "Declaration: $flag"
    else
        fail "Declaration: $flag" "missing ${flag}=false"
    fi
done

# v2.1.77 flags
for flag in SUPPORTS_ALLOW_READ_SANDBOX SUPPORTS_COPY_INDEX \
            SUPPORTS_COMPOUND_BASH_PERMISSION_FIX SUPPORTS_RESUME_TRUNCATION_FIX \
            SUPPORTS_PRETOOLUSE_DENY_PRIORITY SUPPORTS_SENDMESSAGE_AUTO_RESUME \
            SUPPORTS_AGENT_NO_RESUME_PARAM SUPPORTS_PLUGIN_VALIDATE_FRONTMATTER \
            SUPPORTS_BRANCH_COMMAND SUPPORTS_BG_BASH_5GB_KILL; do
    if grep -c "${flag}=false" "$ORCH" >/dev/null 2>&1; then
        pass "Declaration: $flag"
    else
        fail "Declaration: $flag" "missing ${flag}=false"
    fi
done

# ╔══════════════════════════════════════════════════════════════════════╗
# ║  3. Detection blocks                                                ║
# ╚══════════════════════════════════════════════════════════════════════╝
echo ""
echo "=== 3. Detection Blocks ==="

# --- v2.1.72 block ---
v2172_block=$(grep -A20 'version_compare.*2\.1\.72' "$ORCH" | head -20)

for flag in SUPPORTS_PARALLEL_TOOL_RESILIENCE; do
    if echo "$v2172_block" | grep -c "$flag=true" >/dev/null 2>&1; then
        pass "v2.1.72 block sets: $flag"
    else
        fail "v2.1.72 block sets: $flag" "not found in v2.1.72 detection block"
    fi
done

# --- v2.1.74 block ---
if grep -c 'version_compare.*2\.1\.74' "$ORCH" >/dev/null 2>&1; then
    pass "v2.1.74 detection block exists"
else
    fail "v2.1.74 detection block exists" "no version_compare for 2.1.74"
fi

v2174_block=$(grep -A15 'version_compare.*2\.1\.74' "$ORCH" | head -15)

for flag in SUPPORTS_AUTO_MEMORY_DIR SUPPORTS_FULL_MODEL_IDS \
            SUPPORTS_CONTEXT_SUGGESTIONS SUPPORTS_PLUGIN_DIR_OVERRIDE; do
    if echo "$v2174_block" | grep -c "$flag=true" >/dev/null 2>&1; then
        pass "v2.1.74 block sets: $flag"
    else
        fail "v2.1.74 block sets: $flag" "not found in v2.1.74 detection block"
    fi
done

# --- No v2.1.75 block (no plugin-relevant changes) ---
if grep -c 'version_compare.*2\.1\.75' "$ORCH" >/dev/null 2>&1; then
    fail "No v2.1.75 block" "unexpected v2.1.75 detection block found"
else
    pass "No v2.1.75 block (correct — no plugin-relevant changes)"
fi

# --- v2.1.76 block ---
if grep -c 'version_compare.*2\.1\.76' "$ORCH" >/dev/null 2>&1; then
    pass "v2.1.76 detection block exists"
else
    fail "v2.1.76 detection block exists" "no version_compare for 2.1.76"
fi

# Use providers.sh specifically for detection block (doctor.sh also references v2.1.76)
v2176_block=$(grep -A15 'version_compare.*2\.1\.76' "$PROJECT_ROOT/scripts/lib/providers.sh" | head -15)

for flag in SUPPORTS_MCP_ELICITATION SUPPORTS_WORKTREE_SPARSE_PATHS \
            SUPPORTS_EFFORT_COMMAND SUPPORTS_BG_PARTIAL_RESULTS; do
    if echo "$v2176_block" | grep -c "$flag=true" >/dev/null 2>&1; then
        pass "v2.1.76 block sets: $flag"
    else
        fail "v2.1.76 block sets: $flag" "not found in v2.1.76 detection block"
    fi
done

# --- v2.1.77 block ---
if grep -c 'version_compare.*2\.1\.77' "$ORCH" >/dev/null 2>&1; then
    pass "v2.1.77 detection block exists"
else
    fail "v2.1.77 detection block exists" "no version_compare for 2.1.77"
fi

v2177_block=$(grep -A20 'version_compare.*2\.1\.77' "$PROJECT_ROOT/scripts/lib/providers.sh" | head -20)

for flag in SUPPORTS_ALLOW_READ_SANDBOX SUPPORTS_COPY_INDEX \
            SUPPORTS_COMPOUND_BASH_PERMISSION_FIX SUPPORTS_RESUME_TRUNCATION_FIX \
            SUPPORTS_PRETOOLUSE_DENY_PRIORITY SUPPORTS_SENDMESSAGE_AUTO_RESUME \
            SUPPORTS_AGENT_NO_RESUME_PARAM SUPPORTS_PLUGIN_VALIDATE_FRONTMATTER \
            SUPPORTS_BRANCH_COMMAND SUPPORTS_BG_BASH_5GB_KILL; do
    if echo "$v2177_block" | grep -c "$flag=true" >/dev/null 2>&1; then
        pass "v2.1.77 block sets: $flag"
    else
        fail "v2.1.77 block sets: $flag" "not found in v2.1.77 detection block"
    fi
done

# ╔══════════════════════════════════════════════════════════════════════╗
# ║  4. Logging lines                                                   ║
# ╚══════════════════════════════════════════════════════════════════════╝
echo ""
echo "=== 4. Logging ==="

# v2.1.74 labels
for label in "Parallel Tool Resilience" "Auto Memory Dir" \
             "Full Model IDs" "Context Suggestions" "Plugin Dir Override"; do
    if grep -c "$label" "$ORCH" >/dev/null 2>&1; then
        pass "Logged: $label"
    else
        fail "Logged: $label" "not found in detection logging"
    fi
done

# v2.1.76 labels
for label in "MCP Elicitation" "Worktree Sparse Paths" \
             "Effort Command" "BG Partial Results"; do
    if grep -c "$label" "$ORCH" >/dev/null 2>&1; then
        pass "Logged: $label"
    else
        fail "Logged: $label" "not found in detection logging"
    fi
done

# v2.1.77 labels
for label in "Allow Read Sandbox" "SendMessage Auto Resume" "Agent No Resume Param" \
             "Plugin Validate Frontmatter" "Branch Command" "BG Bash 5GB Kill"; do
    if grep -c "$label" "$ORCH" >/dev/null 2>&1; then
        pass "Logged: $label"
    else
        fail "Logged: $label" "not found in detection logging"
    fi
done

# ╔══════════════════════════════════════════════════════════════════════╗
# ║  5. Wiring — spawn_agent, doctor, etc.                              ║
# ╚══════════════════════════════════════════════════════════════════════╝
echo ""
echo "=== 5. Wiring ==="

# -- v2.1.74 wiring --

# spawn_agent full model IDs
if grep -c 'SUPPORTS_FULL_MODEL_IDS.*true' "$ORCH" >/dev/null 2>&1; then
    spawn_context=$(grep -A5 'SUPPORTS_SUBAGENT_MODEL_FIX.*true' "$ORCH" | head -10)
    if echo "$spawn_context" | grep -c 'SUPPORTS_FULL_MODEL_IDS' >/dev/null 2>&1; then
        pass "Wired: SUPPORTS_FULL_MODEL_IDS in spawn_agent"
    else
        fail "Wired: SUPPORTS_FULL_MODEL_IDS in spawn_agent" "not found near SUBAGENT_MODEL_FIX check"
    fi
fi

# doctor context-suggestions
if grep -c 'doctor_add.*context-suggestions' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor context-suggestions check"
else
    fail "Wired: doctor context-suggestions check" "no doctor_add for context-suggestions"
fi

# doctor autoMemoryDirectory
if grep -c 'autoMemoryDirectory' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor autoMemoryDirectory check"
else
    fail "Wired: doctor autoMemoryDirectory check" "no autoMemoryDirectory reference"
fi

# -- v2.1.76 wiring --

# spawn_agent BG partial results
if grep -c 'SUPPORTS_BG_PARTIAL_RESULTS.*true' "$ORCH" >/dev/null 2>&1; then
    if grep -c 'background agent partial results' "$ORCH" >/dev/null 2>&1; then
        pass "Wired: SUPPORTS_BG_PARTIAL_RESULTS in spawn_agent"
    else
        fail "Wired: SUPPORTS_BG_PARTIAL_RESULTS in spawn_agent" "no spawn_agent log for BG partial results"
    fi
fi

# doctor effort-command
if grep -c 'doctor_add.*effort-command' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor effort-command check"
else
    fail "Wired: doctor effort-command check" "no doctor_add for effort-command"
fi

# doctor worktree-sparse-paths
if grep -c 'doctor_add.*worktree-sparse-paths' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor worktree-sparse-paths check"
else
    fail "Wired: doctor worktree-sparse-paths check" "no doctor_add for worktree-sparse-paths"
fi

# doctor mcp-elicitation
if grep -c 'doctor_add.*mcp-elicitation' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor mcp-elicitation check"
else
    fail "Wired: doctor mcp-elicitation check" "no doctor_add for mcp-elicitation"
fi

# doctor plugin-dir-one-path
if grep -c 'doctor_add.*plugin-dir-one-path' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor plugin-dir-one-path warning"
else
    fail "Wired: doctor plugin-dir-one-path warning" "no doctor_add for plugin-dir behavioral change"
fi

# doctor CC v2.1.76 references
if grep -c 'CC v2.1.76.*effort' "$ORCH" >/dev/null 2>&1; then
    pass "Doctor: effort check references CC v2.1.76"
else
    fail "Doctor: effort check references CC v2.1.76" "doctor effort check missing v2.1.76 reference"
fi

if grep -c 'CC v2.1.76.*sparse' "$ORCH" >/dev/null 2>&1; then
    pass "Doctor: sparse paths check references CC v2.1.76"
else
    fail "Doctor: sparse paths check references CC v2.1.76" "doctor sparse paths check missing v2.1.76 reference"
fi

# -- v2.1.77 wiring --

# resume_agent uses dispatch_method send_message
if grep -c 'dispatch_method: "send_message"' "$ORCH" >/dev/null 2>&1; then
    pass "resume_agent uses dispatch_method send_message"
else
    fail "resume_agent dispatch_method" "expected send_message, not found"
fi

# flow-develop.md: no Agent(resume=), uses SendMessage
develop_skill="$PROJECT_ROOT/.claude/skills/flow-develop.md"
if [[ -f "$develop_skill" ]]; then
    old_resume_count="$(grep -c 'Agent.*resume=' "$develop_skill" 2>/dev/null)" || old_resume_count=0
    if [[ "$old_resume_count" -eq 0 ]]; then
        pass "flow-develop.md does NOT instruct Agent(resume=)"
    else
        fail "flow-develop.md still uses Agent(resume=)" "found $old_resume_count references"
    fi

    if grep -c 'SendMessage' "$develop_skill" >/dev/null 2>&1; then
        pass "flow-develop.md uses SendMessage for continuation"
    else
        fail "flow-develop.md SendMessage" "SendMessage not found in Step 3b"
    fi
fi

# doctor tips for v2.1.77
for label in "plugin-validate" "allow-read-sandbox" "branch-command" "sendmessage-resume" "bg-bash-5gb"; do
    if grep -c "\"$label\"" "$ORCH" >/dev/null 2>&1; then
        pass "Doctor tip: $label"
    else
        fail "Doctor tip: $label" "not found in doctor checks"
    fi
done

# resume command references
resume_cmd="$PROJECT_ROOT/.claude/commands/resume.md"
if [[ -f "$resume_cmd" ]]; then
    if grep -c 'v2.1.77' "$resume_cmd" >/dev/null 2>&1; then
        pass "resume.md references v2.1.77"
    else
        fail "resume.md v2.1.77 note" "no v2.1.77 mention"
    fi

    if grep -c 'SendMessage' "$resume_cmd" >/dev/null 2>&1; then
        pass "resume.md mentions SendMessage"
    else
        fail "resume.md SendMessage" "no SendMessage reference"
    fi
fi

# ╔══════════════════════════════════════════════════════════════════════╗
# ║  6. Version comments in source                                      ║
# ╚══════════════════════════════════════════════════════════════════════╝
echo ""
echo "=== 6. Version Comments ==="

# v2.1.72/v2.1.74 comments
for flag_ver in "PARALLEL_TOOL_RESILIENCE.*v2.1.72" \
                "AUTO_MEMORY_DIR.*v2.1.74" "FULL_MODEL_IDS.*v2.1.74" \
                "CONTEXT_SUGGESTIONS.*v2.1.74" "PLUGIN_DIR_OVERRIDE.*v2.1.74"; do
    if grep -cE "$flag_ver" "$ORCH" >/dev/null 2>&1; then
        pass "Version comment: $flag_ver"
    else
        fail "Version comment: $flag_ver" "missing or wrong version in comment"
    fi
done

# v2.1.76 comments
for flag_ver in "MCP_ELICITATION.*v2.1.76" "WORKTREE_SPARSE_PATHS.*v2.1.76" \
                "EFFORT_COMMAND.*v2.1.76" "BG_PARTIAL_RESULTS.*v2.1.76"; do
    if grep -cE "$flag_ver" "$ORCH" >/dev/null 2>&1; then
        pass "Version comment: $flag_ver"
    else
        fail "Version comment: $flag_ver" "missing or wrong version in comment"
    fi
done

# ╔══════════════════════════════════════════════════════════════════════╗
# ║  7. Skill frontmatter & integration                                 ║
# ╚══════════════════════════════════════════════════════════════════════╝
echo ""
echo "=== 7. Skill Frontmatter ==="

# context: fork on heavy skills
for skill in skill-prd.md skill-code-review.md skill-debate.md skill-deep-research.md; do
    skill_path="$PROJECT_ROOT/.claude/skills/$skill"
    if [[ -f "$skill_path" ]] && grep -q '^context: fork' "$skill_path"; then
        pass "$skill has context: fork"
    else
        fail "$skill has context: fork" "missing or file not found"
    fi
done

# agent field on specialized skills
if grep -q '^agent: Plan' "$PROJECT_ROOT/.claude/skills/skill-prd.md"; then
    pass "skill-prd.md has agent: Plan"
else
    fail "skill-prd.md agent" "missing agent: Plan"
fi

for skill in skill-code-review.md skill-deep-research.md; do
    skill_path="$PROJECT_ROOT/.claude/skills/$skill"
    if [[ -f "$skill_path" ]] && grep -q '^agent: Explore' "$skill_path"; then
        pass "$skill has agent: Explore"
    else
        fail "$skill agent" "missing agent: Explore"
    fi
done

# Session ID in flow banners
for skill in flow-discover.md flow-define.md flow-develop.md flow-deliver.md; do
    skill_path="$PROJECT_ROOT/.claude/skills/$skill"
    if [[ -f "$skill_path" ]] && grep -q 'Session: \${CLAUDE_SESSION_ID}' "$skill_path"; then
        pass "$skill has session ID in banner"
    else
        fail "$skill session ID" "missing Session: \${CLAUDE_SESSION_ID}"
    fi
done

# Native background tasks docs
if grep -q 'Native Background Tasks' "$PROJECT_ROOT/.claude/skills/flow-discover.md"; then
    pass "flow-discover.md has native background tasks documentation"
else
    fail "flow-discover.md background tasks" "missing Native Background Tasks section"
fi

# LSP integration guidance
if grep -q 'LSP Integration' "$PROJECT_ROOT/.claude/skills/skill-architecture.md"; then
    pass "skill-architecture.md has LSP integration guidance"
else
    fail "skill-architecture.md LSP" "missing LSP Integration section"
fi

# YAML frontmatter validity
valid=true
for skill in skill-prd.md skill-code-review.md skill-debate.md skill-deep-research.md; do
    skill_path="$PROJECT_ROOT/.claude/skills/$skill"
    if [[ -f "$skill_path" ]]; then
        if ! head -n 1 "$skill_path" | grep -q "^---$"; then
            echo "  $skill: Missing opening YAML delimiter"
            valid=false
        fi
        if ! awk '/^---$/{count++; if(count==2) found=1} END{exit !found}' "$skill_path"; then
            echo "  $skill: Missing closing YAML delimiter"
            valid=false
        fi
        if ! grep -q "^name:" "$skill_path"; then
            echo "  $skill: Missing name field"
            valid=false
        fi
    else
        echo "  $skill: File not found"
        valid=false
    fi
done

if $valid; then
    pass "Updated skills have valid YAML frontmatter"
else
    fail "YAML frontmatter validity" "some skills have invalid frontmatter"
fi

# ╔══════════════════════════════════════════════════════════════════════╗
# ║  8. Cumulative counts                                               ║
# ╚══════════════════════════════════════════════════════════════════════╝
echo ""
echo "=== 8. Cumulative Counts ==="

flag_count=$(grep -c 'SUPPORTS_.*=false' "$ORCH" || true)
if [[ $flag_count -ge 90 ]]; then
    pass "Total flag count: $flag_count (expected >= 90)"
else
    fail "Total flag count: $flag_count" "expected >= 90 flags"
fi

block_count=$(grep -c 'version_compare.*CLAUDE_CODE_VERSION' "$ORCH" || true)
if [[ $block_count -ge 29 ]]; then
    pass "Version compare block count: $block_count (expected >= 29)"
else
    fail "Version compare block count: $block_count" "expected >= 29 blocks"
fi

# ╔══════════════════════════════════════════════════════════════════════╗
# ║  Summary                                                            ║
# ╚══════════════════════════════════════════════════════════════════════╝
test_summary
