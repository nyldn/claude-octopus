---
command: octo
description: Smart router - Single entry point with natural language intent detection
version: 1.0.0
category: workflow
tags: [router, intent-detection, workflow, smart-routing]
created: 2025-02-03
updated: 2025-02-03
---

# Smart Router (/octo)

Single entry point for all Claude Octopus workflows with natural language intent detection. The router analyzes your request and automatically routes to the optimal workflow.

## Usage

```bash
# Just describe what you want - the router figures out the workflow
/octo research OAuth authentication patterns
/octo build user authentication system
/octo validate src/auth.ts
/octo should we use Redis or Memcached?
/octo create a complete e-commerce platform
```

## Routing Intelligence

The router uses keyword matching and confidence scoring to determine the best workflow:

### Routing Table

| Intent | Keywords | Routes To | Confidence Threshold |
|--------|----------|-----------|---------------------|
| **Research** | research, investigate, explore, learn, study, understand, analyze | `/octo:discover` | 70% |
| **Build (Clear)** | build X, create Y, implement Z, develop X | `/octo:develop` | 80% |
| **Build (Vague)** | build, create, make (without specific target) | `/octo:plan` | 60% |
| **Validate** | validate, review, check, audit, inspect, verify | `/octo:validate` | 75% |
| **Debate** | should, vs, or, compare, versus, decide, which | `/octo:debate` | 70% |
| **Lifecycle** | end-to-end, complete, full, entire, whole | `/octo:embrace` | 85% |

### Confidence Levels

- **>80%**: Auto-routes with notification ("Routing to [workflow]...")
- **70-80%**: Shows suggestion and asks for confirmation
- **<70%**: Asks user to clarify intent

## Examples

### Research Intent
```bash
/octo research OAuth security patterns
# → Routes to /octo:discover
# 🔍 Multi-AI research and exploration
```

### Build Intent (Clear)
```bash
/octo build user authentication with JWT
# → Routes to /octo:develop
# 🛠️ Multi-AI implementation with quality gates
```

### Build Intent (Vague)
```bash
/octo build something for users
# → Routes to /octo:plan (with clarification)
# 🎯 Clarifies requirements before routing
```

### Validation Intent
```bash
/octo validate the authentication implementation
# → Routes to /octo:validate (NEW in v7.24.0)
# 🛡️ Multi-AI quality assurance and validation
```

### Debate Intent
```bash
/octo should we use TypeScript or JavaScript?
# → Routes to /octo:debate
# 🐙 Three-way AI debate (Codex, Gemini, Claude)
```

### Lifecycle Intent
```bash
/octo complete implementation of payment system
# → Routes to /octo:embrace
# 🐙 Full 4-phase workflow (Discover → Define → Develop → Deliver)
```

## Fallback Behavior

If the router can't determine intent with confidence:

1. Lists possible workflows with descriptions
2. Asks user to pick or rephrase
3. Provides examples for each workflow

## Direct Access

You can always bypass the router and call workflows directly:

```bash
/octo:discover     # Research phase
/octo:define       # Definition phase
/octo:develop      # Development phase
/octo:deliver      # Delivery phase
/octo:debate       # AI debate
/octo:embrace      # Full lifecycle
/octo:plan         # Requirements planning
/octo:validate     # Quality validation (NEW)
```

## Advanced Usage

### Force Specific Workflow
```bash
# Override router with explicit workflow
/octo:develop build payment system
```

### Multi-Provider Override
```bash
# Use model configuration with router
export OCTOPUS_CODEX_MODEL="claude-opus-4-6"
/octo research advanced ML architectures
# → Uses premium model for research
```

### Chain Workflows
```bash
# Router can suggest chaining
/octo build and validate authentication system
# → Suggests: /octo:develop → /octo:validate
```

---

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo <query>`, you MUST:

### 1. Parse User Query

Extract the user's natural language request and identify keywords.

### 2. Analyze Intent

Match keywords against the routing table:

**Research Keywords**: research, investigate, explore, learn, study, understand, analyze
- If found → Research intent

**Build (Clear) Keywords**: "build X", "create Y", "implement Z", "develop X" (with specific target)
- If found → Build (clear) intent

**Build (Vague) Keywords**: build, create, make (without specific target)
- If found → Build (vague) intent

**Validation Keywords**: validate, review, check, audit, inspect, verify
- If found → Validation intent

**Debate Keywords**: should, vs, or, compare, versus, decide, which
- If found → Debate intent

**Lifecycle Keywords**: end-to-end, complete, full, entire, whole, everything
- If found → Lifecycle intent

### 3. Calculate Confidence Score

Score = (matching keywords / total keywords) * 100

**Adjust for context:**
- Specific target mentioned (+20%)
- Multiple workflow keywords found (-30% for ambiguity)
- Technical terms present (+10%)

### 4. Route Based on Confidence

**High Confidence (>80%)**:
```
✓ Routing to [workflow]: [brief description]

