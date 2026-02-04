# Release Automation Guide

This document explains the automated release process for Claude Octopus and how to ensure GitHub releases are never missed.

## 🚀 Automated Release Process

Claude Octopus has a fully automated release workflow that ensures consistency and prevents missing releases.

### Components

1. **validate-release.sh** - Pre-release validation and auto-creation script
2. **pre-push hook** - Git hook that runs validation before pushing
3. **install-hooks.sh** - Hook installation script
4. **CHANGELOG.md** - Single source of truth for release notes

## How It Works

### 1. Pre-Push Hook Execution

Every time you push to the repository, the pre-push hook automatically:

1. ✅ **Validates version consistency** across all manifests
2. ✅ **Checks command/skill registration** in plugin.json
3. ✅ **Verifies CHANGELOG entry** exists for current version
4. ✅ **Creates/updates git tag** if missing or outdated
5. ✅ **Pushes tag to remote** automatically
6. ✅ **Creates GitHub release** from CHANGELOG entry
7. ✅ **Marks latest release** appropriately

### 2. Automatic GitHub Release Creation

When a tag is pushed, the script:

```bash
# Extracts CHANGELOG entry for the version
RELEASE_NOTES=$(awk "/## \[$VERSION\]/,/^---$/" CHANGELOG.md)

# Creates GitHub release with extracted notes
gh release create "$TAG" \
  --title "v$VERSION" \
  --notes "$RELEASE_NOTES" \
  --latest
```

### 3. Validation Gates

The script performs 10 validation checks:

| Check | What It Validates | Severity |
|-------|------------------|----------|
| 1. Plugin Names | `plugin.json` name = "octo", `marketplace.json` name = "claude-octopus" | 🔴 Critical |
| 2. Version Sync | All manifests have same version | 🔴 Critical |
| 3. Command Registration | All commands registered in plugin.json | 🔴 Critical |
| 4. Command Frontmatter | No namespace prefix in command frontmatter | 🔴 Critical |
| 5. Skill Registration | All skills registered in plugin.json | 🔴 Critical |
| 6. Skill Frontmatter | Descriptive prefixes (skill-, flow-, sys-, octopus-) | 🔴 Critical |
| 7. Marketplace Description | Mentions current version | 🟡 Warning |
| 8. Git Tag | Tag exists and points to HEAD | 🟢 Auto-fix |
| 9. CHANGELOG Entry | Version documented in CHANGELOG.md | 🔴 Critical |
| 10. GitHub Release | Release exists on GitHub | 🟢 Auto-create |

## 📋 Release Checklist

### For Every Release

1. **Update version numbers** in all manifests:
   ```bash
   # Update these files:
   - package.json
   - .claude-plugin/plugin.json
   - .claude-plugin/marketplace.json
   - README.md (version badge)
   - tests/test-version-consistency.sh (EXPECTED_VERSION)
   ```

2. **Add CHANGELOG entry** with this format:
   ```markdown
   ## [X.Y.Z] - YYYY-MM-DD

   ### Added
   - New features

   ### Changed
   - Modified functionality

   ### Fixed
   - Bug fixes

   ### Documentation
   - Documentation updates
   ```

3. **Commit the changes**:
   ```bash
   git add .
   git commit -m "chore: bump version to X.Y.Z"
   ```

4. **Push to remote**:
   ```bash
   git push origin main
   ```

   The pre-push hook will automatically:
   - Validate everything
   - Create/update the git tag
   - Push the tag
   - Create the GitHub release

### First-Time Setup

If you haven't installed the git hooks yet:

```bash
bash scripts/install-hooks.sh
```

This creates a symlink from `.git/hooks/pre-push` to `hooks/pre-push`.

### Manual Release Creation (If Needed)

If you need to manually create a release:

```bash
# Run the validation script directly
bash scripts/validate-release.sh

# Or create a specific release manually
gh release create v7.25.1 \
  --title "v7.25.1" \
  --notes "$(awk '/## \[7.25.1\]/,/^## \[/' CHANGELOG.md | sed '$d' | tail -n +3)" \
  --latest
```

## 🔧 Troubleshooting

### Hook Not Running

If the pre-push hook doesn't run:

