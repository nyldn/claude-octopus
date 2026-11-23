---
name: skill-debate
description: "Structured multi-provider AI debates between Claude and available advisors — use for critical decisions"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, bind `OCTO_ROOT`, `CODEX_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_ROOT` to the same root, and export all three in each fresh shell before launching child processes. Use the verified absolute helper path when needed. Do not infer the root from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$skill-debate` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


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
🟡 Antigravity CLI - Ecosystem and strategic perspective
🟠 Sonnet 5 - Pragmatic implementer perspective if host subagents are available
🐙 current host model - Moderator and synthesis
🟢 Copilot CLI - GitHub-native perspective (if available)
🟤 Qwen CLI - Alternative model perspective (if available)
```

**Core participants are selected from available providers.** Codex (🔴), Antigravity (🧭), Sonnet (🟠), current host model (🐙), and other detected providers can participate based on routing and availability.

**This is NOT optional.** Users need to see which AI providers are active. External API calls (🔴 🟡) use provider API keys. Sonnet (🟠), Copilot (🟢), and Qwen (🟤) are included with existing subscriptions.


## CRITICAL: External CLI Syntax (v0.101.0+)

**You MUST use this exact command pattern. Do NOT improvise provider flags.**

For debate rounds, dispatch every external advisor through Octopus routing in
the advisor role, so the debate prompt does not inherit an implementer persona
or curated skill context:

```bash
OCTOPUS_SPAWN_ROLE=advisor "${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/orchestrate.sh" spawn "$advisor" "$prompt"
```

Do not call provider CLIs directly from the debate workflow. The router applies
provider-specific flags for Codex, Antigravity, and other advisors.

- Provider-specific syntax lives in `scripts/lib/dispatch.sh` and helper scripts.
- Do not copy direct provider CLI invocations into debate steps.
- Always pass the selected advisor name to `orchestrate.sh spawn`; the router chooses the correct command.

**Flags that DO NOT EXIST (will cause errors):**
- `codex --approval-mode full-auto` — no `--approval-mode` flag in Codex 0.130.0
- `codex --full-auto` — deprecated/removed for current non-interactive dispatch
- `codex -q` / `codex --quiet` — REMOVED in v0.101.0
- `codex -y` / `codex --yes` — NEVER EXISTED
- `codex "prompt"` without `exec` — launches interactive TUI, hangs


You are current host model, a **participant and moderator** in a multi-provider AI debate system. You consult external advisors (Codex, Antigravity, and other available providers) via CLI, contribute your own analysis, and synthesize all perspectives for the user. Include an allowed Sonnet analyst through the native Claude Code Agent route. On Codex or another host, require two external advisor results instead of assigning Sonnet's identity to a host subagent.

**CRITICAL: You are NOT just an orchestrator. You are an active participant with your own voice and opinions.**

### Interface-design debates

When the question is an interface design, load
`codex-skills/blocks/architecture-simplification.md`. Give each initial advisor the same
requirements and source revision without another advisor's draft. Record source
access and model family separately from provider transport. A reviewer without
artifact access contributes questions, not approval. Preserve evidence-backed
minority findings even when the vote count favors another design.


## How Users Invoke This Skill

Users invoke this skill explicitly from the slash menu. Parse the supplied intent and run the debate.

### Basic Invocation
```
$skill-debate <question or task>
```

### With Flags
```
$skill-debate -r 3 -d thorough <question>
$skill-debate --rounds 2 --debate-style adversarial <question>
$skill-debate --path debates/009-new-topic <question>
```

### With File References
Users can mention files naturally - you resolve them to full paths:
```
$skill-debate Is our CLAUDE.md accurate?
-> You resolve to full absolute path

$skill-debate Review the auth flow in src/auth.ts
-> You find src/auth.ts relative to cwd and pass full path to advisors
```

### Examples Users Might Say
- `$skill-debate Should we use Redis or in-memory cache?`
- `$skill-debate -r 3 Review the whatsappbot codebase for issues`
- `$skill-debate on whether our error handling in api.ts is sufficient`
- `Run a debate about the database schema design`
- `I want Antigravity and Codex to review this PR`


## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--rounds N` | `-r N` | 1 | Number of debate rounds (1-10) |
| `--debate-style STYLE` | `-d STYLE` | quick | Style: `quick`, `thorough`, `adversarial`, `collaborative` |
| `--mode MODE` | | cross-critique | Advisor exchange: `cross-critique` or `blinded` |
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
| Antigravity analyzes | 🧭 External CLI
| Codex analyzes    |  🔴 External CLI
| Sonnet analyzes   |  🟠 Agent(model: sonnet)
| YOU analyze       |  🐙 Your independent analysis (Opus)
+-------------------+
           |
           v
+-------------------+
|     ROUND 2+      |
+-------------------+
| Antigravity responds | 🧭 Sees prior round
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
2. **Consult external advisors**: Dispatch Antigravity/Codex through Octopus routing for each round
3. **Launch allowed Sonnet**: Dispatch Sonnet via host subagent tool only when the provider allowlist permits it
4. **Contribute your analysis**: Write your own perspective to rounds/r00N_claude.md
5. **Moderate**: Ensure advisors stay on topic, follow word limits
6. **Synthesize**: Combine all four perspectives into actionable recommendations


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


## Implementation Steps

When the user invokes `$skill-debate`:

### Step 1: Check Provider Availability & Display Banner

**MANDATORY: You MUST use the native shell command tool to run this provider check BEFORE displaying the banner. Do NOT skip it. Do NOT assume availability.**
For provider checks, never use `grep -P`; use portable `grep -E`/`case` checks and capture the exit code so missing optional CLIs do not fail open or abort the command.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/helpers/check-providers.sh"
```

**Use the ACTUAL results below. PROHIBITED: Showing only "🔵 Claude: Available ✓" without listing all providers.**

Then display the banner with real provider status:
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: [Topic/question being debated]

Provider Availability:
🔴 Codex CLI: [Available ✓ / Not installed ✗]
🟡 Antigravity CLI: [Available ✓ / Not installed ✗]
🧭 Antigravity CLI: [Available ✓ / Not installed ✗]
🤖 Grok CLI (xAI): [Available ✓ / Not installed ✗]
🟠 Sonnet 5: available only when this Codex session exposes a compatible host subagent tool
🐙 current host model: Available ✓ (Moderator and participant)
```

> **🧭 Antigravity availability:** Antigravity CLI = the `agy` binary; judge availability only via `command -v agy` (as `check-providers.sh` does), never from the `antigravity` desktop shortcut.

**If providers are missing:**
- If all external providers are unavailable: Inform user that debate requires at least one external provider and suggest running `$sys-configure` to configure them
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

**After receiving answers:** Set `DEBATE_MODE` from an explicit `--mode` option if
present. Otherwise, set it to `blinded` for "Independent evaluation" and
`cross-critique` for "Cross-critique" or when no preference was given.
Incorporate the other answers into the debate context.

### Step 3: Parse Arguments & Build Debate Fleet

The blocks that load `consultative-advisors.sh` run under bash even when the host
shell is zsh, where each one runs as a separate bash process. No block sees the
variables an earlier block set, so set each block's inputs first: before the
heredoc as exported assignments for a wrapped block, before the block otherwise.
Take them from the user's request and from the values earlier blocks print. Insert every carried
value as a single-quoted shell literal, escaping each embedded single quote as
`'\''`, or generate the complete value with Python's `shlex.quote`. This keeps
quotes, dollar signs, backticks and newlines literal instead of executing them.
Keep user values outside the fixed heredoc, so a request line equal to
`OCTO_BASH` cannot terminate it.

