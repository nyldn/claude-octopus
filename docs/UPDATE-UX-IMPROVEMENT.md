# Update UX Improvement

**Version:** 7.9.1
**Date:** 2026-01-21
**Status:** Implemented

## The Problem

Users running `/octo:update --update` experienced confusing contradictory messages:

1. **First message:** "New version available! v7.9.0"
2. **Second message:** "Already at latest version (7.8.15)"
3. **User emotion:** Confusion, distrust, frustration

### Root Cause

The command checked **two sources** but presented them inconsistently:
- GitHub API: Shows v7.9.0 (released, but registry hasn't synced)
- Plugin registry: Shows v7.8.15 (last synced version, 12-24h delay)

The command announced GitHub had v7.9.0, then used `claude plugin update` which checked the registry and reported "already at latest" because the registry hadn't synced yet.

## The Solution

### Three-Source Version Checking

Now `/octo:update` checks **three sources** and reports transparently:

| Source | What It Represents | Trust Level |
|--------|-------------------|-------------|
| 🐙 GitHub | Latest release (source of truth) | Highest |
| 🔵 Registry | What's available to install | Medium |
| 📦 Installed | Your current version | Known |

### Five Scenarios Handled

#### Scenario A: Up-to-Date
```
📦 Your version:     v7.9.0
🔵 Registry latest:  v7.9.0
🐙 GitHub latest:    v7.9.0

✅ You're running the latest version!
```

#### Scenario B: Update Available (Registry Synced)
```
📦 Your version:     v7.8.15
🔵 Registry latest:  v7.9.0
🐙 GitHub latest:    v7.9.0

🆕 Update available!
To update, run: /octo:update --update
```

#### Scenario C: Registry Sync Pending ⭐ **THE KEY FIX**
```
📦 Your version:     v7.8.15
🔵 Registry latest:  v7.8.15 (matches your version)
🐙 GitHub latest:    v7.9.0 (released 6 hours ago)

⚠️  Registry Sync Pending

A newer version (v7.9.0) exists on GitHub but hasn't propagated
to the plugin registry yet. Registry sync typically takes 12-24 hours.

Estimated sync completion: 6-18 hours from now

Check back later with: /octo:update
```

#### Scenario D: Auto-Update Blocked (Safe Guard)
When `/octo:update --update` is run but registry hasn't synced:
```
❌ Cannot auto-update: Registry has not synced with GitHub yet.

Please check back later with: /octo:update --update
```

#### Scenario E: Successful Auto-Update
When registry has synced and update proceeds:
```
🔄 Updating to v7.9.0...
✅ Update complete! Please restart Claude Code.
```

## Key Principles

### 1. Transparency Over Simplicity
**Bad:** "Already at latest" (when GitHub has newer)
**Good:** Show all three versions with clear labels

### 2. Explain Discrepancies
**Bad:** Contradictory messages without context
**Good:** "Registry sync typically takes 12-24 hours"

### 3. Set Realistic Expectations
**Bad:** No timeline given
**Good:** "Released 6 hours ago, check back in 6-18 hours"

### 4. Safety First
**Bad:** Try to auto-update even when registry hasn't synced
**Good:** Only auto-update when registry matches GitHub

### 5. Users Handle Nuance
Research insight: Users can understand "GitHub has v7.9.0, registry has v7.8.15 due to sync delay" much better than "Update available!" followed by "Already latest!"

## Research Backing

### Industry Registry Sync Times

| Platform | Typical Sync | Extreme Cases |
|----------|--------------|---------------|
| Chrome Web Store | 15m - 3h | Up to 48 hours |
| npm | 5-15 minutes | Up to 24h for CDN |
| VSCode Marketplace | Minutes to hours | Several hours |
| Homebrew | Real-time (taps) | 24h (auto-update) |

### User Experience Patterns

✅ **What Works:**
- Multi-source transparency (npm, VSCode)
- Progress indicators (Chrome extensions)
- Estimated timing (Homebrew, npm)
- Release notes links (all platforms)

❌ **What Fails:**
- Contradictory messages
- Silent failures
- "Already at latest" when newer exists
- No explanation of delays

## Implementation Notes

### Command Changes

**File:** `.claude/commands/sys-update.md`

**Before:**
1. Check GitHub for latest
2. Check installed version
3. Try `claude plugin update`
4. Report whatever it says

**After:**
1. Check GitHub for latest (source of truth)
2. Check installed version
3. **NEW:** Check registry version by parsing update output
4. Compare all three
5. Provide scenario-specific messaging
6. Only auto-update when safe (registry == GitHub)

### Code Logic

```bash
# Scenario detection
if [ "$INSTALLED_VERSION" = "$GITHUB_VERSION" ]; then
    # Scenario A: Up-to-date

elif [ "$REGISTRY_VERSION" = "$GITHUB_VERSION" ] && [ "$INSTALLED_VERSION" != "$GITHUB_VERSION" ]; then
    # Scenario B: Update available (safe to proceed)

elif [ "$GITHUB_VERSION" != "$REGISTRY_VERSION" ]; then
    # Scenario C: Registry sync pending (explain delay)

fi
```

## Metrics for Success

### User Confusion (Before)
- "Why does it say update available then latest?"
- "Is my plugin broken?"
- "How do I actually update?"
- Abandonment risk: **High**

### User Understanding (After)
- "Ah, the registry hasn't synced yet"
- "I'll check back in 12 hours"
- "I can see the release notes now"
- Abandonment risk: **Low**

## Future Enhancements

### Phase 2 (Medium Effort)
- [ ] Add `--force` flag for GitHub-direct checking
- [ ] Calculate and display actual release age
- [ ] Session-cached update notifications

### Phase 3 (Higher Effort)
- [ ] Webhook/polling for registry sync detection
- [ ] Automatic retry scheduling
- [ ] Integration with Claude Code's native update system

## Related Documentation

- Command implementation: `.claude/commands/sys-update.md`
- User research findings: stored in agent outputs (a503212, a3e37f9)
- Industry patterns: Chrome, npm, VSCode, Homebrew research

## Conclusion

This fix transforms a trust-breaking UX failure into a transparent, educational experience. By checking three sources and explaining discrepancies, users understand what's happening and when to check back, rather than experiencing confusion and frustration.

**Key Insight:** Users don't need perfection—they need honesty about what's happening and realistic expectations about timing.
