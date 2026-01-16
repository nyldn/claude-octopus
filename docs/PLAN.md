# Grapple Performance Optimization Plan v2

## Goal

Make `grapple` faster and more cost-effective by using:
1. **Built-in Claude** (user's default model via `claude --print` without `-m` flag)
2. **GPT-5.2 via Codex OAuth** (faster than API mode, no separate API credits for ChatGPT Pro subscribers)

**Current state:** grapple uses `claude --print` (Sonnet 4.5) and `codex exec` with 5 rounds
**Target state:** Same round structure but with optimized agent selection and reduced timeouts

---

## Research Insights

### From Reddit r/ClaudeCode Thread

Key user feedback on cross-model review:

1. **"Codex is the GOAT reviewer"** - GPT5.2-codex high is best code review model, catches 98% of issues
2. **"Codex is good at reviewing code, but dog shit at writing code"** - Use Claude for implementation, Codex for review
3. **Grapple catches "2-3x more issues than single-model review"** - Claude Octopus already mentioned!
4. **The optimal pattern**: Claude implements → Codex reviews → synthesize

### From Web Research

1. **Adversarial-spec pattern**: Popular Claude Code plugin uses draft → parallel critique → synthesize with Codex CLI for OAuth routing
2. **Speed**: Codex CLI with OAuth is faster than API mode
3. **Model strengths**:
   - Claude: Safety-first, balanced, consistent, good at writing code
   - Codex/GPT: Aggressive, performance-first, excellent at reviewing
4. **Cost**: Codex CLI for ChatGPT Pro subscribers uses no separate API credits

Sources:
- [Reddit r/ClaudeCode - Apes together strong](https://www.reddit.com/r/ClaudeCode/comments/1qa9rt2/)
- [GitHub - adversarial-spec](https://github.com/zscole/adversarial-spec)
- [Builder.io - Codex vs Claude Code](https://www.builder.io/blog/codex-vs-claude-code)

---

## Current Implementation

**File:** `scripts/orchestrate.sh` (lines 6050-6251)

| Round | Current Agent | Command | Timeout |
|-------|---------------|---------|---------|
| 1a | codex | `codex exec` | 90s |
| 1b | claude | `claude --print` | 90s |
| 2a | claude | `claude --print` | 60s |
| 2b | codex-review | `codex exec review` | 60s |
| 3 | claude | `claude --print` | 90s |

---

## Proposed Changes

### 1. No Agent Configuration Changes Needed

Current agent definitions are already optimal:
- `claude` → `claude --print` (uses user's default model, typically Sonnet 4.5)
- `codex` → `codex exec` (uses OAuth if `~/.codex/auth.json` exists)

The `--print` flag without `-m` inherits the user's configured default model.

### 2. Verify grapple Uses Correct Agents

Current `grapple_debate()` already uses:
- `codex` for Round 1a (proposal)
- `claude` for Round 1b (proposal), 2a (critique), 3 (synthesis)
- `codex-review` for Round 2b (critique)

Based on Reddit feedback, this is the **optimal** configuration:
- **Codex proposes** - aggressive, performance-first (good for diverse perspective)
- **Claude proposes** - balanced, safety-first (good at writing code)
- **Claude critiques Codex** - catches unsafe/aggressive patterns
- **Codex critiques Claude** - **"GOAT reviewer"** catches 98% of issues, finds edge cases
- **Claude synthesizes** - balanced final decision

The Reddit thread confirms: "codex is good at reviewing code" - so having `codex-review` critique Claude's proposal is ideal.

### 3. Reduce Timeouts for Speed

The current timeouts can be further reduced since `--print` mode is non-agentic:

| Round | Agent | Current Timeout | New Timeout |
|-------|-------|-----------------|-------------|
| 1a | codex | 90s | 60s |
| 1b | claude | 90s | 60s |
| 2a | claude | 60s | 45s |
| 2b | codex-review | 60s | 45s |
| 3 | claude | 90s | 60s |

**Estimated total time:** ~4-5 minutes (down from ~6-7 minutes)

### 4. Add OAuth Status to Grapple Output

Show authentication mode in grapple banner for transparency:

```bash
echo -e "${RED}║  Codex vs Claude debate until consensus                   ║${NC}"
echo -e "${RED}║  Auth: $(get_auth_mode_display)${NC}"
```

Where `get_auth_mode_display()` returns:
- "Codex OAuth + Claude API" (optimal)
- "Codex API + Claude API" (slower, warn user)

---

## Files to Modify

| File | Changes |
|------|---------|
| `scripts/orchestrate.sh` | Reduce timeouts in `grapple_debate()`, add auth status display |

---

## Implementation Steps

1. Update `grapple_debate()` timeouts:
   - Round 1a: 90s → 60s
   - Round 1b: 90s → 60s
   - Round 2a: 60s → 45s
   - Round 2b: 60s → 45s
   - Round 3: 90s → 60s

2. Add helper function `get_auth_mode_display()` to show current auth configuration

3. Update grapple banner to show auth mode

---

## Verification

1. **Test grapple dry-run:**
   ```bash
   ./scripts/orchestrate.sh -n grapple "implement hello world"
   ```

2. **Test grapple with actual execution:**
   ```bash
   time ./scripts/orchestrate.sh grapple "implement a simple hello world function"
   # Should complete in ~4-5 minutes
   ```

3. **Run test suite:**
   ```bash
   ./scripts/test-claude-octopus.sh
   # All tests should pass
   ```

---

## No Rollback Needed

The changes are minimal (timeout reductions + display enhancement). No functional changes to agent selection or command structure.
