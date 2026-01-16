# Claude Octopus - Phase 2 Configuration UX Improvements

## Status: PLANNING (Phase 1 Complete ✓)

## Phase 1 Achievements (Completed 2026-01-16)

✅ **Command Renamed**: `setup` → `octopus-configure` (avoids plugin collisions)
✅ **Claude Code Skill**: Created `.claude/skills/configure.md` for better integration
✅ **Non-Interactive Mode**: Auto-detects Claude Code environment and uses smart defaults
✅ **Documentation Updated**: All references updated in CLAUDE.md and README.md
✅ **Backward Compatibility**: Old `setup` command shows deprecation warning

### What Phase 1 Solved

The configuration wizard now:
- **Detects** when called by Claude Code (non-TTY or CLAUDE_SESSION_ID present)
- **Auto-selects** reasonable subscription tier defaults instead of blocking
- **Skips** interactive prompts that would hang in Claude's environment
- **Provides** clear instructions for manual configuration

**Example Output in Claude Code:**
```
⚠ Non-interactive mode detected. Using auto-detected defaults.

✓ Auto-detected: Plus tier (default for API key users)
✓ Auto-detected: Free tier (OAuth authenticated)
⚠ OpenRouter not configured (optional - skipping in auto mode)
```

## Phase 2 Goals: Intelligent Auto-Configuration

### Problem Statement

Current state (Phase 1):
- Uses **static defaults** (Plus for OpenAI, Free for Gemini)
- Cannot detect actual subscription tiers
- Still requires manual intervention for API keys
- No visual confirmation of what was detected

Desired state (Phase 2):
- **Auto-detect subscription tiers** via API test calls
- Use **AskUserQuestion** for unavoidable choices
- **Beautiful summary** with visual confirmation
- **Silent configuration** save with progress indicators

### Technical Approach

#### 1. Subscription Tier Auto-Detection

**Goal**: Detect actual subscription tier by making test API calls and analyzing rate limits, model access, or error messages.

**Implementation Strategy:**

```bash
detect_openai_tier() {
    # Approach 1: Check model access
    # - Pro users can access o3-mini-high
    # - Plus users can access gpt-4
    # - Free users get rate limit errors

    # Approach 2: Analyze rate limit headers
    # - X-RateLimit-Limit-Requests
    # - X-RateLimit-Remaining-Requests

    # Approach 3: Check billing endpoint (if available)
}

detect_gemini_tier() {
    # Approach 1: Check workspace domain
    # - OAuth with @company.com → Workspace
    # - OAuth with @gmail.com → Free/Google One

    # Approach 2: Test quota limits
    # - Make API call and check quota headers
}

detect_claude_tier() {
    # Already known: running inside Claude Code
    # Can detect Pro vs API-only based on environment
}
```

**API Test Strategy:**
- Use lightweight test prompts (1-2 tokens)
- Cache results for 24 hours to avoid repeated calls
- Graceful fallback to defaults on API errors

**Files to Create:**
- `scripts/lib/tier-detector.sh` - Tier detection module

#### 2. AskUserQuestion Integration

**Goal**: Use Claude Code's native question system for choices that can't be auto-detected.

**Use Cases:**
- Cost optimization strategy (balanced vs cost-first vs quality-first)
- Whether to install missing developer tools
- Confirmation of detected settings

**Example Implementation:**

```markdown
# In .claude/skills/configure.md

After auto-detection, use AskUserQuestion:

<AskUserQuestion>
{
  "questions": [
    {
      "question": "Which cost optimization strategy do you prefer?",
      "header": "Strategy",
      "multiSelect": false,
      "options": [
        {
          "label": "Balanced (Recommended)",
          "description": "Smart mix of cost and quality based on your subscription tiers"
        },
        {
          "label": "Cost-First",
          "description": "Always prefer cheapest capable provider"
        },
        {
          "label": "Quality-First",
          "description": "Always prefer highest-tier provider"
        }
      ]
    }
  ]
}
</AskUserQuestion>
```

#### 3. Beautiful Summary Output

**Goal**: Clear, visual confirmation of detected configuration.

