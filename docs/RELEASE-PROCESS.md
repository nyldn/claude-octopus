# Release Process

This document describes the step-by-step process for releasing a new version of Claude Octopus.

## Pre-Release Checklist

Before starting the release process, ensure:

- [ ] All features/fixes are committed and tested
- [ ] Test suite passes (`./tests/unit/test-docs-sync.sh`)
- [ ] No uncommitted changes (`git status` clean)
- [ ] You're on the `main` branch

## Release Steps

### 1. Update Version Numbers

Update the version in **all** of these files:

#### a. `.claude-plugin/plugin.json`
```json
{
  "version": "X.Y.Z",
  "description": "Multi-tentacled orchestrator... (vX.Y.Z - ...)"
}
```

#### b. `.claude-plugin/marketplace.json`
**CRITICAL**: Version must appear at START of description for visibility

```json
{
  "plugins": [{
    "description": "vX.Y.Z - Multi-tentacled orchestrator...",
    "version": "X.Y.Z"
  }]
}
```

#### c. `README.md`
Update the version badge:
```markdown
<img src="https://img.shields.io/badge/Version-X.Y.Z-blue" alt="Version X.Y.Z">
```

### 2. Update CHANGELOG.md

Add a new section at the top:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features...

### Fixed
- Bug fixes...

### Changed
- Improvements...

### Enhanced
- Enhancements...
```

Include:
- Visual feedback / UI changes
- New features
- Bug fixes
- Documentation updates
- Breaking changes (if any)

### 3. Run Test Suite

```bash
./tests/unit/test-docs-sync.sh
```

The test will verify:
- ✅ README badge shows correct version
- ✅ CHANGELOG has entry for version
- ✅ README structure is complete
- ✅ Documentation files exist
- ✅ All skills registered in plugin.json
- ✅ Workflow skills present (v7.4+)
- ✅ Hooks configured correctly
- ✅ Debate skill has YAML frontmatter
- ✅ **marketplace.json version matches plugin.json**
- ✅ **marketplace.json description starts with version**

All tests must pass before proceeding.

### 4. Commit Version Changes

```bash
git add -A
git commit -m "chore: Update version numbers for vX.Y.Z release"
git push origin main
```

### 5. Create Git Tag

```bash
# Create annotated tag
git tag -a vX.Y.Z -m "Release vX.Y.Z - Brief Description"

# Push tag to GitHub
git push origin vX.Y.Z
```

### 6. Create GitHub Release

Use the GitHub CLI or web interface:

```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z - Release Title" \
  --notes "$(cat <<'EOF'
## Brief Description

[One-line summary of release]

### Visual Changes (if applicable)
- Visual feedback / UI improvements
- New indicators

### Added
- New features
- New skills/commands

### Fixed
- Bug fixes
- Performance improvements

### Enhanced
- Improvements to existing features

---

## Installation

### New Users
```
/plugin marketplace add nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
/claude-octopus:setup
```

### Existing Users (Update)

**Option A: Via Plugin UI**
1. `/plugin` to open plugin screen
2. Navigate to "Installed" tab
3. Find `claude-octopus@nyldn-plugins`
4. Click update button

**Option B: Reinstall (Most Reliable)**
```
/plugin uninstall claude-octopus
/plugin marketplace update nyldn-plugins
/plugin install claude-octopus@nyldn-plugins
```

**After updating:** Restart Claude Code to load the new version.

---

**Full Changelog**: https://github.com/nyldn/claude-octopus/blob/main/CHANGELOG.md
EOF
)"
```

### 7. Push Final Changes

```bash
git push origin main
```

### 8. Verify Release

Check that:

- [ ] GitHub release is published: https://github.com/nyldn/claude-octopus/releases
- [ ] Git tag exists: `git tag -l vX.Y.Z`
- [ ] Marketplace description shows version (users see "vX.Y.Z - ..." in plugin UI)
- [ ] README badge shows correct version
- [ ] CHANGELOG is up to date

### 9. Announce Release (Optional)

If this is a major release:
- Post in Discord/Slack communities
- Update any external documentation
- Notify contributors

## Version Numbering

Claude Octopus uses semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR** (X.0.0): Breaking changes, major architecture changes
- **MINOR** (0.Y.0): New features, new workflows, significant improvements
- **PATCH** (0.0.Z): Bug fixes, documentation updates, minor improvements

### Examples

- `v7.4.0` - Major features (visual feedback, natural language workflows)
- `v7.4.1` - Bug fix or documentation update
- `v8.0.0` - Breaking change (e.g., require different Claude Code version)

## Common Issues

### Test Suite Fails

If `test-docs-sync.sh` fails:

1. **Version mismatch**: Ensure all version numbers match (plugin.json, marketplace.json, README.md badge)
2. **Marketplace description**: Version must be at START: "vX.Y.Z - ..."
3. **CHANGELOG missing**: Add `## [X.Y.Z] - YYYY-MM-DD` section
4. **README structure**: Check all required sections exist
5. **Skills not registered**: Add new skills to `.claude-plugin/plugin.json`

### Git Push Rejected

If `git push` is rejected:

```bash
# Pull latest changes
git pull origin main --no-rebase --no-edit

# Resolve any conflicts
# Then commit and push again
git push origin main
```

### Marketplace Not Updating

If users don't see the new version:

1. Verify marketplace.json has correct version
2. Check version is at START of description
3. Users may need to run `/plugin marketplace update nyldn-plugins`
4. Some users may need to reinstall (Option B)

## Release Checklist Template

Copy this for each release:

```markdown
## Release vX.Y.Z Checklist

- [ ] Updated `.claude-plugin/plugin.json` version
- [ ] Updated `.claude-plugin/marketplace.json` version
- [ ] **Verified marketplace description starts with "vX.Y.Z -"**
- [ ] Updated README.md version badge
- [ ] Updated CHANGELOG.md with release notes
- [ ] Ran `./tests/unit/test-docs-sync.sh` (all 50+ tests passing)
- [ ] Committed version changes
- [ ] Created git tag `vX.Y.Z`
- [ ] Pushed tag to GitHub
- [ ] Created GitHub Release with install instructions
- [ ] Pushed final changes to main
- [ ] Verified release on GitHub
- [ ] **Verified marketplace shows version (users can see "vX.Y.Z" at a glance)**
```

## Notes

- **Marketplace visibility is critical**: Users complained when version wasn't visible in v7.3
- Always put version at START of marketplace description: "vX.Y.Z - ..."
- Test suite includes marketplace version check (added in v7.4)
- GitHub Releases must be created manually (not automatic)
- Some users prefer reinstall over update (more reliable)

---

*Last updated: 2026-01-18 for v7.4.0 release*