```bash
# Runs under bash even when the host shell is zsh.
export QUESTION='Should we use Redis or in-memory cache?'
if [ -n "${BASH_VERSION:-}" ]; then eval "$(cat)"; else env "OCTO_ALLOWED_PROVIDERS=${OCTO_ALLOWED_PROVIDERS:-}" bash -c "$(cat)"; fi <<'OCTO_BASH'
# Extract question and flags
ROUNDS=3
STYLE="thorough"

# Dynamic advisor selection — the fleet builder remains the admission authority.
CONSULTATIVE_LIB="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/lib/consultative-advisors.sh"
ADVISOR_SELECTOR="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/helpers/select-fleet-advisors.sh"
source "$CONSULTATIVE_LIB" || exit 1
HOST_CLAUDE_ALLOWED=false
HOST_ADVISOR_SUCCESS=0
if octo_consultative_host_allowed; then
  HOST_CLAUDE_ALLOWED=true
fi
REQUIRED_EXTERNAL_ADVISORS=$(octo_consultative_required_external_count)
if ! ADVISORS=$("$ADVISOR_SELECTOR" debate standard "$QUESTION"); then
  echo "No eligible external debate advisors are available." >&2
  exit 1
fi
printf 'HOST_CLAUDE_ALLOWED=%s\nREQUIRED_EXTERNAL_ADVISORS=%s\nADVISORS=%s\nROUNDS=%s\nSTYLE=%s\n' \
  "$HOST_CLAUDE_ALLOWED" "$REQUIRED_EXTERNAL_ADVISORS" "$ADVISORS" "$ROUNDS" "$STYLE"
OCTO_BASH
```

**The `build-fleet.sh debate` command** selects up to 3 debaters from different model families (for example, codex/OpenAI, agy/Google Antigravity, and copilot/Microsoft) to maximize training-bias diversity. Do not hardcode provider pairs; use the runtime `ADVISORS` list.

### Step 4: Setup Debate Folder

Run this block in a fresh shell. Restore the printed fleet settings, the mode
from Step 2, and the original question and clarifying answers using the literal
quoting rule above.

```bash
QUESTION='[Original question from Step 3]'
ROUNDS='[ROUNDS printed by Step 3]'
STYLE='[STYLE printed by Step 3]'
DEBATE_MODE='[DEBATE_MODE from Step 2]'
ADVISORS='[ADVISORS printed by Step 3]'
USER_GOAL='[Primary goal from Step 2]'
USER_PRIORITY='[Priority factor from Step 2]'
USER_CONSTRAINTS='[Constraints from Step 2]'
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
**Mode**: ${DEBATE_MODE}
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

# Encode user text as JSON data rather than shell-generated JSON syntax.
python3 -I - "$DEBATE_DIR/state.json" "$DEBATE_ID" "$QUESTION" "$ROUNDS" \
  "$DEBATE_MODE" "$ADVISORS" "$USER_GOAL" "$USER_PRIORITY" "$USER_CONSTRAINTS" <<'PY_DEBATE_STATE' || exit 1
from datetime import datetime, timezone
from pathlib import Path
import json
import sys
path, run_id, question, rounds, mode, advisors, goal, priority, constraints = sys.argv[1:]
rounds = int(rounds)
if not 1 <= rounds <= 10:
    raise SystemExit('Debate rounds must be between 1 and 10')
if mode not in ('blinded', 'cross-critique'):
    raise SystemExit('Debate mode must be blinded or cross-critique')
state = {
    'debate_id': run_id, 'question': question,
    'rounds_total': rounds, 'rounds_completed': 0, 'mode': mode,
    'advisors': [seat.strip() for seat in advisors.split(',') if seat.strip()],
    'user_context': {'goal': goal, 'priority': priority, 'constraints': constraints},
    'status': 'active',
    'created_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
}
with Path(path).open('w', encoding='utf-8') as stream:
    json.dump(state, stream, ensure_ascii=False, indent=2)
    stream.write('\n')
PY_DEBATE_STATE
printf 'DEBATE_DIR=%s\n' "$DEBATE_DIR"
```

### Step 5: Conduct Rounds

Read the mode from this run's `state.json`. If resuming an older run without a
saved mode, recover the original choice from the conversation and record it in
the `mode` field before continuing. If you already read any advisor responses
in a blinded run, tell the user that independence was lost before proceeding.

#### 5.1: Save Blinded Analysis and Launch External Advisors

In blinded mode, save your analysis for every round before launching any advisors.
Use only the question and source material. Save the first note as
`rounds/r001_claude.md` and use the corresponding round number for each later
note. Confirm all notes are saved before launching external advisors or Sonnet.
Keep the notes for final synthesis even if a background completion includes
response text. During the rounds, check completion status and artifact
presence. Keep advisor responses separate until final synthesis.

