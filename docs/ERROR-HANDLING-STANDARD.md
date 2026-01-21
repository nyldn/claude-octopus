# Error Handling Standard

This document defines conventions for error handling in Claude Octopus skills.

## Why Standardized Error Handling?

1. **Consistency** - Users know what to expect when things go wrong
2. **Recovery** - Clear paths to resolution
3. **Graceful degradation** - Continue with reduced functionality when possible
4. **Debugging** - Structured errors are easier to diagnose

---

## Error Categories

### Category 1: Blocking Errors

**Definition:** Cannot proceed without resolution.

**Format:**
```markdown
🛑 **Error: [Error Type]**

**What happened:**
[Clear explanation of the error]

**Why this matters:**
[Impact on the workflow]

**To resolve:**
1. [Resolution step 1]
2. [Resolution step 2]
3. [Resolution step 3]

**Alternative:**
[If there's a workaround]
```

**Example:**
```markdown
🛑 **Error: Provider Unavailable**

**What happened:**
Codex CLI is not responding (timeout after 30 seconds).

**Why this matters:**
Cannot complete multi-agent research without Codex perspective.

**To resolve:**
1. Check if OPENAI_API_KEY is set correctly
2. Verify internet connectivity
3. Try again in a few minutes (API may be rate-limited)

**Alternative:**
I can proceed with Gemini + Claude only (reduced coverage).
Would you like me to continue with available providers?
```

### Category 2: Warning Errors

**Definition:** Can proceed, but with limitations.

**Format:**
```markdown
⚠️ **Warning: [Warning Type]**

**What happened:**
[Clear explanation]

**Impact:**
[What will be different/limited]

**Proceeding with:**
[What will happen next]
```

**Example:**
```markdown
⚠️ **Warning: Partial Provider Coverage**

**What happened:**
Gemini CLI returned an error (rate limit exceeded).

**Impact:**
Research will use Codex + Claude only (2 of 3 providers).
Some alternative perspectives may be missed.

**Proceeding with:**
Continuing research with available providers.
```

### Category 3: Informational Notices

**Definition:** No action needed, but user should be aware.

**Format:**
```markdown
ℹ️ **Notice: [Notice Type]**

[Brief explanation]
```

**Example:**
```markdown
ℹ️ **Notice: Using Cached Results**

Provider responses from 15 minutes ago are being reused.
Fresh results would require re-running the research phase.
```

---

## Standard Error Types

### Provider Errors

| Error | Icon | Recovery |
|-------|------|----------|
| Provider timeout | 🛑 | Retry or skip provider |
| Rate limit exceeded | ⚠️ | Wait and retry, or skip |
| Authentication failed | 🛑 | Check API key configuration |
| Provider unavailable | ⚠️ | Use alternative providers |

### Content Errors

| Error | Icon | Recovery |
|-------|------|----------|
| URL validation failed | 🛑 | Provide alternative URL |
| Fetch timeout | ⚠️ | Retry or provide content directly |
| Content too large | ⚠️ | Truncate and proceed |
| Malformed content | ⚠️ | Best-effort parsing |

### Workflow Errors

| Error | Icon | Recovery |
|-------|------|----------|
| Quality gate failed | ⚠️ | Retry phase or lower threshold |
| Session not found | 🛑 | Start new session |
| Circular dependency | 🛑 | Refactor workflow |
| Missing dependency | 🛑 | Install or configure |

---

## Error Handling Section Template

Every skill SHOULD include an Error Handling section:

```markdown
## Error Handling

### [Error Scenario 1]

**When this happens:**
[Trigger condition]

**Response:**
[What Claude should do]

**User communication:**
```markdown
[Icon] **[Error Type]**

[Message to show user]
```

### [Error Scenario 2]

[Continue pattern...]

### Fallback Behavior

If all error handling fails:
1. [Fallback step 1]
2. [Fallback step 2]
3. [Ultimate fallback]
```

---

## Graceful Degradation Patterns

### Pattern 1: Provider Fallback

```
PREFER: Codex + Gemini + Claude (full coverage)
  ↓ (if Codex fails)
FALLBACK: Gemini + Claude (reduced coverage)
  ↓ (if Gemini fails)
FALLBACK: Claude only (minimal coverage)
  ↓ (if Claude fails)
ERROR: Cannot proceed (all providers failed)
```

### Pattern 2: Content Fallback