```bash
# Check if hook is installed
ls -la .git/hooks/pre-push

# Should show:
# lrwxr-xr-x  ...  .git/hooks/pre-push -> ../../hooks/pre-push

# If not, reinstall:
bash scripts/install-hooks.sh
```

### Validation Fails

If validation fails before push:

1. Read the error messages carefully
2. Fix the issues (version mismatches, missing registrations, etc.)
3. Commit the fixes
4. Try pushing again

### Missing GitHub Release

If a release is missing on GitHub:

```bash
# List all tags
git tag -l 'v*' --sort=-version:refname

# List all GitHub releases
gh release list

# Create missing release manually
VERSION="7.25.0"  # Replace with your version
gh release create "v$VERSION" \
  --title "v$VERSION" \
  --notes "$(awk "/## \[$VERSION\]/,/^## \[/" CHANGELOG.md | sed '$d' | tail -n +3)"
```

### Tag Points to Wrong Commit

If a tag points to the wrong commit:

```bash
# Delete local and remote tag
git tag -d v7.25.1
git push origin :refs/tags/v7.25.1

# Create new tag at current HEAD
git tag -a v7.25.1 -m "Release v7.25.1"

# Push new tag (pre-push hook will create release)
git push origin v7.25.1
```

## 🎯 Best Practices

### 1. Always Use CHANGELOG.md as Source of Truth

The CHANGELOG is used to generate:
- Git tag messages
- GitHub release notes
- Version documentation

Keep it comprehensive and well-formatted.

### 2. Version Bumps Should Be Atomic

When bumping versions:
- Update all manifests in a single commit
- Add CHANGELOG entry in the same commit
- Don't mix feature changes with version bumps

### 3. Let Automation Handle Tags and Releases

Don't manually create tags or releases unless necessary. The pre-push hook handles this automatically.

### 4. Test Before Releasing

Always run tests before version bumps:

```bash
# Run all tests
make test

# Run version consistency test
bash tests/test-version-consistency.sh
```

### 5. Semantic Versioning

Follow semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR** (X.0.0): Breaking changes
- **MINOR** (7.X.0): New features, backward compatible
- **PATCH** (7.25.X): Bug fixes, backward compatible

## 📊 Monitoring Releases

### Check Release Status

```bash
# List recent releases
gh release list --limit 10

# View specific release
gh release view v7.25.1

# Check latest release
gh release view --web
```

### Verify Version Consistency

```bash
# Run comprehensive validation
bash scripts/validate-release.sh

# Run version tests
bash tests/test-version-consistency.sh
```

## 🔄 Backfilling Missing Releases

If you discover missing releases:

```bash
# List all tags
git tag -l 'v*' --sort=-version:refname

# List all GitHub releases
gh release list --limit 50

# Compare and create missing releases
# For each missing release, run:
VERSION="7.XX.X"
gh release create "v$VERSION" \
  --title "v$VERSION" \
  --notes "$(awk "/## \[$VERSION\]/,/^## \[/" CHANGELOG.md | sed '$d' | tail -n +3)"
```

## ⚠️ Important Notes

### Pre-Push Hook Uses --no-verify

The pre-push hook itself uses `--no-verify` when pushing tags to prevent infinite loops:

```bash
git push --no-verify origin "$TAG"
```

This is safe because the validation has already run.

### CHANGELOG Entry Required

The script will **fail** if there's no CHANGELOG entry for the current version. This ensures all releases are documented.

### "Latest" Release Flag

The script automatically marks new releases as "latest" unless they're being backfilled. For backfilled releases, you may need to manually update the latest flag:

```bash
gh release edit v7.25.1 --latest
```

## 📚 Related Documentation

- **validate-release.sh** - Full validation script implementation
- **hooks/pre-push** - Pre-push hook that triggers validation
- **CHANGELOG.md** - Release notes source of truth
- **CONTRIBUTING.md** - General contribution guidelines

## 🐙 Summary

With this automated release process:

1. ✅ **Never miss a GitHub release** - Automatically created on every push
2. ✅ **Consistent versioning** - Validated across all manifests
3. ✅ **Documented releases** - CHANGELOG drives release notes
4. ✅ **Quality gates** - 10 validation checks before release
5. ✅ **Zero manual steps** - Just push, automation handles the rest

The system is designed to be foolproof: if anything is wrong, it fails fast with clear error messages.