[Execute the workflow]
```

**Medium Confidence (70-80%)**:
```
I think you want: [workflow]
[Brief description]

Should I proceed with this workflow? (yes/no)
```
Wait for user confirmation before routing.

**Low Confidence (<70%)**:
```
I'm not sure which workflow fits best. Here are your options:

1. **Research** (/octo:discover) - Multi-AI research and exploration
2. **Build** (/octo:develop) - Implementation with quality gates
3. **Validate** (/octo:validate) - Quality assurance and validation
4. **Debate** (/octo:debate) - Three-way AI debate
5. **Lifecycle** (/octo:embrace) - Full 4-phase workflow

Which would you like, or would you like to rephrase your request?
```

### 5. Execute Target Workflow

Once routed, execute the target workflow using the Skill tool:

```bash
# For research intent
Skill: "discover", args: "<user query>"

# For build (clear) intent
Skill: "develop", args: "<user query>"

# For build (vague) intent
Skill: "plan", args: "<user query>"

# For validation intent
Skill: "validate", args: "<user query>"  # NEW in v7.24.0

# For debate intent
Skill: "debate", args: "<user query>"

# For lifecycle intent
Skill: "embrace", args: "<user query>"
```

### 6. Display Visual Indicators

When routing to multi-AI workflows, display the appropriate banner:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - [Workflow Type]
[Phase Emoji] [Phase Name]: [Brief description]

Providers:
🔴 Codex CLI - [Provider's role]
🟡 Gemini CLI - [Provider's role]
🔵 Claude - [Your role]
```

### Validation Gates

- ✅ User query parsed
- ✅ Intent detected with confidence score
- ✅ Routing decision made (with user confirmation if needed)
- ✅ Target workflow executed via Skill tool
- ✅ Visual indicators displayed (for multi-AI workflows)

### Prohibited Actions

- ❌ Executing workflows without user confirmation (if confidence < 80%)
- ❌ Assuming intent without keyword analysis
- ❌ Routing to workflows that don't exist
- ❌ Skipping visual indicators for multi-AI workflows
- ❌ Simulating workflow execution (must use Skill tool)

---

## Routing Examples (Detailed)

### Example 1: High Confidence Research
```
User: /octo research OAuth 2.0 security best practices

Analysis:
- Keywords: "research" (research intent)
- Target: "OAuth 2.0 security best practices" (specific)
- Confidence: 95% (high)

Response:
✓ Routing to Research workflow (/octo:discover)

🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching OAuth 2.0 security best practices

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis

[Execute /octo:discover]
```

### Example 2: Medium Confidence Build
```
User: /octo create authentication

Analysis:
- Keywords: "create" (build intent, vague)
- Target: "authentication" (somewhat specific)
- Confidence: 75% (medium)

Response:
I think you want: Implementation workflow (/octo:develop)
This will build the authentication system with multi-AI quality gates.

However, since the requirements aren't fully clear, I could also route to:
- Planning workflow (/octo:plan) to clarify requirements first

Should I proceed with implementation, or plan first? (implement/plan)
```

### Example 3: Low Confidence Ambiguous
```
User: /octo do something with the database

Analysis:
- Keywords: "do" (no clear intent)
- Target: "database" (vague)
- Confidence: 40% (low)

Response:
I'm not sure which workflow fits best. What would you like to do?

1. **Research** - Investigate database patterns and best practices
2. **Build** - Implement database features or schema
3. **Validate** - Review existing database code
4. **Debate** - Compare database options (SQL vs NoSQL, etc.)

Please clarify what you'd like to accomplish.
```

### Example 4: Debate Intent
```
User: /octo should we use Redis or Memcached for session storage?

Analysis:
- Keywords: "should", "or" (debate intent)
- Target: "Redis or Memcached" (comparison)
- Confidence: 90% (high)

Response:
✓ Routing to AI Debate Hub (/octo:debate)

🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: Redis vs Memcached for session storage

Participants:
🔴 Codex CLI - Technical perspective
🟡 Gemini CLI - Ecosystem perspective
🔵 Claude - Moderator and synthesis

[Execute /octo:debate]
```

---

## Notes

- The router is optimized for natural language - users don't need to learn command syntax
- All existing `/octo:*` commands still work and bypass the router
- Router learns from user corrections (future enhancement)
- Confidence thresholds are tunable in future versions
- Works seamlessly with model configuration (`OCTOPUS_CODEX_MODEL`, etc.)
