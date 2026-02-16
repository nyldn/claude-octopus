---
name: flow-define
aliases:
  - define
  - define-workflow
  - grasp
  - grasp-workflow
description: Multi-AI requirements scoping using Codex and Gemini CLIs (Double Diamond Define phase)

  PRIORITY TRIGGERS (always invoke): "octo define", "octo scope", "co-define", "co-scope"

  DO NOT use for: implementation tasks (use flow-develop), research (use flow-discover),
  review/validation (use flow-deliver), or built-in commands.

# Claude Code v2.1.12+ Integration
agent: Plan
context: fork
task_management: true
task_dependencies:
  - flow-discover
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - synthesis_file_exists
trigger: |
  AUTOMATICALLY ACTIVATE when user requests clarification or scoping:
  - "define the requirements for X"
  - "clarify the scope of Y"
  - "what exactly does X need to do"
  - "help me understand the problem with Y"
  - "scope out the Z feature"
  - "what are the specific requirements for X"

  DO NOT activate for:
  - Implementation tasks (use tangle-workflow)
  - Research tasks (use probe-workflow)
  - Review tasks (use ink-workflow)
  - Built-in commands (/plugin, /help, etc.)
---

## Pre-Definition: State Check

Before starting definition:
1. Read `.octo/STATE.md` to verify Discover phase complete
2. Update STATE.md:
   - current_phase: 2
   - phase_position: "Definition"
   - status: "in_progress"

```bash
# Verify Discover phase is complete
if [[ -f ".octo/STATE.md" ]]; then
  discover_status=$("${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" get_phase_status 1)
  if [[ "$discover_status" != "complete" ]]; then
    echo "⚠️ Warning: Discover phase not marked complete. Consider running discovery first."
  fi
fi

# Update state for Definition phase
"${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" update_state \
  --phase 2 \
  --position "Definition" \
  --status "in_progress"
```

---

## ⚠️ EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact sequence.

### STEP 1: Display Visual Indicators (MANDATORY - BLOCKING)

**Check provider availability:**

```bash
command -v codex &> /dev/null && codex_status="Available ✓" || codex_status="Not installed ✗"
command -v gemini &> /dev/null && gemini_status="Available ✓" || gemini_status="Not installed ✗"
```

**Display this banner BEFORE orchestrate.sh execution:**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider definition mode
🎯 Define Phase: [Brief description of what you're defining/scoping]

Provider Availability:
🔴 Codex CLI: ${codex_status} - Technical requirements analysis
🟡 Gemini CLI: ${gemini_status} - Business context and constraints
🔵 Claude: Available ✓ - Consensus building and synthesis

💰 Estimated Cost: $0.01-0.05
⏱️  Estimated Time: 2-5 minutes
```

**Validation:**
- If BOTH Codex and Gemini unavailable → STOP, suggest: `/octo:setup`
- If ONE unavailable → Continue with available provider(s)
- If BOTH available → Proceed normally

**DO NOT PROCEED TO STEP 2 until banner displayed.**

---

### STEP 2: Read Prior State (MANDATORY - State Management)

**Before executing the workflow, read any prior context:**

```bash
# Initialize state if needed
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state

# Set current workflow
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" set_current_workflow "flow-define" "define"

# Get prior decisions (if any)
prior_decisions=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_decisions "all")

# Get context from discover phase
discover_context=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_context "discover")

# Display what you found (if any)
if [[ "$discover_context" != "null" ]]; then
  echo "📋 Building on discovery findings:"
  echo "  $discover_context"
fi

if [[ "$prior_decisions" != "[]" && "$prior_decisions" != "null" ]]; then
  echo "📋 Respecting prior decisions:"
  echo "$prior_decisions" | jq -r '.[] | "  - \(.decision) (\(.phase)): \(.rationale)"'
fi
```

**This provides context from:**
- Discovery phase research (if completed)
- Prior architectural decisions
- User vision captured earlier

**DO NOT PROCEED TO STEP 3 until state read.**

---

### STEP 3: Phase Discussion - Capture User Vision (MANDATORY - Context Gathering)

**Before executing expensive multi-AI orchestration, capture the user's vision to scope the work effectively.**

**Ask clarifying questions using AskUserQuestion:**

```
Use AskUserQuestion tool to ask:

