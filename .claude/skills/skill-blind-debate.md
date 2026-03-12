---
name: skill-blind-debate
user-invocable: true
aliases:
  - blind-debate
  - independent-debate
  - blind
description: "Blind Ideation → Reveal → Multi-round Convergence debate. All AI agents receive the same prompt independently, then debate each other's responses over multiple rounds."
context: fork
trigger: |
  AUTOMATICALLY ACTIVATE when user says:
  - "/blind-debate <question>"
  - "blind debate about X"
  - "independent debate on X"
  - "have them work independently on X then debate"
  - "same prompt to all AIs then compare"

  Supports flags:
  - -r/--rounds N (convergence rounds AFTER the blind phase, default 2, max 10)
  - -a/--advisors LIST (comma-separated: codex,gemini — default: codex,gemini)
  - -w/--max-words N (word limit per response, default 400)
  - -t/--topic NAME (topic slug for folder naming)
  - -o/--out-dir PATH (output directory)
  - -s/--synthesize (generate deliverable from final consensus)
  - --convergence-check (stop early if all agents agree, default: on)
  - --no-convergence-check (force all rounds even if consensus reached)
execution_mode: enforced
validation_gates:
  - blind_phase_completed
  - all_rounds_executed
  - synthesis_file_exists
---

# STOP - SKILL ALREADY LOADED

**DO NOT call Skill() again. DO NOT load any more skills. Execute directly.**

---

# Blind Debate Skill v1.0

## Core Innovation

Unlike the standard `/debate` skill where agents react to each other's framing (creating anchoring bias), this skill uses a **Blind Ideation → Reveal → Iterative Convergence** pattern:

```
     User Question
           |
     ┌─────┼─────┐
     ▼     ▼     ▼
  ┌─────┐┌─────┐┌─────┐
  │Codex││Gemin││Claude│  PHASE 1: BLIND
  │works││works││works │  Same prompt, no cross-reference
  │alone││alone││alone │  Maximum response diversity
  └──┬──┘└──┬──┘└──┬──┘
     │     │     │
     ▼     ▼     ▼
  ┌──────────────────┐
  │   REVEAL ALL 3   │    PHASE 2: REVEAL
  │ responses to all │    Each agent sees ALL responses
  │   3 participants │    for the first time
  └────────┬─────────┘
           │
     ┌─────┼─────┐
     ▼     ▼     ▼
  ┌─────┐┌─────┐┌─────┐
  │Codex││Gemin││Claude│  PHASE 3+: CONVERGENCE ROUNDS
  │critiqu│critiqu│critiqu  Critique all (including own),
  │revise││revise││revise│  propose revised answer
  └──┬──┘└──┬──┘└──┬──┘
     │     │     │         Repeat N rounds or until
     └─────┼─────┘         positions stabilize
           │
           ▼
  ┌──────────────────┐
  │  FINAL SYNTHESIS  │   Disagreement map +
  │  by Claude        │   best-of-all recommendation
  └──────────────────┘
```

**Why this matters:** Standard debate anchors all agents to the first response. Blind ideation explores genuinely different regions of the solution space, then convergence finds the best synthesis.

---

## MANDATORY: Visual Indicators Protocol

**BEFORE starting ANY blind debate, you MUST output this banner:**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Blind Debate
🐙 Topic: [Question being debated]

Phase: Blind Ideation → Reveal → Convergence (N rounds)

