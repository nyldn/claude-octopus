---
name: skill-debate-integration
description: |
  Claude-octopus integration layer for AI Debate Hub.
  Enhances wolverin0/claude-skills debate functionality with quality gates,
  cost tracking, session-aware storage, and document export.
trigger: |
  AUTOMATICALLY ACTIVATE when:
  - User runs /debate command
  - AI Debate Hub (.dependencies/claude-skills/skills/debate.md) is present
  - Running in claude-octopus context

  Provides enhancements without modifying the original skill.
---

# AI Debate Hub Integration Layer

**Status**: ✅ AI Debate Hub detected at `.dependencies/claude-skills/`

## Attribution

- **Original Skill**: AI Debate Hub by wolverin0
- **Version**: v4.7
- **Repository**: https://github.com/wolverin0/claude-skills
- **License**: MIT
- **Integration Type**: Git submodule (read-only reference)

This skill provides **enhancements only**. The core debate functionality comes from the original skill at `.dependencies/claude-skills/skills/debate.md`.

---

## Claude-Octopus Enhancements

When running debates in claude-octopus, the following enhancements are automatically applied:

### 1. Session-Aware Storage

**Original behavior**:
```
debates/
└── NNN-topic-slug/
    ├── context.md
    ├── state.json
    └── rounds/
```

**Enhanced behavior** (when `CLAUDE_CODE_SESSION` is set):
```
~/.claude-octopus/debates/${SESSION_ID}/
└── NNN-topic-slug/
    ├── context.md
    ├── state.json
    ├── synthesis.md
    └── rounds/
```

**Benefits**:
- Debates organized by Claude Code session
- Easy to find debates from specific conversations
- Automatic cleanup when sessions expire
- Integration with claude-octopus analytics

**Implementation**:
```bash
# Detect session context
if [[ -n "${CLAUDE_CODE_SESSION:-}" ]]; then
    DEBATE_BASE_DIR="${HOME}/.claude-octopus/debates/${CLAUDE_CODE_SESSION}"
else
    DEBATE_BASE_DIR="./debates"  # Fallback to original behavior
fi

export DEBATE_BASE_DIR
```

---

### 2. Quality Gates for Debate Responses

**Enhancement**: Evaluate each advisor response for quality before proceeding to next round.

**Quality Metrics**:

| Metric | Weight | Criteria |
|--------|--------|----------|
| **Length** | 25 pts | 50-1000 words (substantive but concise) |
| **Citations** | 25 pts | References, links, or sources present |
| **Code Examples** | 25 pts | Technical examples or code snippets |
| **Engagement** | 25 pts | Addresses other advisors' specific points |

**Quality Thresholds**:
- **Score >= 75**: Proceed (high quality)
- **Score 50-74**: Proceed with warning (flag in synthesis)
- **Score < 50**: Re-prompt advisor for elaboration

**Example Re-Prompt** (score < 50):
```bash
"Your previous response was brief. Please elaborate with:
1. Specific examples or code snippets
2. References to support your claims
3. Direct engagement with other advisors' arguments
Word limit: 500-800 words."
```

**Integration Point**:
After each advisor responds, before writing to `rounds/r00N_advisor.md`:

```bash
evaluate_response_quality() {
    local response_file="$1"
    local advisor="$2"
    local round="$3"

    word_count=$(wc -w < "$response_file")
    has_citations=$(grep -c '\[' "$response_file" || echo 0)
    has_code=$(grep -c '```' "$response_file" || echo 0)
    addresses_others=$(grep -ciE '(gemini|codex|claude)' "$response_file" || echo 0)

    score=0
    (( word_count >= 50 && word_count <= 1000 )) && (( score += 25 ))
    (( has_citations > 0 )) && (( score += 25 ))
    (( has_code > 0 )) && (( score += 25 ))
    (( addresses_others > 0 )) && (( score += 25 ))

    echo "$score"
}

# After advisor response
quality_score=$(evaluate_response_quality "$response_file" "$advisor" "$round")

if (( quality_score < 50 )); then
    log_warn "Low quality response from $advisor (score: $quality_score). Re-prompting..."
    reprompt_advisor "$advisor" "$elaboration_prompt"
