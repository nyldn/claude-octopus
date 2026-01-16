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
test_cmd() {
    local name="$1"
    local cmd="$2"
    local expect_exit="${3:-0}"  # 0 = expect success, 1 = expect failure

    echo -n "  $name... "

    output=$(eval "$cmd" 2>&1)
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
test_output() {
    local name="$1"
    local cmd="$2"
    local expect_pattern="$3"

    echo -n "  $name... "

    output=$(eval "$cmd" 2>&1)
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
# 14. README QUALITY REVIEW
# Scores the README on theme, methodology, humor, and readability
# ============================================
echo -e "${YELLOW}14. README Quality Review${NC}"

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