Participants (working INDEPENDENTLY in Phase 1):
🔴 Codex CLI - Independent analysis (blind)
🟡 Gemini CLI - Independent analysis (blind)
🔵 Claude - Independent analysis (blind)
🐙 Claude - Moderator and synthesis (Phase 3+)
```

**This is NOT optional.** Users need to see which AI providers are active.

---

## CRITICAL: External CLI Syntax (v0.101.0+)

**You MUST use these exact command patterns. Do NOT improvise flags.**

**Codex CLI** (non-interactive headless mode):
```bash
codex exec --full-auto "YOUR PROMPT HERE"
```
- MUST use `exec` subcommand — bare `codex "prompt"` launches interactive TUI
- MUST use `--full-auto` — NOT `-q`, `--quiet`, or `-y` (these flags DO NOT EXIST)

**Gemini CLI** (non-interactive headless mode):
```bash
printf '%s' "YOUR PROMPT HERE" | gemini -p "" -o text --approval-mode yolo
```
- MUST use `-p ""` to trigger headless mode
- MUST pipe prompt via stdin
- Do NOT use `-y` (deprecated, replaced by `--approval-mode yolo`)

---

## EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

### STEP 1: Check Providers & Display Banner

```bash
codex_available=$(command -v codex &> /dev/null && echo "yes" || echo "no")
gemini_available=$(command -v gemini &> /dev/null && echo "yes" || echo "no")
```

Display the visual indicator banner (see above).

If BOTH providers unavailable: inform user and suggest `/octo:setup`. STOP.
If ONE unavailable: note it, proceed with available provider(s) + Claude.

**DO NOT PROCEED until banner displayed.**

---

### STEP 2: Parse Arguments & Setup

Parse the user's question and flags:

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--rounds N` | `-r N` | 2 | Convergence rounds AFTER blind phase (1-10) |
| `--advisors LIST` | `-a LIST` | gemini,codex | Comma-separated provider list |
| `--max-words N` | `-w N` | 400 | Word limit per response |
| `--topic NAME` | `-t NAME` | auto | Topic slug for folder naming |
| `--out-dir PATH` | `-o PATH` | debates/ | Output directory |
| `--synthesize` | `-s` | off | Generate deliverable from consensus |
| `--convergence-check` | | on | Stop early if consensus reached |
| `--no-convergence-check` | | | Force all rounds |

Create the debate folder:

```bash
DEBATE_BASE_DIR="${HOME}/.claude-octopus/blind-debates/${CLAUDE_CODE_SESSION:-local}"
DEBATE_ID="NNN-topic-slug"
DEBATE_DIR="${DEBATE_BASE_DIR}/${DEBATE_ID}"

mkdir -p "${DEBATE_DIR}/rounds"

cat > "${DEBATE_DIR}/context.md" <<EOF
# Blind Debate: ${QUESTION}

**ID**: ${DEBATE_ID}
**Convergence Rounds**: ${ROUNDS}
**Advisors**: ${ADVISORS}
**Started**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Mode**: Blind Ideation → Reveal → Convergence

## Question
${QUESTION}
EOF
```

**DO NOT PROCEED until folder created.**

---

### STEP 3: BLIND PHASE (CRITICAL — This is the key innovation)

**All agents receive the IDENTICAL prompt. No agent sees any other agent's work.**

The blind prompt MUST be:

```
You are participating in a blind ideation exercise. You will answer the following question INDEPENDENTLY.

Do NOT consider what other AI models might say. Do NOT hedge or try to be comprehensive — commit to your best answer with conviction. Be specific and opinionated.

IMPORTANT: Your response will later be compared against other independent responses. The goal is DIVERSITY of thought, not consensus. Take a clear position.

Word limit: ${MAX_WORDS} words.

QUESTION:
${QUESTION}
```

**Launch ALL agents in parallel:**

```bash
# Codex — blind
codex exec --full-auto "${BLIND_PROMPT}" > "${DEBATE_DIR}/rounds/r000_blind_codex.md" 2>"${DEBATE_DIR}/rounds/r000_blind_codex.log" &
CODEX_PID=$!

# Gemini — blind
printf '%s' "${BLIND_PROMPT}" | gemini -p "" -o text --approval-mode yolo > "${DEBATE_DIR}/rounds/r000_blind_gemini.md" 2>"${DEBATE_DIR}/rounds/r000_blind_gemini.log" &
GEMINI_PID=$!
```

**Claude's blind response:** Write your OWN independent analysis to `r000_blind_claude.md`. You MUST write this BEFORE reading any advisor responses. Commit to a clear position.

**Wait for all agents:**

```bash
wait $CODEX_PID $GEMINI_PID
```

**Validation gate: `blind_phase_completed`** — All `r000_blind_*.md` files exist and are non-empty.

**IMPORTANT:** If an advisor's response is empty or errored, note this but continue. A 2-way blind debate is still valuable.

**Display blind phase results:**

```
🔴 **Codex (Blind):** [first 2-3 sentences summary]
🟡 **Gemini (Blind):** [first 2-3 sentences summary]
🔵 **Claude (Blind):** [first 2-3 sentences summary]

Key observation: [note the diversity/overlap of approaches]
```

**DO NOT PROCEED until blind phase validated.**

---

### STEP 4: CONVERGENCE ROUNDS (Repeat for N rounds)

For each convergence round (1 through N):

#### 4.1: Build the Cross-Critique Prompt