In cross-critique mode, write the moderator's analysis after reading the
current round's responses, as described in Step 5.3.

For each round, iterate the runtime advisor list and dispatch through Octopus.
The examples use round one. Use the current round number and its `rNNN` prefix
in the prompts, paths, and calls for later rounds. The launch waits for every advisor to finish, often several minutes, so run the block with
`run_in_background: true`; a foreground 600000 ms timeout stops it after 10 minutes, while
the launcher waits up to `OCTOPUS_ADVISOR_WAIT_SECONDS` (default 3600 s). Each answer lands in
`${DEBATE_DIR}/rounds/r001_<advisor>.md`, with any character other than a letter, digit,
`_` or `-` in the advisor name replaced by `_` (`codex:model` gives `r001_codex_model.md`).
An advisor that fails leaves no file:

```bash
# Runs under bash even when the host shell is zsh.
export QUESTION='[QUESTION from Step 3]'
export CONTEXT='[Clarifying context from Step 2]'
export MAX_WORDS='[--max-words value, default 300]'
export DEBATE_DIR='[DEBATE_DIR printed by Step 4]'
export ADVISORS='[ADVISORS printed by Step 3]'
export REQUIRED_EXTERNAL_ADVISORS='[REQUIRED_EXTERNAL_ADVISORS printed by Step 3]'
if [ -n "${BASH_VERSION:-}" ]; then eval "$(cat)"; else env "OCTO_ALLOWED_PROVIDERS=${OCTO_ALLOWED_PROVIDERS:-}" bash -c "$(cat)"; fi <<'OCTO_BASH'
ORCH="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/orchestrate.sh"
source "${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/lib/consultative-advisors.sh" || exit 1
DEBATE_PROMPT="You are {{advisor}} participating in debate round 1.

DEBATE QUESTION: ${QUESTION}

${CONTEXT}

Write a concise, independent analysis (${MAX_WORDS} words). Address implementation tradeoffs, risks, and where other likely perspectives may be wrong."
if ! SUCCESSFUL_EXTERNAL_ADVISORS=$(octo_launch_advisors "$ORCH" "$ADVISORS" \
    "${DEBATE_DIR}/rounds" r001_ "$DEBATE_PROMPT" "$REQUIRED_EXTERNAL_ADVISORS"); then
  echo "The required external debate advisors did not complete successfully." >&2
  exit 1
fi
printf 'SUCCESSFUL_EXTERNAL_ADVISORS=%s\n' "$SUCCESSFUL_EXTERNAL_ADVISORS"
OCTO_BASH
```

#### 5.2: Launch optional host subagent (Pragmatic Implementer)

Dispatch Sonnet via the host subagent tool only when `HOST_CLAUDE_ALLOWED=true` and the
native Claude Code host enforces `model: "sonnet"`. Codex and other hosts require
two successful external providers. A subagent role, requested model name or
Sonnet-style perspective does not establish a distinct Sonnet provider. If
Claude is disallowed or that native route is unavailable, skip this step. Set
`HOST_ADVISOR_SUCCESS=1` only after the allowed Sonnet task completes with usable
output in this round's `r001_sonnet.md`; otherwise set it to `0`. Remove a stale
Sonnet artifact before launching a new round task. Never count a failed task's
partial output or relabel a Codex result as Sonnet. Sonnet can run in parallel
with the external advisor calls.

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

Your final reply must contain only a completion status and the artifact path.
Do not include any analysis, verdict, or summary in the final reply.

