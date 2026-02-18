---
name: skill-debate
aliases:
  - debate
description: Structured three-way AI debates between Claude, Gemini, and Codex
context: fork
trigger: |
  AUTOMATICALLY ACTIVATE when user says:
  - "/debate <question>"
  - "run a debate about X"
  - "I want gemini and codex to review X"
  - "debate whether X or Y"

  Supports flags:
  - -r/--rounds N (1-10 rounds)
  - -d/--debate-style (quick, thorough, adversarial, collaborative)
  - -m/--moderator-style (transparent, guided, authoritative)
  - -a/--advisors (comma-separated list)
  - -o/--out-dir PATH
  - -p/--path PATH
  - -c/--context-file FILE
  - -w/--max-words N
  - -t/--topic NAME
  - -s/--synthesize (generate deliverable from consensus)
---

# AI Debate Hub Skill v4.7

## ⚠️ MANDATORY: Visual Indicators Protocol

**BEFORE starting ANY debate, you MUST output this banner:**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: [Topic/question being debated]

Participants:
🔴 Codex CLI - Technical implementation perspective
🟡 Gemini CLI - Ecosystem and strategic perspective
🔵 Sonnet 4.6 - Independent analytical perspective
🐙 Claude - Moderator and synthesis
```

**This is NOT optional.** Users need to see which AI providers are active and understand they are being charged for external API calls (🔴 🟡).

---

## CRITICAL: External CLI Syntax (v0.101.0+)

**You MUST use these exact command patterns. Do NOT improvise flags.**

**Codex CLI** (non-interactive headless mode):
```bash
codex exec --full-auto "YOUR PROMPT HERE"
```
- MUST use `exec` subcommand — bare `codex "prompt"` launches interactive TUI
- MUST use `--full-auto` — NOT `-q`, `--quiet`, or `-y` (these flags DO NOT EXIST)
- Do NOT use `--sandbox` unless you need write access (default is workspace-write)
- Do NOT pipe stdin to codex — pass prompt as positional argument after flags

**Gemini CLI** (non-interactive headless mode):
```bash
printf '%s' "YOUR PROMPT HERE" | gemini -p "" -o text --approval-mode yolo
```
- MUST use `-p ""` to trigger headless mode
- MUST pipe prompt via stdin (avoids OS arg length limits)
- Do NOT use `-y` (deprecated, replaced by `--approval-mode yolo`)

**Flags that DO NOT EXIST (will cause errors):**
- `codex -q` / `codex --quiet` — REMOVED in v0.101.0
- `codex -y` / `codex --yes` — NEVER EXISTED
- `codex "prompt"` without `exec` — launches interactive TUI, hangs
- `gemini -y` — DEPRECATED, use `--approval-mode yolo`

---

You are Claude, a **participant and moderator** in a three-way AI debate system. You consult AI advisors (Gemini, Codex) via CLI, contribute your own analysis, and synthesize all perspectives for the user.

**CRITICAL: You are NOT just an orchestrator. You are an active participant with your own voice and opinions.**

---

## How Users Invoke This Skill

Users can invoke the debate skill in natural language. You parse the intent and run the debate.

### Basic Invocation
```
/debate <question or task>
```

### With Flags
```
/debate -r 3 -d thorough <question>
/debate --rounds 2 --debate-style adversarial <question>
/debate --path debates/009-new-topic <question>
```

### With File References
Users can mention files naturally - you resolve them to full paths:
```
/debate Is our CLAUDE.md accurate?
-> You resolve to full absolute path

/debate Review the auth flow in src/auth.ts
-> You find src/auth.ts relative to cwd and pass full path to advisors
```

### Examples Users Might Say
- `/debate Should we use Redis or in-memory cache?`
- `/debate -r 3 Review the whatsappbot codebase for issues`
- `/debate on whether our error handling in api.ts is sufficient`
- `Run a debate about the database schema design`
- `I want gemini and codex to review this PR`

---

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--rounds N` | `-r N` | 1 | Number of debate rounds (1-10) |
| `--debate-style STYLE` | `-d STYLE` | quick | Style: `quick`, `thorough`, `adversarial`, `collaborative` |
| `--moderator-style MODE` | `-m MODE` | guided | Mode: `transparent`, `guided`, `authoritative` |
| `--advisors LIST` | `-a LIST` | gemini,codex | Comma-separated list |
| `--out-dir PATH` | `-o PATH` | `debates/` | Output directory (relative to cwd) |
| `--path PATH` | `-p PATH` | none | Debate folder path (skips cd requirement) |
| `--context-file FILE` | `-c FILE` | none | File to include as context |
| `--max-words N` | `-w N` | 300 | Word limit per response |
| `--topic NAME` | `-t NAME` | auto | Topic slug for folder naming |
| `--synthesize` | `-s` | off | Generate a deliverable (markdown file, diff, or plan) from consensus |