```
PREFER: Full content analysis
  ↓ (if content too large)
FALLBACK: Truncated analysis (first 100K chars)
  ↓ (if fetch fails)
FALLBACK: User-provided content paste
  ↓ (if still fails)
ERROR: Cannot proceed without content
```

### Pattern 3: Quality Fallback

```
PREFER: 75% quality threshold
  ↓ (if threshold not met)
RETRY: Up to 3 attempts
  ↓ (if still not met)
OPTION: Proceed with warning OR lower threshold to 50%
  ↓ (if user declines)
ERROR: Quality requirements not met
```

---

## Recovery Prompts

### When User Input Needed

```markdown
**How would you like to proceed?**

1. **Retry** - Try again with current settings
2. **Skip** - Continue without this component
3. **Alternative** - [Describe alternative approach]
4. **Abort** - Stop the workflow

Type the number or describe what you'd like to do.
```

### When Automatic Recovery Possible

```markdown
ℹ️ **Automatic Recovery**

[Error] occurred but I've automatically:
- [Recovery action 1]
- [Recovery action 2]

Continuing with workflow...
```

---

## Logging Standards

### Error Log Format

```
[TIMESTAMP] [LEVEL] [COMPONENT] [MESSAGE]
[TIMESTAMP] [LEVEL] [COMPONENT] [CONTEXT]
```

**Example:**
```
2026-01-21T06:30:00Z ERROR codex-agent Timeout after 30s
2026-01-21T06:30:00Z ERROR codex-agent prompt="research OAuth patterns" session=abc123
```

### Log Levels

| Level | When to Use |
|-------|-------------|
| ERROR | Blocking errors requiring user intervention |
| WARN | Non-blocking issues, degraded functionality |
| INFO | Normal workflow events |
| DEBUG | Detailed debugging information |

---

## Integration Example

```markdown
## Error Handling

### Provider Timeout

**When this happens:**
A provider (Codex/Gemini) doesn't respond within 30 seconds.

**Response:**
1. Log the timeout with context
2. Mark provider as temporarily unavailable
3. Continue with remaining providers
4. Note reduced coverage in output

**User communication:**
```markdown
⚠️ **Warning: Provider Timeout**

**What happened:**
Codex CLI timed out after 30 seconds.

**Impact:**
Research will proceed with Gemini + Claude (2 of 3 providers).

**Proceeding with:**
Available providers. Results may have reduced technical depth.
```

### All Providers Failed

**When this happens:**
All external providers (Codex, Gemini) fail.

**Response:**
1. Log all failures
2. Offer Claude-only mode
3. If declined, abort with clear message

**User communication:**
```markdown
🛑 **Error: No External Providers Available**

**What happened:**
Both Codex and Gemini are unavailable.

**To resolve:**
1. Check your API keys are configured
2. Verify internet connectivity
3. Run `/co:setup` to diagnose

**Alternative:**
I can continue with Claude-only analysis (reduced multi-perspective coverage).
Would you like to proceed?
```

### Fallback Behavior

If all error handling fails:
1. Save any partial results to session
2. Provide clear error summary
3. Suggest running `/co:debug` for diagnosis
4. Offer to restart from last checkpoint
```

---

## Anti-Patterns

### DON'T: Silent Failures

```markdown
❌ Bad:
[Error occurs but user sees no message]
[Workflow continues with incomplete data]
```

### DON'T: Technical Jargon

```markdown
❌ Bad:
Error: ECONNREFUSED 127.0.0.1:443 SSL_HANDSHAKE_FAILED

✅ Good:
🛑 **Error: Connection Failed**
Could not connect to the provider. Check your internet connection.
```

### DON'T: Dead Ends

```markdown
❌ Bad:
Error occurred. Workflow stopped.

✅ Good:
🛑 **Error: [Type]**
[Explanation]
**Options:** [1] [2] [3]
```

---

## Checklist for Skills

When adding error handling to a skill:

- [ ] All external calls have error handling
- [ ] User-facing messages use standard format
- [ ] Fallback behaviors are documented
- [ ] Recovery options are provided
- [ ] Errors are logged with context
- [ ] No silent failures

---

## Related Documentation

- [OUTPUT-FORMAT-STANDARD.md](./OUTPUT-FORMAT-STANDARD.md) - Output templates
- [ASCII-DIAGRAM-STANDARD.md](./ASCII-DIAGRAM-STANDARD.md) - Workflow diagrams
- [PLUGIN-ARCHITECTURE.md](./PLUGIN-ARCHITECTURE.md) - Skill structure
