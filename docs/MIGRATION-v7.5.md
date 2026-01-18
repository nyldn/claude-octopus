# Migration Guide: v7.5.0 Command Rename

## What Changed in v7.5

Claude Octopus commands now use shorter, categorized names with a new namespace:

### Plugin Namespace

**Before:**
```
/claude-octopus:setup
/claude-octopus:check-update
```

**After:**
```
/co:setup           # 60% shorter!
/co:update
```

The plugin is now registered as `co` (short for Claude Octopus) instead of `claude-octopus`.

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
| `/co:sys-setup` | `/co:setup` | System setup |
| `/co:sys-update` | `/co:update` | Check updates |
| `/co:sys-configure` | `/co:config` | Configuration |
| `/co:skill-knowledge-mode` | `/co:km` | Knowledge mode toggle |
| `/co:flow-probe` | `/co:probe` | Research workflow |
| `/co:flow-grasp` | `/co:grasp` | Define workflow |
| `/co:flow-tangle` | `/co:tangle` | Develop workflow |
| `/co:flow-ink` | `/co:ink` | Deliver workflow |
| `/co:skill-debate` | `/co:debate` | AI debates |
| `/co:skill-code-review` | `/co:review` | Code review |
| `/co:skill-security-audit` | `/co:security` | Security audit |
| `/co:skill-deep-research` | `/co:research` | Deep research |
| `/co:skill-tdd` | `/co:tdd` | Test-driven development |
| `/co:skill-debug` | `/co:debug` | Systematic debugging |
| `/co:skill-doc-delivery` | `/co:docs` | Document delivery |

---

## Backward Compatibility

### All Old Commands Still Work

**Zero breaking changes!** Both namespaces are registered:

| Old Command | New Command (Primary) | Shortcut | Status |
|-------------|----------------------|----------|--------|
| `/claude-octopus:setup` | `/co:sys-setup` | `/co:setup` | ✅ All work |
| `/claude-octopus:check-update` | `/co:sys-update` | `/co:update` | ✅ All work |
| `/claude-octopus:km` | `/co:skill-knowledge-mode` | `/co:km` | ✅ All work |
| `probe-workflow` | `/co:flow-probe` | `/co:probe` | ✅ All work |
| `code-review` | `/co:skill-code-review` | `/co:review` | ✅ All work |

### Dual Registration

The marketplace.json registers TWO plugins pointing to the same source:
- **co** (primary, recommended)
- **claude-octopus** (deprecated, but functional)

This means:
- `/co:setup` works ✅
- `/claude-octopus:setup` works ✅ (via legacy namespace)
- Natural language triggers still work ✅

---

## Recommended Migration Path

### For New Users (v7.5+)

Use the new `co` namespace with shortcuts:

```
# Installation
/plugin install co@nyldn-plugins

# System commands
/co:setup
/co:update

# Mode switching
/co:km on
/co:km off

# Workflows
/co:probe "research OAuth patterns"
/co:tangle "build authentication"
/co:review "check security"

# Specialized skills
/co:debate "Should we use Redis?"
/co:tdd "implement user service"
```

### For Existing Users (Upgrading from v7.4)

**Option A: Gradual Migration (Recommended)**

Continue using old commands while learning the new ones:

```
# Old commands still work
/claude-octopus:setup
/claude-octopus:km on

# Try new shortcuts gradually
/co:setup
/co:km on
```

**Option B: Immediate Switch**

Replace all old commands with new shortcuts:

| Replace This | With This |
|--------------|-----------|
| `/claude-octopus:setup` | `/co:setup` |
| `/claude-octopus:check-update` | `/co:update` |
| `/claude-octopus:km` | `/co:km` |

**Option C: Use Full Categorical Names**

For better discoverability and self-documentation:

```
/co:sys-setup
/co:sys-update
/co:skill-knowledge-mode
/co:flow-probe
/co:skill-code-review
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
/co:update --update
```

### 2. Better Organization

Commands are now categorized by purpose:
- `sys-*` = System operations
- `flow-*` = Workflow phases
- `skill-*` = Specialized capabilities

### 3. Easier Discovery

Type `/co:flow-` to see all workflow commands
Type `/co:skill-` to see all skills
Type `/co:sys-` to see all system commands

### 4. Power User Shortcuts

Frequent commands get 1-2 word shortcuts:
- `/co:setup` instead of `/co:sys-setup`
- `/co:probe` instead of `/co:flow-probe`
- `/co:review` instead of `/co:skill-code-review`

### 5. Zero Breaking Changes

All old commands continue to work indefinitely. Migrate at your own pace.

---

## FAQ

### Q: Do I need to update anything?

**A:** No! Your existing scripts, workflows, and muscle memory continue to work. The old `/claude-octopus:` namespace is still registered.

### Q: Should I use shortcuts or full names?

**A:** Personal preference:
- **Shortcuts** (`/co:setup`) - Faster to type, great for interactive use
- **Full names** (`/co:sys-setup`) - More descriptive, better for scripts/documentation

### Q: What about natural language triggers?

**A:** Natural language triggers are unchanged and continue to work:
- "research OAuth patterns" → triggers flow-probe
- "build authentication" → triggers flow-tangle
- "review this code" → triggers flow-ink

### Q: Will the old namespace be removed?

**A:** No plans to remove it. Backward compatibility is a priority.

### Q: How do I install using the new namespace?

**A:** Use either:
```
/plugin install co@nyldn-plugins          # New namespace
/plugin install claude-octopus@nyldn-plugins  # Old namespace (still works)
```

Both install the same plugin.

---

## Testing Your Migration

### Verify Old Commands Work

```
/claude-octopus:setup
Expected: Setup command executes
```

### Verify New Namespace Works

```
/co:sys-setup
Expected: Same as /claude-octopus:setup
```

### Verify Shortcuts Work

```
/co:setup
Expected: Same as /co:sys-setup
```

### Verify Natural Language Triggers

```
"Research authentication best practices"
Expected: Auto-triggers /co:flow-probe
```

---

## Support

If you encounter issues:

1. **Check plugin installation:**
   ```
   /plugin list
   ```
   Look for `co@nyldn-plugins` or `claude-octopus@nyldn-plugins`

2. **Reinstall if needed:**
   ```
   /plugin uninstall claude-octopus
   /plugin marketplace update nyldn-plugins
   /plugin install co@nyldn-plugins
   ```

3. **Report issues:**
   https://github.com/nyldn/claude-octopus/issues

---

## Summary

✅ **60% shorter commands** - `/co:` instead of `/claude-octopus:`
✅ **Clear categorization** - sys-, flow-, skill- prefixes
✅ **15 shortcuts** added for common commands
✅ **Zero breaking changes** - old commands still work
✅ **Better discoverability** - grouped by category

Start using `/co:` today, or continue with `/claude-octopus:` - both work!
