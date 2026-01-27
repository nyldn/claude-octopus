# Codex Sandbox Configuration

This guide explains how to configure Codex sandbox mode for advanced use cases like mounted filesystems.

## Overview

By default, Codex agents run in `workspace-write` sandbox mode, which restricts filesystem access to the current workspace. This prevents access to mounted filesystems (SSHFS, NFS, FUSE) and other paths outside the workspace.

**Added in:** v7.13.1 (addressing [Issue #9](https://github.com/nyldn/claude-octopus/issues/9))

## When You Need This

You may need to configure sandbox mode if:
- Working with repositories on mounted filesystems (SSHFS, NFS, CIFS)
- Running code audits on remote repositories
- Using multi-device setups with shared storage
- Working in CI/CD environments with mounted artifact directories
- Getting `Sandbox(LandlockRestrict)` errors from Codex

## Sandbox Modes

| Mode | Description | Use Case | Risk Level |
|------|-------------|----------|----------|
| `workspace-write` | Access limited to workspace (default) | Normal development | Low |
| `read-only` | Read-only access to workspace | Safe code audits | Low |
| `danger-full-access` | Full filesystem access | Mounted filesystems | **High** |

## Configuration

### Environment Variable (Recommended)

Set the `OCTOPUS_CODEX_SANDBOX` environment variable:

```bash
# Temporary (current session only)
export OCTOPUS_CODEX_SANDBOX=danger-full-access
octo research "audit code in mounted repo"

# Permanent (add to ~/.bashrc or ~/.zshrc)
echo 'export OCTOPUS_CODEX_SANDBOX=danger-full-access' >> ~/.bashrc
source ~/.bashrc
```

### Per-Command Override

```bash
# One-time override
OCTOPUS_CODEX_SANDBOX=danger-full-access octo research "audit /mnt/nas/repo"
```

### Verify Configuration

Check what sandbox mode is active:

```bash
echo "Current sandbox mode: ${OCTOPUS_CODEX_SANDBOX:-workspace-write}"
```

## Example Use Cases

### SSHFS Mounted Repository

```bash
# Mount remote repository
sshfs user@server:/projects /mnt/projects

# Configure sandbox
export OCTOPUS_CODEX_SANDBOX=danger-full-access

# Run audit
cd /mnt/projects/my-repo
octo research "analyze authentication implementation"
```

### NFS Shared Storage

```bash
# NFS mount at /opt/shared
export OCTOPUS_CODEX_SANDBOX=danger-full-access

# Run embrace workflow
cd /opt/shared/repos/published/my-project
/octo:embrace "comprehensive security audit"
```

### CI/CD Pipeline

```bash
# .gitlab-ci.yml or .github/workflows/audit.yml
env:
  OCTOPUS_CODEX_SANDBOX: danger-full-access

script:
  - octo review "security audit on artifact directory"
```

## Security Considerations

### ⚠️ Risks of `danger-full-access`

- **Full filesystem access**: Codex can read any file the user can read
- **Data exfiltration risk**: Malicious prompts could leak sensitive data
- **Unintended modifications**: Write operations outside workspace

### ✅ Mitigation Strategies

1. **Use for read-only tasks only**: Code audits, research, analysis
2. **Trust your prompts**: Only run Octopus on trusted repositories
3. **Review outputs**: Check what Codex accessed in logs
4. **Temporary override**: Use per-command override instead of permanent export
5. **Mount with restrictions**: Use `noexec` and `ro` flags where possible

```bash
# Example: Read-only SSHFS mount
sshfs user@server:/repos /mnt/repos -o ro,noexec
```

6. **Output isolation**: Octopus only writes to `~/.claude-octopus/results/` by design

### Recommended Configuration

**For trusted repositories (read-only audits):**
```bash
export OCTOPUS_CODEX_SANDBOX=danger-full-access
```

**For untrusted code or write operations:**
```bash
# Use default (or don't set OCTOPUS_CODEX_SANDBOX)
unset OCTOPUS_CODEX_SANDBOX
```

## Troubleshooting

### Issue: `Sandbox(LandlockRestrict)` Error

**Symptom:** Codex fails with:
```
error running landlock: Sandbox(LandlockRestrict)
```

**Solution:**
```bash
export OCTOPUS_CODEX_SANDBOX=danger-full-access
```

### Issue: Permission Denied on Mounted Filesystem

**Symptom:** Codex can't access files on `/mnt/`, `/opt/`, etc.

**Solution:**
1. Check mount is accessible: `ls /mnt/your-mount`
2. Set sandbox mode: `export OCTOPUS_CODEX_SANDBOX=danger-full-access`
3. Verify mount permissions: `stat /mnt/your-mount`

### Issue: Warning Messages

**Symptom:** Seeing warnings about non-default sandbox mode

**This is expected** and intentional. The warnings remind you that you're using a less restrictive sandbox mode.

To suppress warnings (not recommended):
```bash
OCTOPUS_LOG_LEVEL=ERROR OCTOPUS_CODEX_SANDBOX=danger-full-access octo research ...
```

## Advanced: Future Configuration Options

**Coming in future versions:**

- `.octopus.yml` configuration file support
- Per-agent sandbox configuration
- CLI flag: `--codex-sandbox MODE`
- Integration with `/octo:setup` wizard

See [Issue #9](https://github.com/nyldn/claude-octopus/issues/9) for roadmap.

## Examples

### Example 1: Multi-Device Development Setup

```bash
# Developer laptop with NAS-mounted repos
ssh user@nas mkdir -p /data/repos
sshfs user@nas:/data/repos /mnt/nas-repos

# Configure Octopus
export OCTOPUS_CODEX_SANDBOX=danger-full-access

# Run audit on published repos
cd /mnt/nas-repos/my-published-project
octo review "comprehensive security audit"
```

### Example 2: CI/CD Security Scanning

```yaml
# .github/workflows/security-audit.yml
name: Security Audit with Octopus

on: [pull_request]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Mount artifact storage
        run: |
          mkdir -p /mnt/artifacts
          # mount artifact storage

      - name: Run Octopus Security Audit
        env:
          OCTOPUS_CODEX_SANDBOX: danger-full-access
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          octo review "security audit focusing on authentication"
```

## See Also

- [Issue #9](https://github.com/nyldn/claude-octopus/issues/9) - Original feature request
- [Codex CLI Documentation](https://github.com/openai/codex) - Sandbox mode reference
- [SSHFS Guide](https://github.com/libfuse/sshfs) - Mounting remote filesystems

## Need Help?

If you're experiencing issues with sandbox configuration:

1. Check your Codex version: `codex --version`
2. Verify mount accessibility: `ls -la /your/mount/path`
3. Test with simple command: `codex exec --sandbox danger-full-access "ok"`
4. Open an issue: https://github.com/nyldn/claude-octopus/issues

---

**Last Updated:** v7.13.1
**Related Issue:** [#9](https://github.com/nyldn/claude-octopus/issues/9)