For round 1, the prompt includes the blind responses. For round 2+, it includes the previous round's revised positions.

**Round 1 cross-critique prompt:**

```
You previously answered a question independently (blind). Now you can see ALL independent responses, including your own.

YOUR BLIND RESPONSE:
${THIS_AGENT_BLIND_RESPONSE}

ALL INDEPENDENT RESPONSES:

--- RESPONSE A (Codex, blind) ---
${CODEX_BLIND}

--- RESPONSE B (Gemini, blind) ---
${GEMINI_BLIND}

--- RESPONSE C (Claude, blind) ---
${CLAUDE_BLIND}

INSTRUCTIONS:
1. What did each response get RIGHT that others missed?
2. What did each response get WRONG (including your own)?
3. What new insight emerges from seeing all three together?
4. Propose your REVISED answer, incorporating the best elements from all responses.

Be specific about what changed in your thinking and why. If nothing changed, explain why you still hold your original position.

Word limit: ${MAX_WORDS} words.
```

**Round 2+ cross-critique prompt:**

```
This is convergence round ${ROUND_NUM}. Here are the revised positions from the previous round:

--- REVISED POSITION A (Codex) ---
${CODEX_PREV}

--- REVISED POSITION B (Gemini) ---
${GEMINI_PREV}

--- REVISED POSITION C (Claude) ---
${CLAUDE_PREV}

INSTRUCTIONS:
1. Where do you STILL DISAGREE with others? Why?
2. What evidence or argument would change your mind?
3. What is the STRONGEST argument against your current position?
4. Propose your FINAL revised answer for this round.

If you have fully converged with the group, state that explicitly and summarize the consensus.

Word limit: ${MAX_WORDS} words.
```

#### 4.2: Launch All Agents (Parallel)

```bash
# Codex convergence round
codex exec --full-auto "${CODEX_ROUND_PROMPT}" > "${DEBATE_DIR}/rounds/r00${ROUND}_codex.md" 2>"${DEBATE_DIR}/rounds/r00${ROUND}_codex.log" &
CODEX_PID=$!

# Gemini convergence round
printf '%s' "${GEMINI_ROUND_PROMPT}" | gemini -p "" -o text --approval-mode yolo > "${DEBATE_DIR}/rounds/r00${ROUND}_gemini.md" 2>"${DEBATE_DIR}/rounds/r00${ROUND}_gemini.log" &
GEMINI_PID=$!
```

**Claude convergence round:** Read all previous responses, then write your own revised position to `r00${ROUND}_claude.md`.

Wait for agents. Read all responses.

#### 4.3: Convergence Check (if enabled)

After each round, check if all agents have converged:
- If all agents explicitly state they've reached consensus → stop early
- If positions haven't materially changed from previous round → stop early
- Otherwise → continue to next round

**Display round results:**

```
=== CONVERGENCE ROUND ${ROUND} ===

🔴 **Codex:** [key position change or reaffirmation]
🟡 **Gemini:** [key position change or reaffirmation]
🔵 **Claude:** [key position change or reaffirmation]

Convergence status: [converging / diverging / stable]
```

**Validation gate: `all_rounds_executed`** — All round files exist for all participating agents.

**DO NOT PROCEED to synthesis until all rounds complete.**

---

### STEP 5: FINAL SYNTHESIS

Read ALL round files. Write a comprehensive synthesis:

```bash
cat > "${DEBATE_DIR}/synthesis.md" <<EOF
# Blind Debate Synthesis: ${QUESTION}

## Debate Structure
- **Phase 1 (Blind)**: 3 independent responses, no cross-reference
- **Convergence Rounds**: ${ROUNDS_COMPLETED} rounds of cross-critique
- **Participants**: Codex, Gemini, Claude

## Initial Diversity (Blind Phase)
### Approach A (Codex)
[Codex's core blind position — what made it unique]

### Approach B (Gemini)
[Gemini's core blind position — what made it unique]

### Approach C (Claude)
[Claude's core blind position — what made it unique]

### Diversity Analysis
[How different were the blind responses? What dimensions of the problem did each prioritize?]

## Convergence Journey
### What Changed After Reveal
[Key shifts in position after agents saw each other's work]

### Round-by-Round Evolution
[How positions evolved across rounds]

## Final Positions

### Areas of Strong Consensus
[Where all agents converged — high confidence]

### Areas of Partial Agreement
[Where 2 of 3 agree — medium confidence]

### Remaining Disagreements
[Where agents still differ — these represent genuine trade-offs]

## Recommended Path Forward
[Best synthesis of all perspectives, weighted by argument quality]

## Dissenting Views Worth Preserving
[Minority positions that have merit even if outvoted]

## Decision Framework
[When would you choose Approach A over B? What context matters?]
EOF
```