1. **User Experience**
   Question: "How should users interact with this feature?"
   Header: "User Flow"
   Options:
   - label: "API-first (programmatic access)"
     description: "Build API endpoints first, UI later"
   - label: "UI-first (user-facing interface)"
     description: "Build user interface first, API supports it"
   - label: "Both simultaneously"
     description: "Develop API and UI in parallel"
   - label: "Not applicable"
     description: "This feature doesn't have a user interaction"

2. **Implementation Approach**
   Question: "What technical approach do you prefer?"
   Header: "Approach"
   Options:
   - label: "Fastest to market"
     description: "Prioritize speed, use existing libraries"
   - label: "Most maintainable"
     description: "Focus on clean architecture, may take longer"
   - label: "Best performance"
     description: "Optimize for speed and efficiency"
   - label: "Let AI decide"
     description: "Use multi-AI research to determine best approach"

3. **Scope Boundaries**
   Question: "What's explicitly OUT of scope for this phase?"
   Header: "Out of Scope"
   Options:
   - label: "Testing and QA"
     description: "Focus on implementation, test later"
   - label: "Performance optimization"
     description: "Get it working first, optimize later"
   - label: "Edge cases"
     description: "Handle happy path only initially"
   - label: "Nothing excluded"
     description: "Everything is in scope"
   multiSelect: true
```

**After gathering answers, create context file:**

```bash
# Source context manager
source "${CLAUDE_PLUGIN_ROOT}/scripts/context-manager.sh"

# Extract user answers from AskUserQuestion results
user_flow="[Answer from question 1]"
approach="[Answer from question 2]"
out_of_scope="[Answer from question 3]"

# Create context file with user vision
create_templated_context \
  "define" \
  "$(echo "$USER_REQUEST" | head -c 50)..." \
  "User wants: $user_flow approach with $approach priority" \
  "$approach" \
  "Implementation of requested feature" \
  "$out_of_scope"

echo "📋 Context captured and saved to .claude-octopus/context/define-context.md"
```

**This context will be used to:**
- Scope the multi-AI research (discover phase)
- Focus the requirements definition (define phase)
- Guide implementation decisions (develop phase)
- Validate against user expectations (deliver phase)

**DO NOT PROCEED TO STEP 4 until context captured.**

---

### STEP 4: Execute orchestrate.sh define (MANDATORY - Use Bash Tool)

**You MUST execute this command via the Bash tool:**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh define "<user's clarification request>"
```

**CRITICAL: You are PROHIBITED from:**
- ❌ Defining requirements directly without calling orchestrate.sh
- ❌ Using direct analysis instead of orchestrate.sh
- ❌ Claiming you're "simulating" the workflow
- ❌ Proceeding to Step 3 without running this command

**This is NOT optional. You MUST use the Bash tool to invoke orchestrate.sh.**

#### What Users See During Execution (v7.16.0+)

If running in Claude Code v2.1.16+, users will see **real-time progress indicators** in the task spinner:

**Phase 1 - External Provider Execution (Parallel):**
- 🔴 Analyzing technical requirements (Codex)...
- 🟡 Clarifying user needs and context (Gemini)...

**Phase 2 - Synthesis (Sequential):**
- 🔵 Building consensus on problem definition...

These spinner verb updates happen automatically - orchestrate.sh calls `update_task_progress()` before each agent execution. Users see exactly which provider is working and what it's doing.

**If NOT running in Claude Code v2.1.16+:** Progress indicators are silently skipped, no errors shown.

---

### STEP 5: Verify Execution (MANDATORY - Validation Gate)

**After orchestrate.sh completes, verify it succeeded:**

```bash
# Find the latest synthesis file (created within last 10 minutes)
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "grasp-synthesis-*.md" -mmin -10 2>/dev/null | head -n1)

if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "❌ VALIDATION FAILED: No synthesis file found"
  echo "orchestrate.sh did not execute properly"
  exit 1
fi

echo "✅ VALIDATION PASSED: $SYNTHESIS_FILE"
cat "$SYNTHESIS_FILE"
```

**If validation fails:**
1. Report error to user
2. Show logs from `~/.claude-octopus/logs/`
3. DO NOT proceed with presenting results
4. DO NOT substitute with direct analysis

---

