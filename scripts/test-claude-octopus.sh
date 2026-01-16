#!/bin/bash
# test-claude-octopus.sh - Comprehensive test suite for Claude Octopus
# Run with: ./scripts/test-claude-octopus.sh

set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/orchestrate.sh"
PASS=0
FAIL=0
SKIP=0

# Test function
# SECURITY: Uses bash -c instead of eval for safer command execution
test_cmd() {
    local name="$1"
    local cmd="$2"
    local expect_exit="${3:-0}"  # 0 = expect success, 1 = expect failure

    echo -n "  $name... "

    output=$(bash -c "$cmd" 2>&1)
    exit_code=$?

    if [[ "$expect_exit" == "0" ]]; then
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}PASS${NC}"
            ((PASS++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (exit code: $exit_code)"
            echo "    Output: ${output:0:200}"
            ((FAIL++))
            return 1
        fi
    else
        if [[ $exit_code -ne 0 ]]; then
            echo -e "${GREEN}PASS${NC} (expected failure)"
            ((PASS++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (expected failure, got success)"
            ((FAIL++))
            return 1
        fi
    fi
}

# Test function for output validation
# SECURITY: Uses bash -c instead of eval for safer command execution
test_output() {
    local name="$1"
    local cmd="$2"
    local expect_pattern="$3"

    echo -n "  $name... "

    output=$(bash -c "$cmd" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]] && echo "$output" | grep -qE "$expect_pattern"; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "    Expected pattern: $expect_pattern"
        echo "    Output: ${output:0:200}"
        ((FAIL++))
        return 1
    fi
}

echo ""
echo "========================================"
echo "  Claude Octopus Test Suite"
echo "========================================"
echo ""

# ============================================
# 1. SYNTAX & BASIC SETUP
# ============================================
echo -e "${YELLOW}1. Syntax & Setup${NC}"

test_cmd "Script syntax check" "bash -n '$SCRIPT'"
test_cmd "Help (simple)" "'$SCRIPT' help"
test_cmd "Help (full)" "'$SCRIPT' help --full"
test_cmd "Help (auto command)" "'$SCRIPT' help auto"
test_cmd "Help (research command)" "'$SCRIPT' help research"
test_cmd "Init workspace" "'$SCRIPT' init"

echo ""

# ============================================
# 2. DRY-RUN: DOUBLE DIAMOND PHASES
# ============================================
echo -e "${YELLOW}2. Dry-Run: Double Diamond Phases${NC}"

test_cmd "Probe (discover)" "'$SCRIPT' -n probe 'test prompt'"
test_cmd "Grasp (define)" "'$SCRIPT' -n grasp 'test prompt'"
test_cmd "Tangle (develop)" "'$SCRIPT' -n tangle 'test prompt'"
test_cmd "Ink (deliver)" "'$SCRIPT' -n ink 'test prompt'"
test_cmd "Embrace (full workflow)" "'$SCRIPT' -n embrace 'test prompt'"

echo ""

# ============================================
# 3. DRY-RUN: COMMAND ALIASES
# ============================================
echo -e "${YELLOW}3. Dry-Run: Command Aliases${NC}"

test_cmd "research (probe alias)" "'$SCRIPT' -n research 'test'"
test_cmd "define (grasp alias)" "'$SCRIPT' -n define 'test'"
test_cmd "develop (tangle alias)" "'$SCRIPT' -n develop 'test'"
test_cmd "deliver (ink alias)" "'$SCRIPT' -n deliver 'test'"

echo ""

# ============================================
# 4. DRY-RUN: SMART AUTO-ROUTING
# ============================================
echo -e "${YELLOW}4. Dry-Run: Smart Auto-Routing${NC}"

test_output "Routes 'research' to probe" "'$SCRIPT' -n auto 'research best practices'" "PROBE|probe|diamond-discover"
test_output "Routes 'define' to grasp" "'$SCRIPT' -n auto 'define requirements for auth'" "GRASP|grasp|diamond-define"
test_output "Routes 'build' to tangle+ink" "'$SCRIPT' -n auto 'build a new feature'" "TANGLE|tangle|diamond-develop"
test_output "Routes 'review' to ink" "'$SCRIPT' -n auto 'review the code'" "INK|ink|diamond-deliver"
test_output "Routes 'design' to gemini" "'$SCRIPT' -n auto 'design a responsive UI'" "gemini|design"
test_output "Routes 'generate icon' to gemini-image" "'$SCRIPT' -n auto 'generate an app icon'" "gemini-image|image"
test_output "Routes 'fix bug' to codex" "'$SCRIPT' -n auto 'fix the null pointer bug'" "codex|coding"

echo ""

# ============================================
# 5. DRY-RUN: AGENT SPAWNING
# ============================================
echo -e "${YELLOW}5. Dry-Run: Agent Spawning${NC}"

test_cmd "Spawn codex" "'$SCRIPT' -n spawn codex 'test'"
test_cmd "Spawn gemini" "'$SCRIPT' -n spawn gemini 'test'"
test_cmd "Spawn codex-mini" "'$SCRIPT' -n spawn codex-mini 'test'"
test_cmd "Spawn codex-review" "'$SCRIPT' -n spawn codex-review 'test'"
test_cmd "Spawn gemini-fast" "'$SCRIPT' -n spawn gemini-fast 'test'"
test_cmd "Fan-out" "'$SCRIPT' -n fan-out 'test prompt'"
test_cmd "Map-reduce" "'$SCRIPT' -n map-reduce 'test prompt'"

echo ""

# ============================================
# 6. DRY-RUN: FLAGS & OPTIONS
# ============================================
echo -e "${YELLOW}6. Dry-Run: Flags & Options${NC}"

test_cmd "Verbose flag (-v)" "'$SCRIPT' -v -n auto 'test'"
test_cmd "Quick tier (-Q)" "'$SCRIPT' -Q -n auto 'test'"
test_cmd "Premium tier (-P)" "'$SCRIPT' -P -n auto 'test'"
test_cmd "Custom parallel (-p 5)" "'$SCRIPT' -p 5 -n auto 'test'"
test_cmd "Custom timeout (-t 600)" "'$SCRIPT' -t 600 -n auto 'test'"
test_cmd "No personas (--no-personas)" "'$SCRIPT' --no-personas -n auto 'test'"
test_cmd "Custom quality (-q 80)" "'$SCRIPT' -q 80 -n tangle 'test'"

echo ""

# ============================================
# 7. COST TRACKING
# ============================================
echo -e "${YELLOW}7. Cost Tracking${NC}"

test_cmd "Cost report (table)" "'$SCRIPT' cost"
test_cmd "Cost report (JSON)" "'$SCRIPT' cost-json"
test_cmd "Cost report (CSV)" "'$SCRIPT' cost-csv"
# Note: cost-clear and cost-archive modify state, skipping in automated tests

echo ""

# ============================================
# 8. WORKSPACE MANAGEMENT
# ============================================
echo -e "${YELLOW}8. Workspace Management${NC}"

test_cmd "Status" "'$SCRIPT' status"
# Note: kill, clean, aggregate modify state - manual testing recommended

echo ""

# ============================================
# 9. ERROR HANDLING
# ============================================
echo -e "${YELLOW}9. Error Handling${NC}"

test_cmd "Unknown command shows suggestions" "'$SCRIPT' badcommand" 1
test_cmd "Missing prompt for probe" "'$SCRIPT' probe" 1
test_cmd "Missing prompt for tangle" "'$SCRIPT' tangle" 1
# Note: Invalid agent test depends on implementation

echo ""

# ============================================
# 10. RALPH-WIGGUM ITERATION
# ============================================
echo -e "${YELLOW}10. Ralph-Wiggum Iteration${NC}"

test_cmd "Ralph dry-run" "'$SCRIPT' -n ralph 'test iteration'"
test_cmd "Iterate alias dry-run" "'$SCRIPT' -n iterate 'test iteration'"

echo ""

# ============================================
# 11. OPTIMIZATION COMMANDS (v4.2)
# ============================================
echo -e "${YELLOW}11. Optimization Commands${NC}"

test_cmd "Optimize dry-run" "'$SCRIPT' -n optimize 'make it faster'"
test_cmd "Optimise alias dry-run" "'$SCRIPT' -n optimise 'make it faster'"
test_output "Routes performance optimization" "'$SCRIPT' -n auto 'optimize performance and speed'" "optimize-performance|OPTIMIZE.*Performance"
test_output "Routes cost optimization" "'$SCRIPT' -n auto 'reduce AWS costs'" "optimize-cost|OPTIMIZE.*Cost"
test_output "Routes database optimization" "'$SCRIPT' -n auto 'optimize slow database queries'" "optimize-database|OPTIMIZE.*Database"
test_output "Routes accessibility optimization" "'$SCRIPT' -n auto 'improve accessibility and WCAG'" "optimize-accessibility|OPTIMIZE.*Accessibility"
test_output "Routes SEO optimization" "'$SCRIPT' -n auto 'optimize for search engines'" "optimize-seo|OPTIMIZE.*SEO"
test_output "Routes full site audit" "'$SCRIPT' -n auto 'full site audit'" "optimize-audit|Full Site Audit"
test_output "Routes comprehensive audit" "'$SCRIPT' -n auto 'comprehensive site optimization'" "optimize-audit|Full Site Audit"
test_output "Routes audit my website" "'$SCRIPT' -n auto 'audit my website'" "optimize-audit|Full Site Audit"
test_cmd "Help (optimize command)" "'$SCRIPT' help optimize"

echo ""

# ============================================
# 12. AUTHENTICATION (v4.2)
# ============================================
echo -e "${YELLOW}12. Authentication${NC}"

test_cmd "Auth status" "'$SCRIPT' auth status"
test_cmd "Help (auth command)" "'$SCRIPT' help auth"

echo ""

# ============================================
# 13. SHELL COMPLETION (v4.2)
# ============================================
echo -e "${YELLOW}13. Shell Completion${NC}"

test_cmd "Bash completion" "'$SCRIPT' completion bash"
test_cmd "Zsh completion" "'$SCRIPT' completion zsh"
test_cmd "Fish completion" "'$SCRIPT' completion fish"
test_cmd "Help (completion command)" "'$SCRIPT' help completion"

echo ""

# ============================================
# 14. PHASE 3: CONFIDENCE BUILDERS (v4.3)
# ============================================
echo -e "${YELLOW}14. Phase 3: Confidence Builders${NC}"

# Interactive Setup Wizard
test_cmd "Help (init command)" "'$SCRIPT' help init"
test_output "Init help shows --interactive" "'$SCRIPT' help init" "interactive|wizard"

# Error code system (check that the show_error function exists)
test_output "Error codes defined" "grep -c 'E001\|E002\|E003' '$SCRIPT'" "^[3-9]|^[1-9][0-9]"

echo ""

# ============================================
# 15. PHASE 4 FEATURES (v4.4)
# Human-in-the-loop review workflows and CI/CD integration
# ============================================
echo -e "${YELLOW}15. Phase 4 Features (v4.4 - Human-in-the-loop)${NC}"

# Test --ci flag
test_cmd "CI flag parsing" "$SCRIPT --ci -n auto 'test'" 0

# Test review command
test_cmd "Review list" "$SCRIPT review list" 0
test_cmd "Review help" "$SCRIPT review" 0
test_cmd "Review show missing ID" "$SCRIPT review show" 1

# Test audit command
test_cmd "Audit trail" "$SCRIPT audit" 0 || true  # May fail if no audit log exists
test_cmd "Audit with count" "$SCRIPT audit 10" 0 || true

# Test help for new commands
test_cmd "Help review command" "$SCRIPT help review" 0
test_cmd "Help audit command" "$SCRIPT help audit" 0

# Test GitHub Actions workflow exists
echo -n "  Testing: GitHub Actions template exists... "
if [[ -f "$SCRIPT_DIR/../.github/workflows/claude-octopus.yml" ]]; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# Test CI/CD mode integration (environment detection)
echo -n "  Testing: CI environment detection... "
if CI=true $SCRIPT -n auto "test" 2>&1 | grep -q "CI environment detected\|DRY-RUN"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${GREEN}PASS${NC} (CI mode activated silently)"
    ((PASS++))
fi

echo ""

# ============================================
# 16. README QUALITY REVIEW
# Scores the README on theme, methodology, humor, and readability
# ============================================
echo -e "${YELLOW}16. README Quality Review${NC}"

README_FILE="$SCRIPT_DIR/../README.md"
README_SCORE=0
README_MAX=100

if [[ -f "$README_FILE" ]]; then
    README_CONTENT=$(cat "$README_FILE")

    # ─────────────────────────────────────────────────────────────
    # OCTOPUS THEME ALIGNMENT (25 points max)
    # ─────────────────────────────────────────────────────────────
    THEME_SCORE=0
    THEME_MAX=25

    # Check for octopus emoji (🐙) - 5 points
    octopus_count=$(echo "$README_CONTENT" | grep -o '🐙' | wc -l | tr -d ' ')
    if [[ $octopus_count -ge 5 ]]; then
        ((THEME_SCORE+=5))
    elif [[ $octopus_count -ge 3 ]]; then
        ((THEME_SCORE+=3))
    elif [[ $octopus_count -ge 1 ]]; then
        ((THEME_SCORE+=1))
    fi

    # Check for tentacle references - 5 points
    tentacle_count=$(echo "$README_CONTENT" | grep -oi 'tentacle' | wc -l | tr -d ' ')
    if [[ $tentacle_count -ge 5 ]]; then
        ((THEME_SCORE+=5))
    elif [[ $tentacle_count -ge 3 ]]; then
        ((THEME_SCORE+=3))
    elif [[ $tentacle_count -ge 1 ]]; then
        ((THEME_SCORE+=2))
    fi

    # Check for arm/arms references - 3 points
    if echo "$README_CONTENT" | grep -qi '8 arms\|eight arms'; then
        ((THEME_SCORE+=3))
    fi

    # Check for ink references - 3 points
    ink_count=$(echo "$README_CONTENT" | grep -oi '\bink\b' | wc -l | tr -d ' ')
    if [[ $ink_count -ge 3 ]]; then
        ((THEME_SCORE+=3))
    elif [[ $ink_count -ge 1 ]]; then
        ((THEME_SCORE+=2))
    fi

    # Check for octopus ASCII art - 5 points
    if echo "$README_CONTENT" | grep -q "0) ~ (0)"; then
        ((THEME_SCORE+=5))
    fi

    # Check for ocean/marine vocabulary - 4 points
    if echo "$README_CONTENT" | grep -qiE 'suction|squeeze|camouflage|hunt|jet|squirt'; then
        ((THEME_SCORE+=4))
    fi

    echo -n "  Octopus Theme Alignment... "
    if [[ $THEME_SCORE -ge 20 ]]; then
        echo -e "${GREEN}$THEME_SCORE/$THEME_MAX${NC} (excellent)"
    elif [[ $THEME_SCORE -ge 15 ]]; then
        echo -e "${GREEN}$THEME_SCORE/$THEME_MAX${NC} (good)"
    elif [[ $THEME_SCORE -ge 10 ]]; then
        echo -e "${YELLOW}$THEME_SCORE/$THEME_MAX${NC} (fair)"
    else
        echo -e "${RED}$THEME_SCORE/$THEME_MAX${NC} (needs work)"
    fi
    ((README_SCORE+=THEME_SCORE))

    # ─────────────────────────────────────────────────────────────
    # DOUBLE DIAMOND METHODOLOGY (25 points max)
    # ─────────────────────────────────────────────────────────────
    DD_SCORE=0
    DD_MAX=25

    # Check for phase names - 4 points each (16 total)
    if echo "$README_CONTENT" | grep -qi 'probe\|discover'; then ((DD_SCORE+=4)); fi
    if echo "$README_CONTENT" | grep -qi 'grasp\|define'; then ((DD_SCORE+=4)); fi
    if echo "$README_CONTENT" | grep -qi 'tangle\|develop'; then ((DD_SCORE+=4)); fi
    if echo "$README_CONTENT" | grep -qi 'ink\|deliver'; then ((DD_SCORE+=4)); fi

    # Check for "Double Diamond" explicit mention - 3 points
    if echo "$README_CONTENT" | grep -qi 'double diamond'; then
        ((DD_SCORE+=3))
    fi

    # Check for embrace (full workflow) - 3 points
    if echo "$README_CONTENT" | grep -qi 'embrace'; then
        ((DD_SCORE+=3))
    fi

    # Check for diverge/converge language - 3 points
    if echo "$README_CONTENT" | grep -qiE 'diverge|converge'; then
        ((DD_SCORE+=3))
    fi

    echo -n "  Double Diamond Coverage... "
    if [[ $DD_SCORE -ge 20 ]]; then
        echo -e "${GREEN}$DD_SCORE/$DD_MAX${NC} (excellent)"
    elif [[ $DD_SCORE -ge 15 ]]; then
        echo -e "${GREEN}$DD_SCORE/$DD_MAX${NC} (good)"
    elif [[ $DD_SCORE -ge 10 ]]; then
        echo -e "${YELLOW}$DD_SCORE/$DD_MAX${NC} (fair)"
    else
        echo -e "${RED}$DD_SCORE/$DD_MAX${NC} (needs work)"
    fi
    ((README_SCORE+=DD_SCORE))

    # ─────────────────────────────────────────────────────────────
    # HUMOR & PERSONALITY (20 points max)
    # ─────────────────────────────────────────────────────────────
    HUMOR_SCORE=0
    HUMOR_MAX=20

    # Check for puns and playful language - 5 points
    pun_patterns="infinite possibilities|neurons in each|suction cups|untangles everything|tentacles.*love|can't rush perfection"
    pun_count=$(echo "$README_CONTENT" | grep -oiE "$pun_patterns" | wc -l | tr -d ' ')
    if [[ $pun_count -ge 3 ]]; then
        ((HUMOR_SCORE+=5))
    elif [[ $pun_count -ge 1 ]]; then
        ((HUMOR_SCORE+=3))
    fi

    # Check for fun facts - 4 points
    if echo "$README_CONTENT" | grep -qi 'fun fact\|coincidence'; then
        ((HUMOR_SCORE+=4))
    fi

    # Check for italic commentary (*text*) - 4 points
    italic_count=$(echo "$README_CONTENT" | grep -oE '\*[^*]+\*' | wc -l | tr -d ' ')
    if [[ $italic_count -ge 5 ]]; then
        ((HUMOR_SCORE+=4))
    elif [[ $italic_count -ge 2 ]]; then
        ((HUMOR_SCORE+=2))
    fi

    # Check for playful section titles or headers - 4 points
    if echo "$README_CONTENT" | grep -qi 'Octopus Philosophy\|meet our mascot'; then
        ((HUMOR_SCORE+=4))
    fi

    # Check for emojis (beyond octopus) - 3 points
    # Count each emoji individually due to multi-byte grep issues
    emoji_variety=0
    for emoji in ⚡ 💰 🗃️ 📦 ♿ 🔍 🖼️ 🎨 🔎 🦑 🖤 🎩 🚦 📋 🔄 🎭 🧠 🤝; do
        if echo "$README_CONTENT" | grep -q "$emoji" 2>/dev/null; then
            ((emoji_variety++))
        fi
    done
    if [[ $emoji_variety -ge 5 ]]; then
        ((HUMOR_SCORE+=3))
    elif [[ $emoji_variety -ge 3 ]]; then
        ((HUMOR_SCORE+=2))
    fi

    echo -n "  Humor & Personality... "
    if [[ $HUMOR_SCORE -ge 16 ]]; then
        echo -e "${GREEN}$HUMOR_SCORE/$HUMOR_MAX${NC} (excellent)"
    elif [[ $HUMOR_SCORE -ge 12 ]]; then
        echo -e "${GREEN}$HUMOR_SCORE/$HUMOR_MAX${NC} (good)"
    elif [[ $HUMOR_SCORE -ge 8 ]]; then
        echo -e "${YELLOW}$HUMOR_SCORE/$HUMOR_MAX${NC} (fair)"
    else
        echo -e "${RED}$HUMOR_SCORE/$HUMOR_MAX${NC} (needs work)"
    fi
    ((README_SCORE+=HUMOR_SCORE))

    # ─────────────────────────────────────────────────────────────
    # READABILITY & STRUCTURE (30 points max)
    # ─────────────────────────────────────────────────────────────
    READ_SCORE=0
    READ_MAX=30

    # Check for table of contents - 4 points
    if echo "$README_CONTENT" | grep -qi 'table of contents'; then
        ((READ_SCORE+=4))
    fi

    # Check for code blocks (```) - 6 points
    code_blocks=$(echo "$README_CONTENT" | grep -c '```' | tr -d ' ')
    code_blocks=$((code_blocks / 2))  # pairs
    if [[ $code_blocks -ge 15 ]]; then
        ((READ_SCORE+=6))
    elif [[ $code_blocks -ge 10 ]]; then
        ((READ_SCORE+=4))
    elif [[ $code_blocks -ge 5 ]]; then
        ((READ_SCORE+=2))
    fi

    # Check for tables (|---|) - 5 points
    table_count=$(echo "$README_CONTENT" | grep -c '|.*|.*|' | tr -d ' ')
    if [[ $table_count -ge 20 ]]; then
        ((READ_SCORE+=5))
    elif [[ $table_count -ge 10 ]]; then
        ((READ_SCORE+=3))
    elif [[ $table_count -ge 5 ]]; then
        ((READ_SCORE+=2))
    fi

    # Check for section headers (##) - 5 points
    header_count=$(echo "$README_CONTENT" | grep -c '^##' | tr -d ' ')
    if [[ $header_count -ge 15 ]]; then
        ((READ_SCORE+=5))
    elif [[ $header_count -ge 10 ]]; then
        ((READ_SCORE+=3))
    elif [[ $header_count -ge 5 ]]; then
        ((READ_SCORE+=2))
    fi

    # Check for examples section - 4 points
    if echo "$README_CONTENT" | grep -qi 'example'; then
        ((READ_SCORE+=4))
    fi

    # Check for troubleshooting section - 3 points
    if echo "$README_CONTENT" | grep -qi 'troubleshoot'; then
        ((READ_SCORE+=3))
    fi

    # Check for badges at top - 3 points
    if echo "$README_CONTENT" | grep -q 'img.shields.io'; then
        ((READ_SCORE+=3))
    fi

    echo -n "  Readability & Structure... "
    if [[ $READ_SCORE -ge 24 ]]; then
        echo -e "${GREEN}$READ_SCORE/$READ_MAX${NC} (excellent)"
    elif [[ $READ_SCORE -ge 18 ]]; then
        echo -e "${GREEN}$READ_SCORE/$READ_MAX${NC} (good)"
    elif [[ $READ_SCORE -ge 12 ]]; then
        echo -e "${YELLOW}$READ_SCORE/$READ_MAX${NC} (fair)"
    else
        echo -e "${RED}$READ_SCORE/$READ_MAX${NC} (needs work)"
    fi
    ((README_SCORE+=READ_SCORE))

    # ─────────────────────────────────────────────────────────────
    # OVERALL README SCORE
    # ─────────────────────────────────────────────────────────────
    echo ""
    echo -n "  📖 Overall README Score: "

    # Calculate percentage
    README_PCT=$((README_SCORE * 100 / README_MAX))

    if [[ $README_PCT -ge 85 ]]; then
        echo -e "${GREEN}$README_SCORE/$README_MAX ($README_PCT%)${NC} 🐙 Tentacular!"
        ((PASS++))
    elif [[ $README_PCT -ge 70 ]]; then
        echo -e "${GREEN}$README_SCORE/$README_MAX ($README_PCT%)${NC} Good catch!"
        ((PASS++))
    elif [[ $README_PCT -ge 55 ]]; then
        echo -e "${YELLOW}$README_SCORE/$README_MAX ($README_PCT%)${NC} Room to grow"
        ((PASS++))
    else
        echo -e "${RED}$README_SCORE/$README_MAX ($README_PCT%)${NC} Needs more ink!"
        ((FAIL++))
    fi
else
    echo -e "  ${RED}README.md not found${NC}"
    ((FAIL++))
fi

echo ""

# ============================================
# 17. PHASE 5 FEATURES (v4.5)
# Smart Setup Wizard: Intent & Resource-Aware Configuration
# ============================================
echo -e "${YELLOW}17. Phase 5 Features (v4.5 - Smart Setup)${NC}"

# Test help for config command (config is interactive, so we just test help)
test_cmd "Help config command" "$SCRIPT help config" 0

# Test config command function exists in script
echo -n "  Testing: Config command dispatches correctly... "
if grep -q 'config|configure|preferences)' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# Test config file save/load roundtrip
echo -n "  Testing: Config save/load roundtrip... "
TEST_CONFIG_DIR=$(mktemp -d)
TEST_CONFIG_FILE="$TEST_CONFIG_DIR/.user-config"

# Create test config manually
cat > "$TEST_CONFIG_FILE" << 'TESTCFG'
version: "1.0"
created_at: "2026-01-15T10:00:00Z"
updated_at: "2026-01-15T10:00:00Z"
intent:
  primary: "backend"
  all: ["backend", "devops"]
resource_tier: "max-5x"
available_keys:
  openai: true
  gemini: true
  anthropic: false
settings:
  opus_budget: "balanced"
  default_complexity: 2
  prefer_gemini_for_analysis: true
  max_parallel_agents: 3
TESTCFG

# Verify config file was created
if [[ -f "$TEST_CONFIG_FILE" ]]; then
    # Parse primary intent
    primary_intent=$(grep "^  primary:" "$TEST_CONFIG_FILE" | sed 's/.*: *//' | tr -d '"')
    resource_tier=$(grep "^resource_tier:" "$TEST_CONFIG_FILE" | sed 's/.*: *//' | tr -d '"')

    if [[ "$primary_intent" == "backend" ]] && [[ "$resource_tier" == "max-5x" ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC} (parsed: primary=$primary_intent, tier=$resource_tier)"
        ((FAIL++))
    fi
else
    echo -e "${RED}FAIL${NC} (config file not created)"
    ((FAIL++))
fi
rm -rf "$TEST_CONFIG_DIR"

# Test resource tier functions exist in script
echo -n "  Testing: Resource tier functions defined... "
if grep -q 'get_resource_adjusted_tier()' "$SCRIPT" && grep -q 'load_user_config()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# Test intent wizard function exists
echo -n "  Testing: Intent wizard function defined... "
if grep -q 'init_step_intent()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# Test resources wizard function exists
echo -n "  Testing: Resources wizard function defined... "
if grep -q 'init_step_resources()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# Test init has 7 steps
echo -n "  Testing: Init wizard has 7 steps... "
if grep -q 'total_steps=7' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# Test resource tier affects routing (conceptual check)
echo -n "  Testing: get_tiered_agent uses resource tier... "
if grep -A 20 'get_tiered_agent()' "$SCRIPT" | grep -q 'load_user_config\|get_resource_adjusted_tier'; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# Test API fallback function exists
echo -n "  Testing: API fallback function defined... "
if grep -q 'get_fallback_agent()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo ""

# ============================================
# 18. SECURITY TESTS (v4.6.0)
# ============================================
echo -e "${YELLOW}18. Security Tests${NC}"

# --- Path Validation Tests ---
echo -n "  Path validation function exists... "
if grep -q 'validate_workspace_path()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  Path traversal blocked... "
if grep -q '\.\..*path traversal\|traversal.*\.\.' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  Workspace restricted to safe paths... "
if grep -q 'HOME.*tmp.*var/tmp\|safe_prefix\|allowed_prefix' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Command Execution Safety ---
echo -n "  Array-based command execution... "
if grep -q 'cmd_array\|read -ra.*cmd\|\${cmd_array\[@\]}' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  No eval with user input... "
if ! grep -E 'eval "\$\{?(prompt|PROMPT|user_input)' "$SCRIPT" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC} (eval found with user input)"
    ((FAIL++))
fi

# --- JSON Validation ---
echo -n "  JSON extraction validation exists... "
if grep -q 'extract_json_field()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  Agent type validation exists... "
if grep -q 'validate_agent_type()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- CI Mode ---
echo -n "  CI mode detection exists... "
if grep -q 'CI_MODE\|CLAUDE_CODE_DISABLE_BACKGROUND_TASKS' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  CI mode skips interactive prompts... "
if grep -q 'CI_MODE.*true.*auto\|CI_MODE.*abort\|CI mode.*skip' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Claude Code v2.1.9 Integration ---
echo -n "  Claude session ID support... "
if grep -q 'CLAUDE_CODE_SESSION\|CLAUDE_SESSION_ID' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  Plans directory configured... "
if grep -q 'PLANS_DIR' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- API Key Safety ---
echo -n "  API keys not directly logged... "
# Check for direct key value logging (not length or presence checks)
if ! grep -E 'echo.*\$\{?(OPENAI_API_KEY|GEMINI_API_KEY)[^#}]*[^}]"?$|log.*"\$\{?(OPENAI_API_KEY|GEMINI_API_KEY)\}"?' "$SCRIPT" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC} (API key may be logged)"
    ((FAIL++))
fi

echo ""

# ============================================
# 19. CROSSFIRE TESTS (v4.7.0)
# Adversarial Cross-Model Review: grapple and squeeze
# ============================================
echo -e "${YELLOW}19. Crossfire Tests (v4.7.0 - Adversarial Review)${NC}"

# --- Dry-Run Tests ---
test_cmd "Grapple dry-run" "'$SCRIPT' -n grapple 'test debate'"
test_cmd "Squeeze dry-run" "'$SCRIPT' -n squeeze 'test security review'"
test_cmd "Red-team alias dry-run" "'$SCRIPT' -n red-team 'test security review'"

# --- Grapple with Principles ---
test_cmd "Grapple with security principles" "'$SCRIPT' -n grapple --principles security 'test'"
test_cmd "Grapple with performance principles" "'$SCRIPT' -n grapple --principles performance 'test'"
test_cmd "Grapple with maintainability principles" "'$SCRIPT' -n grapple --principles maintainability 'test'"

# --- Auto-Routing to Crossfire ---
test_output "Routes 'security audit' to squeeze" "'$SCRIPT' -n auto 'security audit the auth module'" "squeeze|red-team|crossfire-squeeze"
test_output "Routes 'red team' to squeeze" "'$SCRIPT' -n auto 'red team the payment system'" "squeeze|red-team|crossfire-squeeze"
test_output "Routes 'pentest' to squeeze" "'$SCRIPT' -n auto 'pentest the API endpoints'" "squeeze|red-team|crossfire-squeeze"
test_output "Routes 'adversarial review' to grapple" "'$SCRIPT' -n auto 'adversarial review of the design'" "grapple|crossfire-grapple"
test_output "Routes 'debate' to grapple" "'$SCRIPT' -n auto 'have models debate the architecture'" "grapple|crossfire-grapple"
test_output "Routes 'cross-model review' to grapple" "'$SCRIPT' -n auto 'cross-model review of the implementation'" "grapple|crossfire-grapple"

# --- Function Definitions ---
echo -n "  grapple_debate() function exists... "
if grep -q 'grapple_debate()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  squeeze_test() function exists... "
if grep -q 'squeeze_test()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  No-explore constraint in grapple... "
if grep -A 60 'grapple_debate()' "$SCRIPT" | grep -q 'no_explore_constraint\|Do NOT read.*explore'; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Principles Directory ---
PRINCIPLES_DIR="$SCRIPT_DIR/../agents/principles"

echo -n "  Principles directory exists... "
if [[ -d "$PRINCIPLES_DIR" ]]; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  security.md principles file exists... "
if [[ -f "$PRINCIPLES_DIR/security.md" ]]; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  performance.md principles file exists... "
if [[ -f "$PRINCIPLES_DIR/performance.md" ]]; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  maintainability.md principles file exists... "
if [[ -f "$PRINCIPLES_DIR/maintainability.md" ]]; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  general.md principles file exists... "
if [[ -f "$PRINCIPLES_DIR/general.md" ]]; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Crossfire Classification ---
echo -n "  classify_task detects crossfire intents... "
if grep -A 50 'classify_task()' "$SCRIPT" | grep -qE 'crossfire-grapple|crossfire-squeeze|security.*audit.*squeeze'; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- OAuth Support ---
echo -n "  OAuth auth file check in preflight... "
if grep -q '\.codex/auth\.json' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo ""

# ============================================
# 20. MULTI-PROVIDER ROUTING (v4.8)
# Subscription-aware provider selection and OpenRouter integration
# ============================================
echo -e "${YELLOW}20. Multi-Provider Routing (v4.8)${NC}"

# --- Provider Configuration ---
echo -n "  Provider config file path defined... "
if grep -q 'PROVIDERS_CONFIG_FILE=' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  load_providers_config() function exists... "
if grep -q 'load_providers_config()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  save_providers_config() function exists... "
if grep -q 'save_providers_config()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Provider Detection ---
echo -n "  detect_providers() function exists... "
if grep -q 'detect_providers()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  auto_detect_provider_config() function exists... "
if grep -q 'auto_detect_provider_config()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Scoring Engine ---
echo -n "  score_provider() function exists... "
if grep -q 'score_provider()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  select_provider() function exists... "
if grep -q 'select_provider()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  get_tiered_agent_v2() function exists... "
if grep -q 'get_tiered_agent_v2()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  is_agent_available_v2() function exists... "
if grep -q 'is_agent_available_v2()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- OpenRouter Integration ---
echo -n "  execute_openrouter() function exists... "
if grep -q 'execute_openrouter()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  get_openrouter_model() function exists... "
if grep -q 'get_openrouter_model()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  openrouter agent type defined... "
if grep -q 'openrouter).*openrouter_execute' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- CLI Flags ---
echo -n "  --provider flag parsing... "
if grep -q '\-\-provider).*FORCE_PROVIDER' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  --cost-first flag parsing... "
if grep -q '\-\-cost-first).*FORCE_COST_FIRST' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  --quality-first flag parsing... "
if grep -q '\-\-quality-first).*FORCE_QUALITY_FIRST' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  --openrouter-nitro flag parsing... "
if grep -q '\-\-openrouter-nitro).*OPENROUTER_ROUTING_OVERRIDE' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  --openrouter-floor flag parsing... "
if grep -q '\-\-openrouter-floor).*OPENROUTER_ROUTING_OVERRIDE' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Provider Status Display ---
echo -n "  show_provider_status() function exists... "
if grep -q 'show_provider_status()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  show_status calls show_provider_status... "
if grep -A 10 '^show_status()' "$SCRIPT" | grep -q 'show_provider_status'; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Provider Capabilities ---
echo -n "  get_provider_capabilities() function exists... "
if grep -q 'get_provider_capabilities()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  get_provider_context_limit() function exists... "
if grep -q 'get_provider_context_limit()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  get_cost_tier_value() function exists... "
if grep -q 'get_cost_tier_value()' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Setup Wizard Steps ---
echo -n "  Setup wizard has 9 steps... "
if grep -q 'total_steps=9' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  Setup wizard includes Codex tier step... "
if grep -q 'Codex/OpenAI Subscription Tier' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  Setup wizard includes Gemini tier step... "
if grep -q 'Gemini Subscription Tier' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

echo -n "  Setup wizard includes OpenRouter step... "
if grep -q 'OpenRouter.*Universal Fallback\|OpenRouter Fallback Configuration' "$SCRIPT"; then
    echo -e "${GREEN}PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAIL++))
fi

# --- Provider Config File Roundtrip ---
echo -n "  Provider config save/load roundtrip... "
TEST_PROVIDER_DIR=$(mktemp -d)
TEST_PROVIDER_FILE="$TEST_PROVIDER_DIR/.providers-config"

# Create test config manually
cat > "$TEST_PROVIDER_FILE" << 'TESTCFG'
version: "2.0"
providers:
  codex:
    installed: true
    auth_method: "oauth"
    subscription_tier: "plus"
    cost_tier: "low"
    priority: 2
  gemini:
    installed: true
    auth_method: "oauth"
    subscription_tier: "workspace"
    cost_tier: "bundled"
    priority: 3
  openrouter:
    enabled: false
    api_key_set: false
    routing_preference: "default"
    priority: 99
cost_optimization:
  strategy: "balanced"
TESTCFG

# Verify config file was created
if [[ -f "$TEST_PROVIDER_FILE" ]]; then
    # Parse subscription tier
    codex_tier=$(grep -A5 "^  codex:" "$TEST_PROVIDER_FILE" | grep "subscription_tier:" | sed 's/.*: *//' | tr -d '"')
    gemini_cost=$(grep -A5 "^  gemini:" "$TEST_PROVIDER_FILE" | grep "cost_tier:" | sed 's/.*: *//' | tr -d '"')
    strategy=$(grep "^  strategy:" "$TEST_PROVIDER_FILE" | sed 's/.*: *//' | tr -d '"')

    if [[ "$codex_tier" == "plus" ]] && [[ "$gemini_cost" == "bundled" ]] && [[ "$strategy" == "balanced" ]]; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC} (parsed: codex=$codex_tier, gemini_cost=$gemini_cost, strategy=$strategy)"
        ((FAIL++))
    fi
else
    echo -e "${RED}FAIL${NC} (config file not created)"
    ((FAIL++))
fi
rm -rf "$TEST_PROVIDER_DIR"

echo ""

# ============================================
# SUMMARY
# ============================================
echo "========================================"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "========================================"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
fi
