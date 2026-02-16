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

## ⚠️ EXECUTION CONTRACT (MANDATORY - BLOCKING)

**PRECEDENCE: This contract overrides any conflicting instructions in later sections.**

**You are PROHIBITED from proceeding without completing these steps in order.**

### STEP 1: Provider Detection (BLOCKING)

Use the Bash tool to execute:
```bash
command -v codex && echo "CODEX_AVAILABLE" || echo "CODEX_UNAVAILABLE"
command -v gemini && echo "GEMINI_AVAILABLE" || echo "GEMINI_UNAVAILABLE"
```

**You MUST use the Bash tool for this check.** Do NOT assume provider availability.

- If BOTH unavailable: STOP, inform user, suggest `/octo:setup`
- If ONE unavailable: Note it, proceed with available provider(s) + Claude
- If BOTH available: Proceed normally

### STEP 2: Visual Indicators (BLOCKING)

Display the provider banner. DO NOT PROCEED without displaying it.

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: [Topic/question being debated]

Participants:
🔴 Codex CLI - [Available ✓ / Not installed ✗] - Technical implementation perspective
🟡 Gemini CLI - [Available ✓ / Not installed ✗] - Ecosystem and strategic perspective
🔵 Sonnet 4.5 - Independent analytical perspective
🐙 Claude - Moderator and synthesis
```

**This is NOT optional.** Users need to see which AI providers are active and understand they are being charged for external API calls (🔴 🟡).

### STEP 3: Ask Clarifying Questions (BLOCKING)

**Use the AskUserQuestion tool to gather context before starting the debate:**

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

After receiving answers, incorporate them into the debate context.

### STEP 4: Setup Debate Folder (BLOCKING)

Use the Bash tool to create the debate directory structure:

```bash
DEBATE_BASE_DIR="${HOME}/.claude-octopus/debates/${CLAUDE_CODE_SESSION:-local}"
DEBATE_ID="NNN-topic-slug"
DEBATE_DIR="${DEBATE_BASE_DIR}/${DEBATE_ID}"
mkdir -p "${DEBATE_DIR}/rounds"
```

Write `context.md` with debate parameters, question, clarifying context (goal, priority, constraints), and any additional context from the user's message or referenced files.

Write `state.json` with debate metadata (debate_id, question, rounds_total, rounds_completed, advisors, user_context, status, timestamps).

### STEP 5: Execute CLI Calls via Bash Tool (MANDATORY)

**For each debate round**, you MUST use the Bash tool to invoke external CLIs directly:

**Codex invocation (MANDATORY Bash tool call):**
```bash
codex exec --full-auto "YOUR DEBATE PROMPT HERE" > "${DEBATE_DIR}/rounds/r00N_codex.md"
```

**Gemini invocation (MANDATORY Bash tool call):**
```bash
printf '%s' "YOUR DEBATE PROMPT HERE" | gemini -p "" -o text --approval-mode yolo > "${DEBATE_DIR}/rounds/r00N_gemini.md"
```

After reading advisor responses, write your own independent analysis to `${DEBATE_DIR}/rounds/r00N_claude.md`.

For multi-round debates, include previous round context in subsequent prompts so advisors can respond to each other's points.

Evaluate response quality after each round (see Quality Gates in reference section below).

### STEP 6: Verify Execution (VALIDATION GATE)

Use the Bash tool to check output files exist:
```bash
ls -la "${DEBATE_DIR}/rounds/r001_codex.md" "${DEBATE_DIR}/rounds/r001_gemini.md" 2>&1
```

If validation fails, STOP and report the error. Do NOT substitute with direct analysis.

### STEP 7: Synthesize and Present Results

1. Write `${DEBATE_DIR}/synthesis.md` combining all perspectives (summary per advisor, areas of agreement, areas of disagreement, recommended path forward, next steps)
2. If `--synthesize` flag set, generate `${DEBATE_DIR}/deliverable.md` as a proposal (NEVER auto-apply changes without user approval)
3. Present key findings to user in chat
4. Provide debate folder path and suggest export options via `/octo:docs`

### FORBIDDEN ACTIONS

❌ You CANNOT research/analyze directly without the Bash calls in STEP 5
❌ You CANNOT use Task/Explore agents as substitute for Codex/Gemini
❌ You CANNOT claim you are "simulating" the workflow
❌ You CANNOT skip to presenting results without CLI execution
❌ You CANNOT write advisor responses yourself instead of calling CLIs
❌ Do not substitute analysis/summary for required command execution

### COMPLETION GATE

Task is incomplete until all contract checks pass and outputs are reported.
Before presenting results, verify every MUST item was completed. Report any missing items explicitly.

---

# AI Debate Hub Skill v4.7

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