### STEP 6: Update State (MANDATORY - Post-Execution)

**After synthesis is verified, record findings and decisions in state:**

```bash
# Extract key definition from synthesis
key_definition=$(head -50 "$SYNTHESIS_FILE" | grep -A 3 "## Problem Definition\|## Summary" | tail -3 | tr '\n' ' ')

# Record any architectural decisions made
# (You should identify these from the synthesis - e.g., tech stack, approach, patterns)
decision_made=$(echo "$key_definition" | grep -o "decided to\|chose to\|selected\|using [A-Za-z0-9 ]*" | head -1)

if [[ -n "$decision_made" ]]; then
  "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_decision \
    "define" \
    "$decision_made" \
    "Consensus from multi-AI definition phase"
fi

# Update define phase context
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "define" \
  "$key_definition"

# Update metrics
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "phases_completed" "1"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "codex"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "gemini"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "claude"
```

**DO NOT PROCEED TO STEP 7 until state updated.**

---

### STEP 7: Present Problem Definition (Only After Steps 1-6 Complete)

Read the synthesis file and present:
- Core requirements (must have, should have, nice to have)
- Technical constraints
- User needs
- Edge cases to handle
- Out of scope items
- Perspectives from all providers
- Requirements checklist
- Next steps (usually tangle phase for implementation)

**Include attribution:**
```
---
*Multi-AI Problem Definition powered by Claude Octopus*
*Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude*
*Full problem definition: $SYNTHESIS_FILE*
```

---

# Define Workflow - Define Phase 🎯

## ⚠️ MANDATORY: Visual Indicators Protocol

**BEFORE executing ANY workflow actions, you MUST output this banner:**

