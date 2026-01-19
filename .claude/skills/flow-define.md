---
name: flow-define
aliases:
  - define
  - define-workflow
  - grasp
  - grasp-workflow
description: |
  Define phase workflow - Clarify and scope problems using external CLI providers.
  Part of the Double Diamond methodology (Define phase).
  Uses Codex and Gemini CLIs for multi-perspective problem definition.
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

# Define Workflow - Define Phase 🎯

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
./scripts/orchestrate.sh define "<user's clarification request>"
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

When this skill activates:

1. **Confirm the clarification task**
   ```
   I'll clarify the requirements for "<task>" using multiple AI perspectives.

   🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider problem definition
   🎯 Define Phase: Defining requirements
   ```

2. **Execute grasp workflow**
   ```bash
   ./scripts/orchestrate.sh define "<user's clarification request>"
   ```

3. **Monitor execution**
   - Watch for provider responses
   - Check for requirement gaps
   - Note conflicting perspectives

4. **Read synthesis results**
   ```bash
   # Find the latest synthesis file
   SYNTHESIS_FILE=$(ls -t ~/.claude-octopus/results/${CLAUDE_CODE_SESSION}/grasp-synthesis-*.md 2>/dev/null | head -n1)

   # Read problem definition
   cat "$SYNTHESIS_FILE"
   ```

5. **Present problem definition in chat**
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

[Executes: ./scripts/orchestrate.sh define "Define exact requirements for user authentication system"]

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

**Ready to define!** This skill activates automatically when users request requirement clarification or problem definition.