fi
```

---

### 3. Cost Tracking & Analytics

**Enhancement**: Track token usage and cost for each debate, integrated with claude-octopus analytics.

**Cost Breakdown**:
```json
{
  "debate_id": "042-redis-vs-memcached",
  "cost_tracking": {
    "total_cost_usd": 0.142,
    "by_advisor": {
      "gemini": {
        "rounds": 3,
        "total_tokens": 8100,
        "input_tokens": 3200,
        "output_tokens": 4900,
        "cost_usd": 0.068,
        "model": "gemini-3-pro"
      },
      "codex": {
        "rounds": 3,
        "total_tokens": 7200,
        "input_tokens": 2800,
        "output_tokens": 4400,
        "cost_usd": 0.074,
        "model": "gpt-5.1-codex-max"
      }
    },
    "model_pricing": {
      "gemini-3-pro": {
        "input_per_million": 2.50,
        "output_per_million": 10.00
      },
      "gpt-5.1-codex-max": {
        "input_per_million": 3.00,
        "output_per_million": 15.00
      }
    }
  }
}
```

**Analytics Integration**:
```bash
# Append to ~/.claude-octopus/analytics/${DATE}.log
# Format: timestamp|type|topic|rounds|total_tokens|cost_usd|session_id

record_debate_analytics() {
    local debate_id="$1"
    local topic="$2"
    local rounds="$3"
    local total_tokens="$4"
    local total_cost="$5"
    local session_id="${CLAUDE_CODE_SESSION:-none}"

    local timestamp=$(date +%s)
    local date_str=$(date +%Y-%m-%d)
    local analytics_file="${HOME}/.claude-octopus/analytics/${date_str}.log"

    echo "$timestamp|debate|$topic|$rounds|$total_tokens|$total_cost|$session_id" >> "$analytics_file"
}
```

**Cost Warnings**:
- Before starting debate with > 5 rounds: "Estimated cost: $0.30-0.50. Continue? (y/n)"
- After each round: Show running total
- At synthesis: Display final cost breakdown

**Typical Costs** (based on default word limits):
- **Quick** (1 round): $0.02 - $0.05
- **Thorough** (3 rounds): $0.10 - $0.20
- **Adversarial** (5 rounds): $0.25 - $0.50
- **10-round debate**: $0.50 - $1.00

---

### 4. Document Export Integration

**Enhancement**: Export debate results to professional office formats using document-delivery skill (v7.3.0).

**Export Options**:

| Format | Best For | Generated From |
|--------|----------|----------------|
| **PPTX** | Stakeholder presentations | synthesis.md (consensus, recommendations) |
| **DOCX** | Detailed documentation | transcript.md (full debate record) |
| **PDF** | Archival/sharing | synthesis.md (final report) |
| **Markdown** | Developer handoff | transcript.md (original format) |

**Usage**:
```bash
# After debate completes
"Export this debate synthesis to PowerPoint"
→ Uses document-delivery skill
→ Generates slides: Summary, Consensus, Disagreements, Recommendations

"Create a Word document from the full transcript"
→ Exports transcript.md to DOCX
→ Formatted with headings, quotes, code blocks

"Convert to PDF for archival"
→ Generates PDF with metadata (topic, participants, date, cost)
```

**Integration with Knowledge Mode**:
```bash
# Strategic deliberation workflow
/claude-octopus:km on
/debate -r 3 -d collaborative "Should we enter European market?"

# After synthesis
"Export to PowerPoint for board meeting"
→ Professional deck with:
   - Executive summary
   - UX perspective (from ux-researcher persona)
   - Strategy perspective (from strategy-analyst persona)
   - Market data (from research-synthesizer persona)
   - Consensus recommendations
```

---

### 5. Enhanced Viewer Integration

**Enhancement**: Integrate debate viewer with claude-octopus session tracking.

**Original Viewer**: `.dependencies/claude-skills/viewer.html`

**Enhanced Viewer**: `viewer/debates-enhanced.html` (adds):
- Session filtering (filter debates by Claude Code session)
- Quality score badges (show response quality scores)
- Cost breakdown chart (visualize token usage and costs)
- Export buttons (quick export to PPTX/DOCX/PDF)
- Link to claude-octopus analytics

**Access**:
```bash
# After debate completes
open viewer/debates-enhanced.html

# Or use command
/debate-viewer
```

---

## Integration Commands

These commands are available when debate-integration skill is active:

### /debate (Original + Enhanced)

All original flags work, plus enhanced storage and tracking:

```bash
/debate <question>
/debate -r 3 -d thorough "Architecture decision"
/debate --rounds 5 --debate-style adversarial "Security review"
```

**What happens**:
1. Original debate.md skill executes core logic
2. Integration layer applies enhancements:
   - Session-aware storage path
   - Quality scoring after each round
   - Cost tracking throughout
   - Final synthesis with metrics

### /debate-export (New)

Export debate results to professional formats:

```bash
/debate-export <debate-id> --format pptx
/debate-export 042-redis-vs-memcached --format docx
/debate-export latest --format pdf
```

**Arguments**:
- `<debate-id>`: Debate folder name (e.g., `042-topic-slug`) or `latest`
- `--format`: Output format (`pptx`, `docx`, `pdf`, `md`)

### /debate-quality (New)

Show quality scores for debate responses:

```bash
/debate-quality <debate-id>

