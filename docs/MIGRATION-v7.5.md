# Migration Guide: Namespace Changes (v7.5 → v7.7.3)

> **Note:** This guide has been updated for v7.7.3 which changed the namespace from `/co:` to `/octo:`.

## What Changed

Claude Octopus has undergone two namespace changes:

### v7.5: `/claude-octopus:` → `/co:`
### v7.7.3: `/co:` → `/octo:` (current)

The plugin is now registered as `octo` for complete consistency with the "octo" natural language prefix.

### Current Namespace

**Before (v7.4 and earlier):**
```
/claude-octopus:setup
/claude-octopus:check-update
```

**After (v7.7.3+):**
```
/octo:setup           # Unified with "octo" prefix!
/octo:update
```

### Three-Category System

All commands and skills now follow a clear category structure:

| Category | Prefix | Purpose | Examples |
|----------|--------|---------|----------|
| **System** | `sys-` | Setup, updates, configuration | sys-setup, sys-update, sys-configure |
| **Workflows** | `flow-` | Double Diamond phases | flow-probe, flow-grasp, flow-tangle, flow-ink |
| **Skills** | `skill-` | All other capabilities | skill-debate, skill-code-review, skill-tdd |

### Shortcut Aliases

15 shortcut aliases added for frequently-used commands:

| Full Name | Shortcut | Purpose |
|-----------|----------|---------|
| `/octo:sys-setup` | `/octo:setup` | System setup |
| `/octo:sys-update` | `/octo:update` | Check updates |
| `/octo:sys-configure` | `/octo:config` | Configuration |
| `/octo:skill-knowledge-mode` | `/octo:km` | Knowledge mode toggle |
| `/octo:flow-probe` | `/octo:probe` | Research workflow |
| `/octo:flow-grasp` | `/octo:grasp` | Define workflow |
| `/octo:flow-tangle` | `/octo:tangle` | Develop workflow |
| `/octo:flow-ink` | `/octo:ink` | Deliver workflow |
| `/octo:skill-debate` | `/octo:debate` | AI debates |
| `/octo:skill-code-review` | `/octo:review` | Code review |
| `/octo:skill-security-audit` | `/octo:security` | Security audit |
| `/octo:skill-deep-research` | `/octo:research` | Deep research |
| `/octo:skill-tdd` | `/octo:tdd` | Test-driven development |
| `/octo:skill-debug` | `/octo:debug` | Systematic debugging |
| `/octo:skill-doc-delivery` | `/octo:docs` | Document delivery |

---

## Backward Compatibility

### All Old Commands Still Work

**Zero breaking changes!** Both namespaces are registered:

| Old Command | New Command (Primary) | Shortcut | Status |
|-------------|----------------------|----------|--------|
| `/claude-octopus:setup` | `/octo:sys-setup` | `/octo:setup` | ✅ All work |
| `/claude-octopus:check-update` | `/octo:sys-update` | `/octo:update` | ✅ All work |
| `/claude-octopus:km` | `/octo:skill-knowledge-mode` | `/octo:km` | ✅ All work |
| `probe-workflow` | `/octo:flow-probe` | `/octo:probe` | ✅ All work |
| `code-review` | `/octo:skill-code-review` | `/octo:review` | ✅ All work |

### Current Setup

The plugin is registered as `octo` (matching the "octo" natural language prefix):
- `/octo:setup` works ✅
- Natural language triggers (e.g., "octo research X") work ✅

**Note:** The `/co:` and `/claude-octopus:` namespaces are no longer supported as of v7.7.3.

---

## Recommended Migration Path

### For New Users (v7.7.3+)

Use the `octo` namespace:

```
# Installation
/plugin install claude-octopus@nyldn-plugins

# System commands
/octo:setup
/octo:update

# Mode switching
/octo:km on
/octo:km off

# Workflows
/octo:probe "research OAuth patterns"
/octo:tangle "build authentication"
/octo:review "check security"

# Specialized skills
/octo:debate "Should we use Redis?"
/octo:tdd "implement user service"
```

### For Existing Users (Upgrading from v7.4)

**Option A: Gradual Migration (Recommended)**

Continue using old commands while learning the new ones:

```
# Old commands still work
/claude-octopus:setup
/claude-octopus:km on

# Try new shortcuts gradually
/octo:setup
/octo:km on
```

**Option B: Immediate Switch**

Replace all old commands with new shortcuts:

| Replace This | With This |
|--------------|-----------|
| `/claude-octopus:setup` | `/octo:setup` |
| `/claude-octopus:check-update` | `/octo:update` |
| `/claude-octopus:km` | `/octo:km` |

**Option C: Use Full Categorical Names**

For better discoverability and self-documentation:

```
/octo:sys-setup
/octo:sys-update
/octo:skill-knowledge-mode
/octo:flow-probe
/octo:skill-code-review
```

---

## Complete Rename Table

### Commands