Cover: implementation feasibility, hidden gotchas, concrete effort estimates, and what the other approaches miss from a builder's perspective."
)
```

After all allowed advisors finish, enforce the two-provider minimum. Fill in the
block's export lines:

```bash
# Runs under bash even when the host shell is zsh.
export SUCCESSFUL_EXTERNAL_ADVISORS='[SUCCESSFUL_EXTERNAL_ADVISORS printed by the round'"'"'s launch block]'
export HOST_ADVISOR_SUCCESS='[1 if the allowed Sonnet task completed with usable output, else 0]'
export DEBATE_DIR='[DEBATE_DIR printed by Step 4]'
if [ -n "${BASH_VERSION:-}" ]; then eval "$(cat)"; else env "OCTO_ALLOWED_PROVIDERS=${OCTO_ALLOWED_PROVIDERS:-}" bash -c "$(cat)"; fi <<'OCTO_BASH'
source "${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/lib/consultative-advisors.sh" || exit 1
if ! octo_consultative_provider_count_is_sufficient \
    "$SUCCESSFUL_EXTERNAL_ADVISORS" "$HOST_ADVISOR_SUCCESS" "${DEBATE_DIR}/rounds/r001_sonnet.md"; then
  echo "A debate requires two successful, allowlisted providers." >&2
  exit 1
fi
OCTO_BASH
```

**WHY Sonnet and not just more Opus?** Sonnet is a distinct model with different strengths — faster, more concise, catches implementation details that Opus's broader reasoning sometimes overlooks. Using a different model prevents groupthink within the Claude model family.

**Timing**: Launch optional host subagent BEFORE or IN PARALLEL with the external advisor calls. By the time the CLI calls return, Sonnet is usually done too. Check for completion before proceeding to 5.3.

#### 5.3: Read Advisor Responses and Record the Moderator Analysis

For cross-critique, run the response-reading block after the provider minimum
passes. Then write your own analysis to `rounds/r001_claude.md` based on the
advisor perspectives. For blinded mode, skip this step during the rounds.
During final synthesis, use the block for each round to read advisor responses
alongside the saved moderator notes. Keep those notes as written.

Restore the run directory and use the appropriate round prefix in the block.

```bash
DEBATE_DIR='[DEBATE_DIR printed by Step 4]'
ROUND_PREFIX=r001
state_file="${DEBATE_DIR}/state.json"
if ! mode=$(jq -er '.mode | select(. == "blinded" or . == "cross-critique")' "$state_file"); then
    printf '%s\n' 'Recover the saved debate mode before reading advisor responses.' >&2
    exit 1
fi
if [ "$mode" = blinded ]; then
    rounds=$(jq -er '.rounds_total | select(type == "number" and . == floor and . >= 1 and . <= 10)' "$state_file") || exit 1
    for ((round = 1; round <= rounds; round++)); do
        moderator_file="${DEBATE_DIR}/rounds/$(printf 'r%03d_claude.md' "$round")"
        if [ ! -f "$moderator_file" ] || [ ! -s "$moderator_file" ]; then
            printf 'Save the blinded moderator analysis for round %s before reading advisor responses.\n' "$round" >&2
            exit 1
        fi
    done
fi
for response_file in "${DEBATE_DIR}/rounds/${ROUND_PREFIX}_"*.md; do
    [ -f "$response_file" ] || continue
    [ "$response_file" = "${DEBATE_DIR}/rounds/${ROUND_PREFIX}_claude.md" ] && continue
    printf '\n## %s\n' "$(basename "$response_file" .md)"
    cat "$response_file" || exit 1
done
```

#### 5.4: Quality Gates (Claude-Octopus Enhancement)
In cross-critique mode, evaluate response quality after each advisor responds.
In blinded mode, wait until Step 6 before scoring advisor responses. Set
`ROUND_PREFIX` to the current round's prefix for each invocation.

```bash
DEBATE_DIR='[DEBATE_DIR printed by Step 4]'
ROUND_PREFIX=r001
evaluate_response_quality() {
    local response_file="${1}"
    local word_count has_citations has_code addresses_others score=0

    word_count=$(wc -w < "$response_file") || return 1
    # grep -c prints 0 and exits 1 when there are no matches.
    has_citations=$(grep -c '\[' "$response_file") || [[ $? -eq 1 ]] || return 1
    has_code=$(grep -c '```' "$response_file") || [[ $? -eq 1 ]] || return 1
    addresses_others=$(grep -ciE '(gemini|codex|agy|antigravity|claude|sonnet)' "$response_file") ||
        [[ $? -eq 1 ]] || return 1

    (( word_count >= 50 && word_count <= 1000 )) && (( score += 25 ))
    (( has_citations > 0 )) && (( score += 25 ))
    (( has_code > 0 )) && (( score += 25 ))
    (( addresses_others > 0 )) && (( score += 25 ))

    echo "$score"
}