# Example output:
# Debate: 042-redis-vs-memcached
# Round 1:
#   Gemini: 85/100 (good length, citations, code examples)
#   Codex: 92/100 (excellent engagement, detailed examples)
#   Claude: 88/100 (strong synthesis, addresses both)
# Round 2:
#   Gemini: 78/100 (good, but brief on some points)
#   Codex: 95/100 (exceptional detail, multiple sources)
#   Claude: 91/100 (excellent moderation, new insights)
```

### /debate-cost (New)

Show cost breakdown for debate:

```bash
/debate-cost <debate-id>

# Example output:
# Debate: 042-redis-vs-memcached (3 rounds)
# Total Cost: $0.142
#
# Breakdown by Advisor:
#   Gemini (gemini-3-pro):
#     Tokens: 8,100 (3,200 input / 4,900 output)
#     Cost: $0.068
#   Codex (gpt-5.1-codex-max):
#     Tokens: 7,200 (2,800 input / 4,400 output)
#     Cost: $0.074
#
# Pricing (per million tokens):
#   gemini-3-pro: $2.50 input / $10.00 output
#   gpt-5.1-codex-max: $3.00 input / $15.00 output
```

### /debate-viewer (New)

Open enhanced debate viewer:

```bash
/debate-viewer

# Opens viewer/debates-enhanced.html in default browser
# Shows all debates with:
#   - Session filtering
#   - Quality scores
#   - Cost breakdown
#   - Export options
```

---

## Integration with Claude-Octopus Workflows

### Scenario 1: Optional Debate Phase in Double Diamond

```bash
# Full workflow with debate
orchestrate.sh embrace --with-debate "Should we implement caching?"

# Flow:
# 1. probe   → Research caching strategies (parallel agents)
# 2. grasp   → Define requirements (synthesis)
# 3. debate  → Multi-perspective consensus (Gemini vs Codex vs Claude)
# 4. tangle  → Implement agreed solution (quality gated)
# 5. ink     → Deliver and validate
```

**Value**: Structured debate ensures team alignment before implementation.

### Scenario 2: Adversarial Quality Gate (Enhanced grapple)

```bash
# Replace grapple with structured debate
orchestrate.sh grapple --use-debate "Review auth.ts for security"

# Roles:
#   Gemini: Defend the code (find strengths)
#   Codex: Attack the code (find vulnerabilities)
#   Claude: Moderate and synthesize critical issues

# Uses adversarial style (5 rounds)
# Quality gates prevent proceeding if consensus < 75%
```

**Value**: More thorough security review than simple back-and-forth.

### Scenario 3: Knowledge Mode Deliberation

```bash
# Strategic decision-making
/claude-octopus:km on
/debate -r 3 -d collaborative "Should we enter European market?"

# Personas (from knowledge mode):
#   - ux-researcher: User needs and cultural considerations
#   - strategy-analyst: Market analysis, competitive landscape
#   - research-synthesizer: GDPR, regulatory requirements

# After synthesis:
"Export this deliberation to PowerPoint"
→ Professional deck for board presentation
```

**Value**: Combines domain expertise with structured debate + deliverable output.

---

## Environment Variables

The integration layer uses these environment variables:

```bash
# Claude Code session (auto-set by Claude Code CLI)
CLAUDE_CODE_SESSION="session-uuid"

# Claude-octopus debate mode flag (auto-set when debate runs)
CLAUDE_OCTOPUS_DEBATE_MODE="true"

# Session-aware debate directory (computed)
DEBATE_BASE_DIR="${HOME}/.claude-octopus/debates/${CLAUDE_CODE_SESSION}"

# Quality gate threshold (default: 50)
DEBATE_QUALITY_THRESHOLD="${DEBATE_QUALITY_THRESHOLD:-50}"