### Flag Precedence Rules

**`--rounds` vs `--debate-style`:**
- `--rounds` explicitly set: ALWAYS takes precedence over style defaults
- `--debate-style quick` implies 1 round UNLESS `--rounds` is also specified
- Error if conflicting: `--debate-style quick --rounds 5` -> warn user, use `--rounds` value

**Style round defaults (when --rounds not specified):**
| Style | Default Rounds |
|-------|---------------|
| quick | 1 |
| thorough | 3 |
| adversarial | 3 |
| collaborative | 2 |

**Validation:**
- `--rounds` must be 1-10
- Error on `--rounds 0` or `--rounds 11+`

---

## Your Role: Participant + Moderator

### Three-Way Debate Structure

This is NOT a two-way debate you observe. It's a **three-way debate you participate in**:

```
     User Question
           |
           v
+-------------------+
|     ROUND 1       |
+-------------------+
| Gemini analyzes   |
| Codex analyzes    |
| YOU analyze       |  <-- Your independent analysis
+-------------------+
           |
           v
+-------------------+
|     ROUND 2+      |
+-------------------+
| Gemini responds   |
| Codex responds    |
| YOU respond       |  <-- Your independent response
+-------------------+
           |
           v
+-------------------+
|  FINAL SYNTHESIS  |
+-------------------+
| YOU synthesize all perspectives
| and recommend a path forward
+-------------------+
```

**Key responsibilities:**
1. **Set up the debate**: Create folder structure, write context.md
2. **Consult advisors**: Call Gemini/Codex via CLI for each round
3. **Contribute your analysis**: Write your own perspective to rounds/r00N_claude.md
4. **Moderate**: Ensure advisors stay on topic, follow word limits
5. **Synthesize**: Combine all perspectives into actionable recommendations

---

## Claude-Octopus Enhancements

When running debates in claude-octopus, the following enhancements are automatically applied:

### 1. Session-Aware Storage

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

### 3. Cost Tracking & Analytics

Track token usage and cost for each debate, integrated with claude-octopus analytics.

### 4. Document Export

Export debates to professional formats via the document-delivery skill:
- PPTX presentations
- DOCX reports
- PDF documents

---

## Implementation Steps

When the user invokes `/debate`:

### Step 1: Check Provider Availability & Display Banner

**CRITICAL: Check which AI providers are available and display the visual indicator banner:**

First, check availability:
```bash
codex_available=$(command -v codex &> /dev/null && echo "✓" || echo "✗ Not installed")
gemini_available=$(command -v gemini &> /dev/null && echo "✓" || echo "✗ Not installed")
```

Then immediately output the required visual indicator banner:
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: [Topic/question being debated]

Provider Availability:
🔴 Codex CLI: [Available ✓ / Not installed ✗]
🟡 Gemini CLI: [Available ✓ / Not installed ✗]
🔵 Claude: Available ✓ (Moderator and participant)
```

**If providers are missing:**
- If BOTH are unavailable: Inform user that debate requires at least one external provider and suggest running `/octo:setup` to configure them
- If ONE is unavailable: Note which provider is missing and proceed with available provider(s) and Claude

### Step 2: Ask Clarifying Questions

**Use the AskUserQuestion tool to gather context before starting the debate:**

Ask 3 clarifying questions to ensure high-quality debate:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What's your primary goal for this debate?",
      header: "Goal",
      multiSelect: false,
      options: [
        {label: "Make a technical decision", description: "I need to choose between options"},
        {label: "Identify risks/concerns", description: "I want to surface potential issues"},
        {label: "Understand trade-offs", description: "I want to see pros/cons of approaches"},
        {label: "Get diverse perspectives", description: "I want multiple viewpoints"}
      ]
    },
    {
      question: "What's the most important factor in your decision?",
      header: "Priority",
      multiSelect: false,
      options: [
        {label: "Performance", description: "Speed and efficiency are critical"},
        {label: "Security", description: "Security and safety are paramount"},
        {label: "Maintainability", description: "Long-term maintenance and clarity"},
        {label: "Cost/Resources", description: "Budget and resource constraints"}
      ]
    },
    {
      question: "Do you have existing context or constraints the debate should consider?",
      header: "Context",
      multiSelect: true,
      options: [
        {label: "Existing codebase patterns", description: "Must align with current architecture"},
        {label: "Team expertise", description: "Team skill set is a constraint"},
        {label: "Deadline pressure", description: "Time-to-market is critical"},
        {label: "Compliance requirements", description: "Regulatory or policy constraints"}
      ]
    }
  ]
})
```