for response_file in "${DEBATE_DIR}/rounds/${ROUND_PREFIX}_"*.md; do
    [ -f "$response_file" ] || continue
    response_name=$(basename "$response_file" .md)
    advisor="${response_name#"${ROUND_PREFIX}_"}"
    [ "$advisor" = claude ] && continue
    quality_score=$(evaluate_response_quality "$response_file") || exit 1
    if (( quality_score < 50 )); then
        echo "Low quality response from ${advisor} (score: $quality_score). Re-prompting..."
        # Re-prompt for more detail
    fi
done
```

### Step 6: Final Synthesis

After all rounds complete, write a comprehensive synthesis. In blinded mode,
use Steps 5.3 and 5.4 to read and score the advisor responses for each
completed round. Use the same round prefix in both steps and cite the saved
moderator analyses when comparing perspectives.

```bash
DEBATE_DIR='[DEBATE_DIR printed by Step 4]'
QUESTION='[Original question from Step 3]'
cat > "${DEBATE_DIR}/synthesis.md" <<EOF
# Final Synthesis: ${QUESTION}

## Summary of Perspectives

### External Advisor Perspectives
[Key points from each advisor selected in ADVISORS: Codex, Antigravity, or other available providers]

### 🟠 Sonnet's Perspective
[Key points from Sonnet across all rounds — especially implementation feasibility and gotchas]

### 🐙 current host model Perspective
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


## Example Usage

### Example 1: Quick Debate
```
User: $skill-debate Should we use Redis or in-memory cache?

Claude:
1. Creates debate folder at ~/.claude-octopus/debates/${SESSION_ID}/042-redis-vs-memcached/
2. Writes context.md with question
3. Round 1:
   - Launches Sonnet via Agent(model: sonnet, run_in_background: true) when the provider allowlist permits it
   - Calls orchestrate.sh spawn for each runtime advisor selected by build-fleet.sh, such as codex and agy
   - Waits for Sonnet completion
   - Writes own analysis (Opus) considering all advisor perspectives
4. Writes synthesis.md with final recommendation from all participants
5. Presents results in chat
```

### Example 2: Thorough Adversarial Debate
```
User: $skill-debate -r 3 -d adversarial Review our authentication implementation in src/auth.ts

Claude:
1. Reads src/auth.ts to understand context
2. Creates debate folder
3. Round 1 (Sonnet launched in background first, then selected external advisors in parallel):
   - 🟠 Sonnet: Implementation feasibility analysis of auth.ts
   - External advisors selected by build-fleet.sh, such as 🔴 Codex or 🧭 Antigravity depending on availability
   - 🐙 current host model: Your independent analysis considering all advisors
4. Round 2:
   - 🟠 Sonnet: Responds to other participants' points
   - External advisors challenge each other's points
   - 🐙 Claude: You challenge advisor points
5. Round 3:
   - All participants: Final positions
6. Synthesis with quality scores for each advisor
7. Present results with cost tracking
```


## Quality Checklist

Before completing a debate, ensure:

- [ ] All rounds completed for selected participants
- [ ] Your independent analysis (Opus) written for each round (not just summaries)
- [ ] Synthesis.md includes all participating perspectives
- [ ] Quality scores recorded for advisor responses
- [ ] Cost tracking updated (if in claude-octopus context)
- [ ] Results presented to user in chat
- [ ] Debate folder path provided to user


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
Knowledge mode "deliberate" phase → Run $skill-debate to get multiple perspectives
→ Use synthesis for final decision
```


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
- Quick (1 round): 0.02 USD - 0.05 USD
- Thorough (3 rounds): 0.10 USD - 0.20 USD
- Adversarial (5 rounds): 0.25 USD - 0.50 USD

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


**Ready to debate!** Users can invoke with `$skill-debate <question>` or natural language.