# Cost warning threshold (default: $0.30)
DEBATE_COST_WARNING="${DEBATE_COST_WARNING:-0.30}"
```

---

## File Structure

When running debates in claude-octopus:

```
~/.claude-octopus/
├── debates/${SESSION_ID}/
│   └── NNN-topic-slug/
│       ├── context.md              # Initial configuration
│       ├── state.json              # Session tracking + cost data
│       ├── transcript.md           # Full debate (generated)
│       ├── synthesis.md            # Final analysis (generated)
│       ├── quality-scores.json     # NEW: Response quality metrics
│       └── rounds/
│           ├── r001_gemini.md
│           ├── r001_codex.md
│           ├── r001_claude.md
│           ├── r002_gemini.md
│           └── ...
├── analytics/${DATE}.log           # Usage tracking
└── results/${SESSION_ID}/          # Other session results
```

**Enhanced state.json**:
```json
{
  "debate_id": "042-redis-vs-memcached",
  "topic": "Should we use Redis or in-memory cache?",
  "status": "completed",
  "current_round": 3,
  "total_rounds": 3,
  "sessions": {
    "gemini": { "id": "uuid", "status": "active", "tokens": 8100 },
    "codex": { "id": "uuid", "status": "active", "tokens": 7200 }
  },
  "quality_scores": {
    "round_1": { "gemini": 85, "codex": 92, "claude": 88 },
    "round_2": { "gemini": 78, "codex": 95, "claude": 91 },
    "round_3": { "gemini": 82, "codex": 89, "claude": 93 }
  },
  "cost_tracking": {
    "total_cost_usd": 0.142,
    "by_advisor": { /* ... */ }
  },
  "metadata": {
    "claude_code_session": "session-uuid",
    "created_at": "2026-01-18T06:15:00Z",
    "completed_at": "2026-01-18T06:32:00Z",
    "duration_seconds": 1020
  }
}
```

---

## Best Practices

### 1. Choose Appropriate Debate Style

Match debate style to decision importance:

| Decision Type | Recommended Style | Rounds | Estimated Cost |
|---------------|-------------------|--------|----------------|
| **Exploratory** | quick | 1 | $0.02-0.05 |
| **Important** | thorough | 3 | $0.10-0.20 |
| **Critical** | adversarial | 5 | $0.25-0.50 |
| **Team alignment** | collaborative | 2-3 | $0.08-0.15 |

### 2. Set Quality Expectations

For high-stakes debates, raise quality threshold:

```bash
export DEBATE_QUALITY_THRESHOLD=75

/debate -r 5 -d adversarial "Security review: auth.ts"
```

### 3. Export for Stakeholders

Knowledge work debates should be exported:

```bash
/claude-octopus:km on
/debate -r 3 "Strategic decision"

# After synthesis
"Export to PowerPoint for leadership team"
```

### 4. Track Costs for Budgeting

Monitor debate analytics:

```bash
# Monthly debate costs
grep "^.*|debate|" ~/.claude-octopus/analytics/2026-01-*.log | \
  awk -F'|' '{sum+=$6} END {print "Total: $"sum}'
```

---

## Troubleshooting

### Issue: Submodule Not Found

**Symptom**: `/debate` command fails with "AI Debate Hub not found"

**Solution**:
```bash
cd /path/to/claude-octopus
git submodule update --init --recursive
```

### Issue: Quality Scores Too Strict

**Symptom**: Advisors constantly re-prompted for elaboration

**Solution**: Lower quality threshold
```bash
export DEBATE_QUALITY_THRESHOLD=40
```

### Issue: Cost Warnings Too Frequent

**Symptom**: Warning prompts before every debate

**Solution**: Raise cost warning threshold
```bash
export DEBATE_COST_WARNING=0.50  # Warn only if > $0.50
```

### Issue: Debates Not Showing in Viewer

**Symptom**: Enhanced viewer shows no debates

**Solution**: Check debate base directory
```bash
ls -la ~/.claude-octopus/debates/${CLAUDE_CODE_SESSION}/
# If empty, check original location:
ls -la ./debates/
```

---

## Contributing Enhancements Upstream

This integration layer is claude-octopus specific, but **generic improvements** should be contributed to wolverin0/claude-skills:

**Upstream Contributions** (submit to wolverin0):
- Atomic state writes (file locking)
- Retry logic with exponential backoff
- Enhanced error handling
- Session timeout improvements
- Bug fixes

**Claude-Octopus Specific** (keep in this layer):
- Session-aware storage paths
- Integration with claude-octopus quality gates
- Document-delivery skill export
- Knowledge mode persona mapping
- Analytics integration

**How to Contribute**:
1. Fork wolverin0/claude-skills
2. Create branch for enhancement
3. Test thoroughly
4. Submit PR with clear description
5. Reference this integration in PR description

---

## Version Compatibility

| Component | Version | Compatibility |
|-----------|---------|---------------|
| **AI Debate Hub** | v4.7 | ✅ Fully compatible |
| **claude-octopus** | v7.4.0 | ✅ This version |
| **document-delivery** | v7.3.0+ | ✅ Required for export |
| **knowledge-mode** | v7.2.0+ | ✅ Required for deliberate |
| **Claude Code** | v2.1.10+ | ✅ Required for session IDs |

---

## License & Attribution

**Original Skill**:
- AI Debate Hub by wolverin0
- License: MIT
- Repository: https://github.com/wolverin0/claude-skills

**Integration Layer**:
- Claude-Octopus by nyldn
- License: MIT
- Repository: https://github.com/nyldn/claude-octopus

Both components are open source and contributions are welcome.

---

*AI Debate Hub Integration for claude-octopus v7.4.0+*
*Original skill by wolverin0 - Enhanced for production workflows*
