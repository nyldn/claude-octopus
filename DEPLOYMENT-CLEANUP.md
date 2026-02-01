# Deployment Folder Cleanup Plan

## Current State Analysis

**Plugin directory size:** 15MB
**Main bloat sources:** scripts/ (944KB), docs/ (396KB), agents/ (312KB), component-analyzer/ (216KB)

## Files/Directories to Remove/Move

### 🔴 REMOVE IMMEDIATELY (Runtime/Dev Artifacts)

These should be .gitignored and removed from git:

```bash
# Runtime workspace (generated at ~/.claude-octopus/ during execution)
.claude-octopus/

# Development analysis tool
component-analyzer/

# Generated reports
reports/

# Test artifacts
test-results.xml
test-results*.xml

# Backup files
.claude-plugin/plugin.json.bak
```

### 🟡 EVALUATE/CONSOLIDATE (Development Docs)

**Option A: Move to docs/** (Keep in deployment for reference)
```bash
# Move to docs/development/
CLAUDE.md → docs/development/CLAUDE.md
CONTRIBUTING.md → docs/CONTRIBUTING.md
SECURITY.md → docs/SECURITY.md
PLUGIN_NAME_SAFEGUARDS.md → docs/development/PLUGIN_NAME_SAFEGUARDS.md
SAFEGUARDS.md → docs/development/SAFEGUARDS.md

# Archive old migrations
MIGRATION-7.13.0.md → docs/migrations/MIGRATION-7.13.0.md
RELEASE-v7.17.0.md → docs/releases/RELEASE-v7.17.0.md
```

**Option B: Remove entirely** (Only keep on GitHub wiki/website)

### 🟢 KEEP (Essential Deployment Files)

**Root-level essentials:**
- ✅ README.md (user-facing documentation)
- ✅ LICENSE (MIT license)
- ✅ CHANGELOG.md (version history)
- ✅ package.json (plugin metadata)
- ✅ .gitignore (ignore patterns)
- ✅ Makefile (build/test automation)
- ✅ install.sh (installation script)
- ✅ deploy.sh (deployment validation)

**Core directories:**
- ✅ `.claude/` - Plugin commands, skills, hooks
- ✅ `.claude-plugin/` - Plugin manifest and marketplace info
- ✅ `agents/` - Personas, principles, skills (312KB - core functionality)
- ✅ `scripts/` - Runtime orchestration (944KB - essential)
- ✅ `hooks/` - Git hooks (36KB)
- ✅ `config/` - Modular CLAUDE.md configs (16KB)
- ✅ `assets/` - Images for README (188KB)

**Optional but valuable:**
- ✅ `tests/` - Quality assurance (192KB)
- ⚠️ `docs/` - User documentation (396KB - consider trimming)
- ⚠️ `.github/` - CI/CD workflows (keep if using GitHub Actions)

**Unclear - needs investigation:**
- ❓ `src/` - 20KB, check contents
- ❓ `.dependencies/` - Contains claude-skills submodule

## Recommended .gitignore Additions

Add to `.gitignore`:

```gitignore
# Runtime workspace (actual workspace is at ~/.claude-octopus/)
.claude-octopus/
.parallel-agents/

# Development tools
component-analyzer/
reports/

# Test artifacts
test-results.xml
test-results*.xml
coverage-report.*

# Backup files
*.bak
*~

# macOS
.DS_Store

# IDE
.idea/
.vscode/

# Source experiments (if src/ is for development only)
src/
```

## Deployment Best Practices

### 1. **Separation Strategy**

Create a parent directory structure:
```
claude-octopus/
├── plugin/              # DEPLOYMENT (git tracked, clean)
│   ├── .claude/
│   ├── .claude-plugin/
│   ├── agents/
│   ├── scripts/
│   └── README.md
│
└── dev-workspace/       # DEVELOPMENT (git ignored)
    ├── research/
    ├── benchmarks/
    ├── drafts/
    ├── analysis/
    └── experiments/
```

### 2. **Pre-Push Hook**

The existing `hooks/pre-push` already validates deployment. Ensure it's installed:

```bash
./scripts/install-hooks.sh
```

### 3. **Automated Cleanup Script**

Create `scripts/clean-deployment.sh`:

```bash
#!/bin/bash
# Remove development artifacts from plugin/ directory

rm -rf .claude-octopus/
rm -rf component-analyzer/
rm -rf reports/
rm -f test-results*.xml
find . -name "*.bak" -delete
find . -name ".DS_Store" -delete

echo "✅ Deployment directory cleaned"
```

### 4. **Size Monitoring**

Add to Makefile:

```makefile
check-size:
	@echo "Plugin deployment size:"
	@du -sh .
	@echo ""
	@echo "Largest directories:"
	@du -sh ./* 2>/dev/null | sort -h | tail -10
```

## Action Items

### Immediate (Do Now)

1. ✅ Update .gitignore with runtime artifacts
2. ✅ Remove .claude-octopus/, component-analyzer/, reports/, test-results.xml
3. ✅ Remove .claude-plugin/plugin.json.bak
4. ✅ Run deployment validation: `./deploy.sh`

### Short-term (This Week)

1. Evaluate src/ directory - delete if not needed
2. Consolidate *.md files into docs/
3. Create scripts/clean-deployment.sh
4. Add size monitoring to Makefile

### Long-term (Next Release)

1. Consider splitting large docs/ into separate documentation repo
2. Review if all 30 commands + 35 skills are actively used
3. Evaluate agent persona consolidation (29 personas = 312KB)
4. Consider lazy-loading strategies for large assets

## Expected Size Reduction

**Before:** 15MB
**After cleanup:** ~13.5MB (-1.5MB)
- Remove .claude-octopus/: -500KB
- Remove component-analyzer/: -216KB
- Remove reports/: -16KB
- Remove test artifacts: -50KB
- Remove backups: -100KB

**Further optimization possible:** ~11MB (-4MB total)
- Consolidate/trim docs/: -1MB
- Optimize assets/: -500KB (compress images)
- Review unused scripts: -500KB

## Validation Checklist

After cleanup, verify:

- [ ] `./deploy.sh` passes all checks
- [ ] Plugin installs correctly: `/plugin install claude-octopus@nyldn-plugins`
- [ ] All commands work: `/octo:setup`, `/octo:probe`, etc.
- [ ] No sensitive data in git history
- [ ] All runtime artifacts are .gitignored
- [ ] Documentation is still accessible
- [ ] Tests still pass: `make test`