| Old Name | New Primary Name | Shortcut Alias |
|----------|------------------|----------------|
| setup.md | sys-setup.md | setup.md |
| check-update.md | sys-update.md | update.md, check-update.md |
| knowledge-mode.md | skill-knowledge-mode.md | km.md |

### Workflow Skills

| Old Name | New Primary Name | Shortcut Alias |
|----------|------------------|----------------|
| probe-workflow.md | flow-probe.md | probe.md |
| grasp-workflow.md | flow-grasp.md | grasp.md |
| tangle-workflow.md | flow-tangle.md | tangle.md |
| ink-workflow.md | flow-ink.md | ink.md |

### System Skills

| Old Name | New Primary Name | Shortcut Alias |
|----------|------------------|----------------|
| configure.md | sys-configure.md | config.md |

### Other Skills

| Old Name | New Primary Name | Shortcut Alias |
|----------|------------------|----------------|
| debate.md | skill-debate.md | debate.md |
| debate-integration.md | skill-debate-integration.md | (none) |
| code-review.md | skill-code-review.md | review.md |
| architecture.md | skill-architecture.md | (none) |
| security-audit.md | skill-security-audit.md | security.md |
| quick-review.md | skill-quick-review.md | (none) |
| adversarial-security.md | skill-adversarial-security.md | (none) |
| deep-research.md | skill-deep-research.md | research.md |
| writing-plans.md | skill-writing-plans.md | (none) |
| test-driven-development.md | skill-tdd.md | tdd.md |
| systematic-debugging.md | skill-debug.md | debug.md |
| document-delivery.md | skill-doc-delivery.md | docs.md |
| finishing-branch.md | skill-finish-branch.md | (none) |
| verification-before-completion.md | skill-verify.md | (none) |
| parallel-agents.md | skill-parallel-agents.md | (none) |
| knowledge-work-mode.md | skill-knowledge-work.md | (none) |

---

## Benefits of v7.5

### 1. 60% Shorter Commands

**Before:**
```
/claude-octopus:check-update --update
```

**After:**
```
/octo:update --update
```

### 2. Better Organization

Commands are now categorized by purpose:
- `sys-*` = System operations
- `flow-*` = Workflow phases
- `skill-*` = Specialized capabilities

### 3. Easier Discovery

Type `/octo:flow-` to see all workflow commands
Type `/octo:skill-` to see all skills
Type `/octo:sys-` to see all system commands

### 4. Power User Shortcuts

Frequent commands get 1-2 word shortcuts:
- `/octo:setup` instead of `/octo:sys-setup`
- `/octo:probe` instead of `/octo:flow-probe`
- `/octo:review` instead of `/octo:skill-code-review`

### 5. Zero Breaking Changes

All old commands continue to work indefinitely. Migrate at your own pace.

---

## FAQ

### Q: Do I need to update anything?

**A:** No! Your existing scripts, workflows, and muscle memory continue to work. The old `/claude-octopus:` namespace is still registered.

### Q: Should I use shortcuts or full names?

**A:** Personal preference:
- **Shortcuts** (`/octo:setup`) - Faster to type, great for interactive use
- **Full names** (`/octo:sys-setup`) - More descriptive, better for scripts/documentation

### Q: What about natural language triggers?

**A:** Natural language triggers are unchanged and continue to work:
- "research OAuth patterns" → triggers flow-probe
- "build authentication" → triggers flow-tangle
- "review this code" → triggers flow-ink

### Q: Will the old namespace be removed?

**A:** No plans to remove it. Backward compatibility is a priority.

### Q: How do I install?

**A:** Use:
```
/plugin install claude-octopus@nyldn-plugins
```

This gives you the `/octo:` namespace that matches the "octo" natural language prefix.

---

## Testing Your Migration

### Verify Old Commands Work

```
/claude-octopus:setup
Expected: Setup command executes
```

### Verify New Namespace Works

```
/octo:sys-setup
Expected: Same as /claude-octopus:setup
```

### Verify Shortcuts Work

```
/octo:setup
Expected: Same as /octo:sys-setup
```

### Verify Natural Language Triggers

```
"Research authentication best practices"
Expected: Auto-triggers /octo:flow-probe
```

---

## Support

If you encounter issues:

1. **Check plugin installation:**
   ```
   /plugin list
   ```
   Look for `claude-octopus@nyldn-plugins`

2. **Reinstall if needed:**
   ```
   /plugin uninstall claude-octopus
   /plugin marketplace update nyldn-plugins
   /plugin install claude-octopus@nyldn-plugins
   ```

3. **Report issues:**
   https://github.com/nyldn/claude-octopus/issues

---

## Summary

✅ **Unified namespace** - `/octo:` matches "octo" natural language prefix
✅ **Clear categorization** - sys-, flow-, skill- prefixes
✅ **15 shortcuts** added for common commands
✅ **Better discoverability** - grouped by category

Use `/octo:` commands or "octo X" natural language - both work consistently!