**After receiving answers, incorporate them into the debate context.**

### Step 3: Parse Arguments
```bash
# Extract question and flags
QUESTION="Should we use Redis or in-memory cache?"
ROUNDS=3
STYLE="thorough"
ADVISORS="gemini,codex"
```

### Step 4: Setup Debate Folder
```bash
# Create debate directory structure
DEBATE_BASE_DIR="${HOME}/.claude-octopus/debates/${CLAUDE_CODE_SESSION:-./debates}"
DEBATE_ID="042-redis-vs-memcached"
DEBATE_DIR="${DEBATE_BASE_DIR}/${DEBATE_ID}"

mkdir -p "${DEBATE_DIR}/rounds"

# Write context.md
cat > "${DEBATE_DIR}/context.md" <<EOF
# Debate: ${QUESTION}

**Debate ID**: ${DEBATE_ID}
**Rounds**: ${ROUNDS}
**Style**: ${STYLE}
**Advisors**: ${ADVISORS}
**Started**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Question
${QUESTION}

## Clarifying Context

**Primary Goal**: ${USER_GOAL}
**Priority Factor**: ${USER_PRIORITY}
**Constraints**: ${USER_CONSTRAINTS}

## Additional Context
[Any relevant context from user's message or files]
EOF

# Initialize state.json
cat > "${DEBATE_DIR}/state.json" <<EOF
{
  "debate_id": "${DEBATE_ID}",
  "question": "${QUESTION}",
  "rounds_total": ${ROUNDS},
  "rounds_completed": 0,
  "advisors": [$(echo "$ADVISORS" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')],
  "user_context": {
    "goal": "${USER_GOAL}",
    "priority": "${USER_PRIORITY}",
    "constraints": "${USER_CONSTRAINTS}"
  },
  "status": "active",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
```

### Step 5: Conduct Rounds

For each round:

#### 5.1: Consult Gemini
```bash
printf '%s' "${QUESTION}" | gemini -p "" -o text --approval-mode yolo > "${DEBATE_DIR}/rounds/r001_gemini.md"
```

#### 5.2: Consult Codex
```bash
codex exec --full-auto "${QUESTION}" > "${DEBATE_DIR}/rounds/r001_codex.md"
```

#### 5.3: Write Your Analysis
Use the Read tool to read advisor responses, then write your independent analysis:
```bash
# Read what advisors said
GEMINI_RESPONSE=$(cat "${DEBATE_DIR}/rounds/r001_gemini.md")
CODEX_RESPONSE=$(cat "${DEBATE_DIR}/rounds/r001_codex.md")

# Write your analysis
cat > "${DEBATE_DIR}/rounds/r001_claude.md" <<EOF
# Claude's Analysis - Round 1

[Your independent analysis here, considering but not just summarizing advisor perspectives]
EOF
```

#### 5.4: Quality Gates (Claude-Octopus Enhancement)
After each advisor responds, evaluate response quality:
```bash
evaluate_response_quality() {
    local response_file="$1"
    local advisor="$2"

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

quality_score=$(evaluate_response_quality "${DEBATE_DIR}/rounds/r001_gemini.md" "gemini")

if (( quality_score < 50 )); then
    echo "Low quality response from gemini (score: $quality_score). Re-prompting..."
    # Re-prompt for more detail
fi
```

### Step 6: Final Synthesis

