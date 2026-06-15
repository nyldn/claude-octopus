---
name: skill-debate
effort: high
user-invocable: true
aliases:
  - debate
description: Structured multi-provider AI debates between Claude and available advisors — use for critical decisions
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

# AI Debate Hub Skill v4.8

## MANDATORY COMPLIANCE — DO NOT SKIP

**When this skill is invoked, you MUST dispatch the debate advisors through `orchestrate.sh` and synthesize their positions. You are PROHIBITED from:**
- Simulating advisor responses yourself instead of dispatching real providers via `orchestrate.sh`
- Deciding the question is "too simple" and answering single-model without the multi-provider debate
- Skipping the provider availability check or the structured rounds
- Dropping an available advisor (including `agy`) from the roster without telling the user
- Rationalizing that one model's view is sufficient — the user invoked a debate for multiple perspectives


## ⚠️ MANDATORY: Visual Indicators Protocol

**BEFORE starting ANY debate, you MUST output this banner:**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: [Topic/question being debated]

Participants:
🔴 Codex CLI - Technical implementation perspective
🟡 Gemini CLI - Ecosystem and strategic perspective
🟠 Sonnet 4.6 - Pragmatic implementer perspective
🐙 Claude (Opus) - Moderator and synthesis
🟢 Copilot CLI - GitHub-native perspective (if available)
🟤 Qwen CLI - Alternative model perspective (if available)
```

**Core participants are selected from available providers.** Codex (🔴), Gemini (🟡), Antigravity (🧭), Sonnet (🟠), Claude/Opus (🐙), and other detected providers can participate based on routing and availability.

**This is NOT optional.** Users need to see which AI providers are active. External API calls (🔴 🟡) use provider API keys. Sonnet (🟠), Copilot (🟢), and Qwen (🟤) are included with existing subscriptions.

---

## CRITICAL: External CLI Syntax (v0.101.0+)

**You MUST use this exact command pattern. Do NOT improvise provider flags.**

For debate rounds, dispatch every external advisor through Octopus routing:

```bash
"${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" spawn "$advisor" "$prompt"
```

Do not call provider CLIs directly from the debate workflow. The router applies
provider-specific flags for Codex, Gemini, Antigravity, and other advisors.

- Provider-specific syntax lives in `scripts/lib/dispatch.sh` and helper scripts.
- Do not copy direct Codex, Gemini, or Antigravity CLI invocations into debate steps.
- Always pass the selected advisor name to `orchestrate.sh spawn`; the router chooses the correct command.

**Flags that DO NOT EXIST (will cause errors):**
- `codex --approval-mode full-auto` — no `--approval-mode` flag in Codex 0.130.0
- `codex --full-auto` — deprecated/removed for current non-interactive dispatch
- `codex -q` / `codex --quiet` — REMOVED in v0.101.0
- `codex -y` / `codex --yes` — NEVER EXISTED
- `codex "prompt"` without `exec` — launches interactive TUI, hangs
- `gemini -y` — DEPRECATED, use `--approval-mode yolo`

---

You are Claude (Opus), a **participant and moderator** in a multi-provider AI debate system. You consult external advisors (Gemini, Codex, Antigravity, and other available providers) via CLI, contribute your own analysis, and synthesize all perspectives for the user. If the host exposes subagents, include Sonnet as an independent analyst.

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
| `--advisors LIST` | `-a LIST` | auto | Comma-separated list |
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

### Multi-Provider Debate Structure

This is a **provider debate** with selected advisor voices plus you as moderator:

```
     User Question
           |
           v
+-------------------+
|     ROUND 1       |
+-------------------+
| Gemini analyzes   |  🟡 External CLI
| Codex analyzes    |  🔴 External CLI
| Sonnet analyzes   |  🟠 Agent(model: sonnet)
| YOU analyze       |  🐙 Your independent analysis (Opus)
+-------------------+
           |
           v
