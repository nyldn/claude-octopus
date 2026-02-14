# Claude Octopus - Safeguards & Critical Configuration

This document outlines critical configuration that must NOT be changed without careful consideration and extensive testing.

## 🔒 Critical: Plugin Name Lock

**Status:** ✅ **LOCKED** - Do not change without breaking existing workflows

### Current Configuration

```json
// .claude-plugin/plugin.json
{
  "name": "octo"  // ⚠️ LOCKED - See details below
}
```

```json
// package.json
{
  "name": "claude-octopus"  // This is different and correct
}
```

### Why These Are Different

| File | Name | Purpose | Command Format |
|------|------|---------|----------------|
| `.claude-plugin/plugin.json` | `"octo"` | Command prefix in Claude Code | `/octo:discover`, `/octo:debate` |
| `package.json` | `"claude-octopus"` | Package/marketplace identity | N/A (npm/git) |

### What Happens If You Change It

❌ **Changing plugin name from `"octo"` to `"claude-octopus"`:**

```diff
// .claude-plugin/plugin.json
{
- "name": "octo"
+ "name": "claude-octopus"  // ❌ BREAKS ALL COMMANDS
}
```

**Impact:**
- All commands change from `/octo:*` to `/claude-octopus:*`
- Existing documentation becomes incorrect
- User workflows break
- Skills/commands referencing `/octo:*` stop working
- 100+ references across codebase need updating

**Estimated fix time:** 4-8 hours + documentation updates + user migration

### Historical Context

This configuration was broken and fixed multiple times:

| Commit | Change | Result |
|--------|--------|--------|
| `3ebb189` | Set plugin name to `claude-octopus` | ❌ Broke command prefixes |
| `d9e8354` | Reverted to `octo` | ✅ Fixed commands |
| `57ce38c` | Removed namespace prefix from frontmatter | ✅ Correct format |

### Validation & Safeguards

Multiple layers of protection now exist:

#### 1. Automated Test
```bash
make test-plugin-name
```

Runs: `tests/validate-plugin-name.sh`

#### 2. Pre-commit Hook
File: `.claude/hooks/pre-commit.sh`

Automatically validates plugin name before every commit.

#### 3. GitHub Actions
Workflow: `.github/workflows/test.yml`

Smoke tests include plugin name validation on every PR.

#### 4. Documentation
Files:
- `.claude-plugin/PLUGIN_NAME_LOCK.md` - Detailed explanation
- `.claude-plugin/plugin.json` - In-file comment warning
- `SAFEGUARDS.md` (this file) - Central reference

### If You MUST Change It

**Don't.** But if you have no choice:

1. **Update all command references** (100+ files):
   - `.claude/commands/*.md` - Command files
   - `.claude/skills/*.md` - Skill files
   - `README.md` - Documentation
   - `CLAUDE.md` - System instructions
   - All example code

2. **Update tests:**
   - `tests/validate-plugin-name.sh` - Expected name
   - All test files referencing `/octo:*`

3. **Notify users:**
   - Create migration guide
   - Document breaking change
   - Provide search/replace script
   - Bump major version (breaking change)

4. **Update validation:**
   - Pre-commit hook
   - Test suite
   - CI/CD workflows

**Estimated effort:** 1-2 days + user support + migration period

---

## 🛡️ Sandbox Write Restrictions (v2.1.38+)

**Status:** ⚠️ **AWARENESS REQUIRED** - Claude Code blocks writes to `.claude/skills` in sandbox mode

### What Changed

As of Claude Code v2.1.38, sandbox mode explicitly blocks writes to the `.claude/skills` directory. This is a security hardening measure to prevent untrusted code from modifying skill definitions.

### Impact on Claude Octopus

- **Installation:** The `install.sh` script and plugin manager handle skill installation outside sandbox mode, so normal installation is unaffected.
- **Dynamic skill generation:** Any workflow or hook that attempts to create or modify files in `.claude/skills` at runtime will fail silently in sandboxed environments.
- **Development:** When developing new skills locally, ensure you're not running in sandbox mode (`/sandbox` to check).

### What to Do

1. **Never generate skills dynamically** at runtime — all skills should be pre-defined in the plugin package
2. **Use `~/.claude-octopus/` for runtime artifacts** — this directory is outside the sandbox boundary
3. **Test in sandbox mode** before releasing — run `make test-smoke` with sandbox enabled to catch write failures early

### Detection

```bash
# Check if running in sandbox mode
claude /sandbox  # Shows current sandbox status
```

If a hook or script fails silently, check if it's attempting to write to a sandboxed path.

---

## 🛡️ Other Critical Configuration

### Command Frontmatter Format

**Current (correct):**
```yaml
---
command: discover
description: "Discovery phase..."
---
```

**Incorrect (do not use):**
```yaml
---
command: octo:discover  # ❌ WRONG - namespace added twice
---
```

The namespace is automatically added by Claude Code based on plugin name.

### Version Synchronization

These must stay in sync:

```json
// .claude-plugin/plugin.json
{
  "version": "7.9.7"
}
```

```json
// package.json
{
  "version": "7.9.7"
}
```

```markdown
// README.md
![Version 7.9.7](...)
```

Use: `scripts/bump-version.sh` to update all at once (if it exists, otherwise manual sync required).

---

## 📋 Pre-Release Checklist

Before releasing a new version:

- [ ] Run `make test-plugin-name` - Verify plugin name is `"octo"`
- [ ] Run `make test-smoke` - Verify all smoke tests pass
- [ ] Check version sync across `plugin.json`, `package.json`, `README.md`
- [ ] Verify command references use `/octo:*` format
- [ ] Test installation from marketplace
- [ ] Verify commands work after installation

---

## 🔍 Monitoring

### How to Detect Issues

**Plugin name changed:**
```bash
./tests/validate-plugin-name.sh
# Should output: ✅ Plugin name is correct: "octo"
```

**Commands not working:**
```bash
# Try running a command in Claude Code
/octo:discover test query

# If it fails, check plugin.json name field
grep '"name"' .claude-plugin/plugin.json
```

### Recovery Steps

If plugin name gets changed accidentally:

1. **Revert the change immediately:**
   ```bash
   # In .claude-plugin/plugin.json, set:
   "name": "octo"
   ```

2. **Verify fix:**
   ```bash
   make test-plugin-name
   ```

3. **Test commands:**
   - Reload plugin in Claude Code
   - Run `/octo:discover test` to verify

---

## 📚 References

- **Plugin Name Lock:** `.claude-plugin/PLUGIN_NAME_LOCK.md`
- **Development Guide:** `.claude/DEVELOPMENT.md`
- **Test Suite:** `tests/README.md`
- **System Instructions:** `CLAUDE.md`

---

**Last Updated:** 2026-02-13
**Status:** All safeguards active and tested ✅