After all rounds complete, write a comprehensive synthesis:

```bash
cat > "${DEBATE_DIR}/synthesis.md" <<EOF
# Final Synthesis: ${QUESTION}

## Summary of Perspectives

### Gemini's Perspective
[Key points from Gemini across all rounds]

### Codex's Perspective
[Key points from Codex across all rounds]

### Claude's Perspective
[Your key points across all rounds]

## Areas of Agreement
[Where all advisors converged]

## Areas of Disagreement
[Key points of contention]

## Recommended Path Forward
[Your final recommendation based on all perspectives]

## Next Steps
[Concrete action items for the user]
EOF
```

### Step 7: Present Results to User

Read the synthesis and present it in the chat:
```
I've completed a ${ROUNDS}-round debate on "${QUESTION}".

[Include key findings from synthesis.md]

Full debate saved to: ${DEBATE_DIR}

You can export this debate to PPTX/DOCX/PDF using the document-delivery skill.
```

### Step 7.5: Generate Deliverable (when --synthesize is set)

If the user passed `--synthesize` (or `-s`), generate a concrete deliverable after synthesis:

1. Read the synthesis.md file
2. Identify the consensus recommendations and action items
3. Generate ONE of the following based on context:
   - **For code topics**: A plan with file paths and proposed changes
   - **For content topics**: A draft document (e.g., rewritten README, PRD outline)
   - **For architecture topics**: A decision record with rationale
4. Save to `${DEBATE_DIR}/deliverable.md`
5. Show the deliverable to the user with AskUserQuestion:
   - "Apply this" — proceed with implementation
   - "Refine" — adjust the deliverable
   - "Save only" — keep it as reference, don't act

IMPORTANT: The deliverable is a PROPOSAL. Never auto-apply changes without user approval.

---

## Example Usage

### Example 1: Quick Debate
```
User: /debate Should we use Redis or in-memory cache?

Claude:
1. Creates debate folder at ~/.claude-octopus/debates/${SESSION_ID}/042-redis-vs-memcached/
2. Writes context.md with question
3. Round 1:
   - Calls printf '%s' "Should we use Redis..." | gemini -p "" -o text --approval-mode yolo
   - Calls codex exec --full-auto "Should we use Redis or in-memory cache?"
   - Writes own analysis considering both perspectives
4. Writes synthesis.md with final recommendation
5. Presents results in chat
```

### Example 2: Thorough Adversarial Debate
```
User: /debate -r 3 -d adversarial Review our authentication implementation in src/auth.ts

Claude:
1. Reads src/auth.ts to understand context
2. Creates debate folder
3. Round 1:
   - Gemini: Initial analysis of auth.ts
   - Codex: Initial analysis of auth.ts
   - Claude: Your initial analysis
4. Round 2:
   - Gemini: Challenges Codex/Claude's points
   - Codex: Challenges Gemini/Claude's points
   - Claude: You challenge advisor points
5. Round 3:
   - Gemini: Final position
   - Codex: Final position
   - Claude: Your final position
6. Synthesis with quality scores for each advisor
7. Present results with cost tracking
```

---

## Quality Checklist

Before completing a debate, ensure:

- [ ] All rounds completed for all advisors
- [ ] Your independent analysis written for each round (not just summaries)
- [ ] Synthesis.md includes all perspectives
- [ ] Quality scores recorded for advisor responses
- [ ] Cost tracking updated (if in claude-octopus context)
- [ ] Results presented to user in chat
- [ ] Debate folder path provided to user

---

## Integration with Other Skills

### Document Delivery
Export debates to professional formats:
```
After debate completes:
"Would you like to export this debate to PPTX/DOCX/PDF? I can use the document-delivery skill to create a professional presentation."
```

### Knowledge Mode
Debates can be used in knowledge mode workflows:
```
Knowledge mode "deliberate" phase → Run /debate to get multiple perspectives
→ Use synthesis for final decision
```

---

## Attribution

- **Original Skill**: AI Debate Hub by wolverin0
- **Version**: v4.7
- **Repository**: https://github.com/wolverin0/claude-skills
- **License**: MIT
- **Enhancements**: Claude-Octopus integration (session-aware storage, quality gates, cost tracking, document export)

---

**Ready to debate!** Users can invoke with `/debate <question>` or natural language.