+-------------------+
|     ROUND 2+      |
+-------------------+
| Gemini responds   |  🟡 Sees prior round
| Codex responds    |  🔴 Sees prior round
| Sonnet responds   |  🟠 Sees prior round
| YOU respond       |  🐙 Your independent response
+-------------------+
           |
           v
+-------------------+
|  FINAL SYNTHESIS  |
+-------------------+
| YOU synthesize all four perspectives
| and recommend a path forward
+-------------------+
```

**Key responsibilities:**
1. **Set up the debate**: Create folder structure, write context.md
2. **Consult external advisors**: Call Gemini/Codex via CLI for each round
3. **Launch Sonnet**: Dispatch Sonnet via Agent tool (run_in_background) for each round
4. **Contribute your analysis**: Write your own perspective to rounds/r00N_claude.md
5. **Moderate**: Ensure advisors stay on topic, follow word limits
6. **Synthesize**: Combine all four perspectives into actionable recommendations

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

**MANDATORY: You MUST use the Bash tool to run this provider check BEFORE displaying the banner. Do NOT skip it. Do NOT assume availability.**
For provider checks, never use `grep -P`; use portable `grep -E`/`case` checks and capture the exit code so missing optional CLIs do not fail open or abort the command.

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/helpers/check-providers.sh"
```

**Use the ACTUAL results below. PROHIBITED: Showing only "🔵 Claude: Available ✓" without listing all providers.**

Then display the banner with real provider status:
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: [Topic/question being debated]

Provider Availability:
🔴 Codex CLI: [Available ✓ / Not installed ✗]
🟡 Gemini CLI: [Available ✓ / Not installed ✗]
🧭 Antigravity CLI: [Available ✓ / Not installed ✗]
🟠 Sonnet 4.6: Available ✓ (via Agent tool — no extra cost)
🐙 Claude (Opus): Available ✓ (Moderator and participant)
```

**If providers are missing:**
- If all external providers are unavailable: Inform user that debate requires at least one external provider and suggest running `/octo:setup` to configure them
- If one or more providers are unavailable: Note which providers are missing and proceed with available provider(s) and Claude

### Step 2: Ask Clarifying Questions

**Use the AskUserQuestion tool to gather context before starting the debate:**

Ask 4 clarifying questions to ensure high-quality debate:

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
      question: "How should the AI models evaluate the topic?",
      header: "Evaluation",
      multiSelect: false,
      options: [
        {label: "Cross-critique (Recommended)", description: "Models challenge each other's proposals directly — deeper analysis but may anchor on first responses"},
        {label: "Independent evaluation", description: "Models evaluate independently without seeing others' work — prevents groupthink and anchoring bias"}
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

**After receiving answers:**
- If user selected "Cross-critique": use `--mode cross-critique` (default ACH falsification)
- If user selected "Independent evaluation": use `--mode blinded` (no cross-contamination)
- Incorporate all other answers into the debate context.

### Step 3: Parse Arguments & Build Debate Fleet
```bash
# Extract question and flags
QUESTION="Should we use Redis or in-memory cache?"
ROUNDS=3
STYLE="thorough"

# Dynamic advisor selection — use build-fleet.sh for model family diversity
DEBATE_FLEET=$("${HOME}/.claude-octopus/plugin/scripts/helpers/build-fleet.sh" debate standard "${QUESTION}" 2>/dev/null)
# Extract debater agent types (exclude claude-sonnet Moderator)
ADVISORS=$(echo "$DEBATE_FLEET" | grep '|Debater|' | cut -d'|' -f1 | paste -sd',' -)
# Fallback if build-fleet.sh unavailable: use installed providers, including agy.
if [[ -z "$ADVISORS" ]]; then
  fallback_advisors=()
  command -v codex >/dev/null 2>&1 && fallback_advisors+=(codex)
  command -v agy >/dev/null 2>&1 && fallback_advisors+=(agy)
  command -v gemini >/dev/null 2>&1 && fallback_advisors+=(gemini)
  ADVISORS=$(IFS=,; echo "${fallback_advisors[*]}")