**First, check task status (if available):**
```bash
task_status=$("${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" get-task-status 2>/dev/null || echo "")
```

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider definition mode
🎯 Define Phase: [Brief description of what you're defining/scoping]
📋 Session: ${CLAUDE_SESSION_ID}
📝 Tasks: ${task_status}

Providers:
🔴 Codex CLI - Technical requirements analysis
🟡 Gemini CLI - Business context and constraints
🔵 Claude - Consensus building and synthesis
```

**This is NOT optional.** Users need to see which AI providers are active and understand they are being charged for external API calls (🔴 🟡).

---

**Part of Double Diamond: DEFINE** (convergent thinking)

```
        DEFINE (grasp)

         \         /
          \       /
           \     /
            \   /
             \ /

          Converge to
           problem
```

## What This Workflow Does

The **define** phase clarifies and scopes problems using external CLI providers:

1. **🔴 Codex CLI** - Technical requirements analysis, edge cases, constraints
2. **🟡 Gemini CLI** - User needs, business requirements, context understanding
3. **🔵 Claude (You)** - Problem synthesis and requirement definition

This is the **convergent** phase after discovery - we narrow down from broad research to specific problem definition.

---

## When to Use Define

Use define when you need:
- **Requirement Definition**: "Define exactly what the auth system needs to do"
- **Problem Clarification**: "Clarify the caching requirements"
- **Scope Definition**: "What's the scope of the notification feature?"
- **Constraint Identification**: "What are the technical constraints for X?"
- **Edge Case Analysis**: "What edge cases do we need to handle for Y?"
- **Requirement Validation**: "Are these requirements complete for Z?"

**Don't use define for:**
- Research and exploration (use probe-workflow)
- Building implementations (use tangle-workflow)
- Code review and validation (use ink-workflow)
- Simple questions Claude can answer

---

## Visual Indicators

Before execution, you'll see:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider problem definition
🎯 Define Phase: Clarifying requirements and scope

Providers:
🔴 Codex CLI - Technical requirements
🟡 Gemini CLI - Business needs and context
🔵 Claude - Problem synthesis
```

---

## How It Works

### Step 1: Invoke Grasp Phase

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh define "<user's clarification request>"
```

### Step 2: Multi-Provider Problem Definition

The orchestrate.sh script will:
1. Call **Codex CLI** for technical requirement analysis
2. Call **Gemini CLI** for business/user need analysis
3. You (Claude) synthesize into clear problem definition
4. Identify gaps and missing requirements

### Step 3: Read Results

Results are saved to:
```
~/.claude-octopus/results/${SESSION_ID}/grasp-synthesis-<timestamp>.md
```

### Step 4: Present Problem Definition

Read the synthesis and present clear, actionable requirements to the user.

---

## Implementation Instructions

When this skill is invoked, follow the EXECUTION CONTRACT above exactly. The contract includes:

1. **Blocking Step 1**: Display visual indicators with provider status
2. **Blocking Step 2**: Execute orchestrate.sh define via Bash tool
3. **Blocking Step 3**: Verify synthesis file exists
4. **Step 4**: Present formatted problem definition

Each step is **mandatory and blocking** - you cannot proceed to the next step until the current one completes successfully.

### Task Management Integration

Create tasks to track execution progress:

```javascript
// At start of skill execution
TaskCreate({
  subject: "Execute define workflow with multi-AI providers",
  description: "Run orchestrate.sh define for problem clarification",
  activeForm: "Running multi-AI define workflow"
})

// Mark in_progress when calling orchestrate.sh
TaskUpdate({taskId: "...", status: "in_progress"})

// Mark completed ONLY after synthesis file verified
TaskUpdate({taskId: "...", status: "completed"})
```

### Error Handling

If any step fails:
- **Step 1 (Providers)**: If both unavailable, suggest `/octo:setup` and STOP
- **Step 2 (orchestrate.sh)**: Show bash error, check logs, report to user
- **Step 3 (Validation)**: If synthesis missing, show orchestrate.sh logs, DO NOT substitute with direct analysis

Never fall back to direct analysis if orchestrate.sh execution fails. Report the failure and let the user decide how to proceed.

### Problem Definition Format

After successful execution, present problem definition with:
   ```
   # Problem Definition: <task>

   ## Core Requirements
   [Essential requirements that must be met]

   ## Technical Constraints
   [Technical limitations and considerations]

   ## User Needs
   [What users actually need from this]

   ## Edge Cases to Handle
   [Specific edge cases identified]

   ## Out of Scope
   [What is explicitly NOT included]

   ## Perspectives

   ### Codex Analysis (Technical)
   [Technical requirements and constraints]

   ### Gemini Analysis (Business/User)
   [User needs and business context]

   ### Claude Synthesis
   [Integrated problem definition]

   ## Requirements Checklist
   - [ ] Functional requirements defined
   - [ ] Non-functional requirements defined
   - [ ] Technical constraints identified
   - [ ] Edge cases documented
   - [ ] Out-of-scope items clarified
   - [ ] Success criteria established

   ## Next Steps
   [Recommended next actions - usually tangle phase for implementation]

   Full problem definition saved to: <synthesis file path>
   ```

---

## Example Usage

### Example 1: Define Auth Requirements

```
User: Define the exact requirements for our user authentication system

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider problem definition
🎯 Define Phase: Clarifying authentication requirements

[Executes: ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh define "Define exact requirements for user authentication system"]

[After completion, reads synthesis and presents:]

# Problem Definition: User Authentication System

## Core Requirements

### Must Have (P0)
1. User registration with email + password
2. Secure login with JWT token generation
3. Password reset via email
4. Session management with token refresh
5. Logout (token invalidation)

### Should Have (P1)
6. Remember me functionality
7. Account lockout after failed attempts
8. Email verification on signup
9. Password strength requirements

### Nice to Have (P2)
10. OAuth social login (Google, GitHub)
11. Two-factor authentication
12. Single sign-on (SSO)

## Technical Constraints

- Must work with existing Express.js backend
- Token storage: Redis for production, in-memory for dev
- Password hashing: bcrypt (min 12 rounds)
- Token expiry: Access token 15min, refresh token 7 days
- Rate limiting: Max 5 login attempts per 15min per IP

## User Needs

- Simple registration process (< 2 minutes)
- Secure password recovery without support tickets
- Stay logged in across browser sessions (remember me)
- Clear error messages for failed login
- Ability to log out from all devices

## Edge Cases to Handle

1. **Concurrent logins**: Same user, multiple devices
2. **Expired tokens**: Graceful refresh without re-login
3. **Password reset race condition**: Multiple reset requests
4. **Account enumeration**: Don't reveal if email exists
5. **Token theft**: Detect suspicious login locations
6. **Deleted users**: Handle auth for soft-deleted accounts

## Out of Scope

- ❌ Biometric authentication (fingerprint, face ID)
- ❌ LDAP/Active Directory integration
- ❌ Custom OAuth provider implementation
- ❌ Device fingerprinting
- ❌ Passwordless email magic links

## Perspectives

### Codex Analysis (Technical)
- JWT structure: { userId, role, exp, iat, jti }
- Database schema for users, refresh_tokens, password_resets
- API endpoints: POST /register, POST /login, POST /logout, POST /refresh, POST /reset-password
- Middleware for auth verification
- Security: HTTPS only, secure cookies, CSRF protection

### Gemini Analysis (Business/User)
- User journey: Registration → Email verification → Login → Access app
- Error handling: Clear messages without security leaks
- Performance: Auth checks < 50ms
- Compliance: GDPR (data deletion), password policies
- Analytics: Track signup conversion, failed login rates

### Claude Synthesis
- Hybrid approach: Core auth (P0) first, iterate on P1/P2
- Security-first: All requirements validated against OWASP
- User experience: Balance security with convenience
- Scalable: Design for 100K users, plan for 1M+

## Requirements Checklist
- ✅ Functional requirements defined (registration, login, reset)
- ✅ Non-functional requirements defined (performance, security)
- ✅ Technical constraints identified (Express, Redis, bcrypt)
- ✅ Edge cases documented (6 critical cases)
- ✅ Out-of-scope items clarified (4 items)
- ✅ Success criteria established (< 2min registration, < 50ms auth)

## Next Steps

1. **Immediate**: Review and confirm requirements with stakeholders
2. **Then**: Use **tangle-workflow** to implement the auth system
3. **Finally**: Use **ink-workflow** to validate implementation

Ready to proceed to implementation?

Full problem definition saved to: ~/.claude-octopus/results/abc-123/grasp-synthesis-20250118-144530.md
```

### Example 2: Clarify Feature Scope

```
User: What exactly does the notification feature need to do?

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider problem definition
🎯 Define Phase: Clarifying notification requirements

[Executes grasp workflow]

[Presents detailed problem definition with:]
- Core notification types (email, push, in-app)
- Delivery requirements (real-time vs batched)
- User preferences (opt-in/out, frequency)
- Technical constraints (message queue, delivery tracking)
- Edge cases (offline users, rate limits)

Ready to build once requirements are confirmed.
```

---

## Integration with Other Workflows

Grasp is the **second phase** of the Double Diamond:

```
PROBE (Discover) → GRASP (Define) → TANGLE (Develop) → INK (Deliver)
```

**Typical flow:**
1. **Probe**: "Research authentication best practices" (discover options)
2. **Grasp**: "Define exact requirements for our auth system" (narrow down)
3. **Tangle**: "Implement the auth system" (build it)
4. **Ink**: "Validate the auth implementation" (deliver it)

Or use grasp standalone when requirements are unclear.

---

## Quality Checklist

Before completing grasp workflow, ensure:

- [ ] Core requirements clearly defined (must have, should have, nice to have)
- [ ] Technical constraints documented
- [ ] User needs understood and articulated
- [ ] Edge cases identified and documented
- [ ] Out-of-scope items explicitly listed
- [ ] Success criteria established
- [ ] Next steps recommended to user
- [ ] Full problem definition shared

---

## Cost Awareness

**External API Usage:**
- 🔴 Codex CLI uses your OPENAI_API_KEY (costs apply)
- 🟡 Gemini CLI uses your GEMINI_API_KEY (costs apply)
- 🔵 Claude analysis included with Claude Code

Grasp workflows typically cost $0.01-0.05 per task depending on complexity.

---

## Post-Definition: State Update

After definition completes:
1. Update `.octo/STATE.md` with completion
2. Populate `.octo/ROADMAP.md` with defined phases and success criteria

```bash
# Update state after Definition completion
"${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" update_state \
  --status "complete" \
  --history "Define phase completed"

# Populate ROADMAP.md with defined requirements
if [[ -f "$SYNTHESIS_FILE" ]]; then
  echo "📝 Updating .octo/ROADMAP.md with defined phases..."
  "${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" update_roadmap \
    --from-synthesis "$SYNTHESIS_FILE"
fi
```

---

**Ready to define!** This skill activates automatically when users request requirement clarification or problem definition.