Present the synthesis to the user in the chat.

**Validation gate: `synthesis_file_exists`** — `synthesis.md` exists and is non-empty.

---

### STEP 6: Generate Deliverable (when --synthesize is set)

If `--synthesize` was passed:
1. Read synthesis.md
2. Generate a concrete deliverable based on consensus
3. Save to `${DEBATE_DIR}/deliverable.md`
4. Present to user with options: "Apply this" / "Refine" / "Save only"

---

## Flags Reference

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--rounds N` | `-r N` | 2 | Convergence rounds after blind phase |
| `--advisors LIST` | `-a LIST` | gemini,codex | Which providers to include |
| `--max-words N` | `-w N` | 400 | Word limit per response |
| `--topic NAME` | `-t NAME` | auto-generated | Topic slug for folder |
| `--out-dir PATH` | `-o PATH` | `~/.claude-octopus/blind-debates/` | Output directory |
| `--synthesize` | `-s` | off | Generate deliverable |
| `--convergence-check` | | on | Early stop if consensus |
| `--no-convergence-check` | | off | Force all rounds |

---

## Example Usage

### Example 1: Architecture Decision
```
/blind-debate Should we use microservices or a modular monolith for our new payment system?

Phase 1 (Blind):
  Codex: Argues for microservices, focuses on team scaling
  Gemini: Argues for modular monolith, focuses on operational simplicity
  Claude: Proposes hybrid — monolith first with service extraction plan

Phase 2 (Round 1 — Reveal):
  Codex: "Gemini's point about operational complexity is valid. Revised: start monolith..."
  Gemini: "Codex's scaling concern is real. Revised: modular monolith WITH service boundaries..."
  Claude: "Both now converging toward my hybrid position. Adding: specific extraction triggers..."

Phase 3 (Round 2):
  All three converge on: "Start with modular monolith, define service boundaries upfront,
  extract when team size exceeds 3 squads or module deploy frequency diverges >2x"

Synthesis: Strong consensus with specific decision triggers.
```

### Example 2: Quick 1-Round Blind
```
/blind-debate -r 1 What's the best approach to handling authentication in a serverless app?

Phase 1 (Blind): 3 independent responses
Phase 2 (1 convergence round): Cross-critique and revise
Synthesis: Key trade-offs surfaced, recommended approach with alternatives
```

---

## Quality Checklist

Before completing a blind debate:

- [ ] Visual banner displayed before any work
- [ ] Blind phase: ALL agents received the IDENTICAL prompt
- [ ] Blind phase: Claude wrote response BEFORE reading advisor outputs
- [ ] Blind phase: No cross-references in blind prompts
- [ ] Convergence: Each agent saw ALL responses (not just one)
- [ ] Convergence: Prompts asked for specific critique, not just "react"
- [ ] Synthesis includes initial diversity analysis
- [ ] Synthesis includes convergence journey (what changed)
- [ ] Synthesis includes remaining disagreements (not just consensus)
- [ ] All round files saved to debate directory
- [ ] Debate folder path provided to user

---

## Prohibitions (MANDATORY)

- CANNOT show Agent A's blind response to Agent B during Phase 1
- CANNOT frame Phase 1 prompts as "argue for X" or "argue against X"
- CANNOT skip the blind phase and go straight to cross-critique
- CANNOT write Claude's blind response AFTER reading advisor responses
- CANNOT use Phase 1 prompts that reference other agents or positions
- CANNOT skip convergence rounds if user requested them (unless --convergence-check triggers early stop)
- CANNOT present synthesis without showing the diversity of blind responses
- CANNOT omit remaining disagreements from synthesis

---

## Integration with Other Skills

- **`/octo:debate`**: Use `/debate` for quick position-based debates. Use `/blind-debate` when you want maximum diversity and reduced anchoring bias.
- **`/octo:docs`**: Export blind debate results to PPTX/DOCX/PDF
- **`/octo:embrace`**: Use blind debate in the Define phase to explore solution space before committing

---

**Ready!** Users invoke with `/blind-debate <question>` or `/octo:blind-debate <question>`.