fi
```

**The `build-fleet.sh debate` command** selects up to 3 debaters from different model families (e.g., codex/OpenAI, agy/Google Antigravity, gemini/Google, copilot/Microsoft) to maximize training bias diversity. Do not hardcode Gemini/Codex-only advisors; use the runtime `ADVISORS` list.

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
[If claude-mem is installed, search for past debates or decisions on this topic using its MCP tools]
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

For each round, iterate the runtime advisor list and dispatch through Octopus:

```bash
IFS=',' read -r -a ADVISOR_LIST <<< "$ADVISORS"
for advisor in "${ADVISOR_LIST[@]}"; do
  case "$advisor" in
    claude*|codex*|gemini*|agy*|antigravity|copilot*|qwen*|opencode*|ollama*|cursor-agent*|vibe*) ;;
    *) echo "Skipping unsupported advisor: $advisor"; continue ;;
  esac
  safe_advisor=$(printf '%s' "$advisor" | tr -c '[:alnum:]_-' '_')
  "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" spawn "$advisor" \
    "You are ${advisor} participating in debate round 1.

DEBATE QUESTION: ${QUESTION}

${CONTEXT}

Write a concise, independent analysis (${MAX_WORDS} words). Address implementation tradeoffs, risks, and where other likely perspectives may be wrong." \
    > "${DEBATE_DIR}/rounds/r001_${safe_advisor}.md" &
done
wait
```

#### 5.2: Launch Sonnet (Pragmatic Implementer)

Dispatch Sonnet via the Agent tool with `model: "sonnet"` and `run_in_background: true` when the host exposes subagents. Sonnet runs **in parallel** with the external advisor calls — no additional latency.

```
Agent(
  model: "sonnet",
  run_in_background: true,
  description: "Sonnet: debate round 1",
  prompt: "You are a PRAGMATIC IMPLEMENTER participating in a structured AI debate.
YOUR ROLE: You are the person who would actually have to BUILD this. You care about what ships, what works, and what you'll be debugging at 2am. Ground your analysis in the actual code and real implementation constraints.

DEBATE QUESTION: ${QUESTION}

${CONTEXT}

Write your analysis (${MAX_WORDS} words) to: ${DEBATE_DIR}/rounds/r001_sonnet.md

Cover: implementation feasibility, hidden gotchas, concrete effort estimates, and what the other approaches miss from a builder's perspective."
)
```

**WHY Sonnet and not just more Opus?** Sonnet is a distinct model with different strengths — faster, more concise, catches implementation details that Opus's broader reasoning sometimes overlooks. Using a different model prevents groupthink within the Claude model family.

**Timing**: Launch Sonnet BEFORE or IN PARALLEL with the external advisor calls. By the time the CLI calls return, Sonnet is usually done too. Check for completion before proceeding to 5.3.

#### 5.3: Write Your Analysis (Opus)
Use the Read tool to read all advisor responses, then write your independent analysis:
```bash
# Read what all advisors said
for response_file in "${DEBATE_DIR}"/rounds/r001_*.md; do
  printf '\n## %s\n' "$(basename "$response_file" .md)"
  cat "$response_file"
done

# Write your analysis as moderator
cat > "${DEBATE_DIR}/rounds/r001_claude.md" <<EOF
# Claude (Opus) Analysis - Round 1

[Your independent analysis here, considering but not just summarizing the three advisor perspectives. Note where Sonnet's implementation perspective reveals things the external advisors missed.]
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
    addresses_others=$(grep -ciE '(gemini|codex|agy|antigravity|claude|sonnet)' "$response_file" || echo 0)

    score=0
    (( word_count >= 50 && word_count <= 1000 )) && (( score += 25 ))
    (( has_citations > 0 )) && (( score += 25 ))
    (( has_code > 0 )) && (( score += 25 ))
    (( addresses_others > 0 )) && (( score += 25 ))

    echo "$score"
}