**Design:**

```
🐙 Claude Octopus Configuration Summary

Provider Status:
  ✓ OpenAI/Codex
    Tier: Plus ($20/mo)
    Auth: API Key (164 chars)
    Cost: Low

  ✓ Gemini
    Tier: Free
    Auth: OAuth (oauth-personal)
    Cost: Free

  ✓ Claude
    Tier: Pro ($20/mo)
    Auth: OAuth
    Cost: Medium

  ⚠ OpenRouter
    Status: Not configured (optional)

Cost Strategy: Balanced
Workspace: ~/.claude-octopus

Next Steps:
  1. Try: ./scripts/orchestrate.sh auto "research OAuth patterns"
  2. View: ./scripts/orchestrate.sh status
  3. Docs: https://github.com/nyldn/claude-octopus

Configuration saved to: ~/.claude-octopus/.providers-config
```

**Implementation:**
- Create `format_config_summary()` function
- Use ANSI colors for visual hierarchy
- Show actionable next steps

#### 4. Silent Config Save with Visual Confirmation

**Goal**: Save configuration without blocking, show progress.

**Design:**

```
Saving configuration...
  ✓ Provider settings saved
  ✓ Cost strategy saved
  ✓ Workspace initialized
  ✓ Preflight cache invalidated

Configuration saved to: ~/.claude-octopus/.providers-config
```

### Migration Path

**Step 1: Create Detector Module** (3-5 days)
- Build `scripts/lib/tier-detector.sh`
- Implement OpenAI tier detection
- Implement Gemini tier detection
- Add caching layer

**Step 2: Skill Refactor** (2-3 days)
- Move setup logic into `.claude/skills/configure.md`
- Integrate AskUserQuestion for user choices
- Add detection function calls

**Step 3: Beautiful Output** (1-2 days)
- Create `format_config_summary()` function
- Add color coding and visual hierarchy
- Test in both interactive and non-interactive modes

**Step 4: Integration Testing** (2-3 days)
- Test all subscription tier combinations
- Verify AskUserQuestion UX
- Test error handling and fallbacks
- Update documentation

### Success Criteria

✅ **Auto-detection accuracy** ≥ 90% for subscription tiers
✅ **Zero blocking prompts** in Claude Code environment
✅ **Clear visual feedback** on what was detected
✅ **Graceful fallbacks** when detection fails
✅ **User satisfaction**: Setup takes < 30 seconds

### Technical Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| API changes break detection | High | Cache results, fallback to defaults |
| Rate limits from detection calls | Medium | Lightweight test prompts, caching |
| Different OAuth flows break detection | Medium | Multiple detection strategies |
| AskUserQuestion not available in all contexts | Low | Fallback to bash prompts |

---

## Development Notes

### Current Config Files
- `~/.claude-octopus/.providers-config` - Provider settings (YAML)
- `~/.claude-octopus/.user-config` - User preferences (YAML)
- `~/.claude-octopus/.setup-config` - Setup completion timestamp

### Key Functions
- `setup_wizard()` - Main wizard (line 5902)
- `save_providers_config()` - Config persistence (line 3178)
- `preflight_check()` - Dependency verification
- `status_display()` - Current status output

### Environment Variables
- `CLAUDE_SESSION_ID` - Indicates running in Claude Code
- `OPENAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`
- `CLAUDE_OCTOPUS_WORKSPACE` - Override workspace location

---

## Timeline Estimate

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Phase 1 (✅ Complete) | 1 day | Non-interactive mode, command rename |
| Phase 2.1 - Detector | 3-5 days | Tier auto-detection module |
| Phase 2.2 - Skill Refactor | 2-3 days | AskUserQuestion integration |
| Phase 2.3 - Beautiful Output | 1-2 days | Summary formatting |
| Phase 2.4 - Testing | 2-3 days | Integration tests, docs |
| **Total Phase 2** | **8-13 days** | Fully automated configuration |

---

**Last Updated**: 2026-01-16
**Phase 1 Completed**: 2026-01-16
**Phase 2 Target Start**: TBD