for response_file in "${DEBATE_DIR}"/rounds/r001_*.md; do
    advisor=$(basename "$response_file" .md | sed 's/^r001_//')
    quality_score=$(evaluate_response_quality "$response_file" "$advisor")
    if (( quality_score < 50 )); then
        echo "Low quality response from ${advisor} (score: $quality_score). Re-prompting..."
        # Re-prompt for more detail
    fi
done
```

### Step 6: Final Synthesis

After all rounds complete, write a comprehensive synthesis:

```bash
cat > "${DEBATE_DIR}/synthesis.md" <<EOF
# Final Synthesis: ${QUESTION}

## Summary of Perspectives

### External Advisor Perspectives
[Key points from each advisor selected in ADVISORS: Codex, Gemini, Antigravity, or other available providers]

### 🟠 Sonnet's Perspective
[Key points from Sonnet across all rounds — especially implementation feasibility and gotchas]

### 🐙 Claude (Opus) Perspective
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
   - Launches Sonnet via Agent(model: sonnet, run_in_background: true) — pragmatic implementer
   - Calls orchestrate.sh spawn for each runtime advisor selected by build-fleet.sh, such as codex and agy when Gemini is not installed
   - Waits for Sonnet completion
   - Writes own analysis (Opus) considering all advisor perspectives
4. Writes synthesis.md with final recommendation from all participants
5. Presents results in chat
```

### Example 2: Thorough Adversarial Debate
```
User: /debate -r 3 -d adversarial Review our authentication implementation in src/auth.ts

Claude:
1. Reads src/auth.ts to understand context
2. Creates debate folder
3. Round 1 (Sonnet launched in background first, then selected external advisors in parallel):
   - 🟠 Sonnet: Implementation feasibility analysis of auth.ts
   - External advisors selected by build-fleet.sh, such as 🔴 Codex, 🧭 Antigravity, or 🟡 Gemini depending on availability
   - 🐙 Claude (Opus): Your independent analysis considering all advisors
4. Round 2:
   - 🟠 Sonnet: Responds to other participants' points
   - External advisors challenge each other's points
   - 🐙 Claude: You challenge advisor points
5. Round 3:
   - All participants: Final positions
6. Synthesis with quality scores for each advisor
7. Present results with cost tracking
```

---

## Quality Checklist

Before completing a debate, ensure:

- [ ] All rounds completed for selected participants
- [ ] Your independent analysis (Opus) written for each round (not just summaries)
- [ ] Synthesis.md includes all participating perspectives
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

## Quality Gates for Responses

Each advisor response is scored before proceeding:

| Metric | Weight | Criteria |
|--------|--------|----------|
| Length | 25 pts | 50-1000 words (substantive but concise) |
| Citations | 25 pts | References, links, or sources present |
| Code Examples | 25 pts | Technical examples or code snippets |
| Engagement | 25 pts | Addresses other advisors' specific points |

Score >= 75: proceed. Score 50-74: proceed with warning. Score < 50: re-prompt for elaboration.

## Cost Tracking

Typical costs (default word limits):
- Quick (1 round): $0.02 - $0.05
- Thorough (3 rounds): $0.10 - $0.20
- Adversarial (5 rounds): $0.25 - $0.50

Cost tracking integrates with `~/.claude-octopus/analytics/` logs.

## Export

After debate completes, export results via document-delivery skill:
- PPTX: stakeholder presentations from synthesis
- DOCX: detailed documentation from full transcript
- PDF: archival with metadata (topic, participants, cost)

## Attribution

- **Original Skill**: AI Debate Hub by wolverin0
- **Version**: v4.8
- **Repository**: https://github.com/wolverin0/claude-skills
- **License**: MIT
- **Enhancements**: Claude-Octopus integration (session-aware storage, quality gates, cost tracking, document export, provider debate with Sonnet)

---

**Ready to debate!** Users can invoke with `/debate <question>` or natural language.
