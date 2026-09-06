## Description
Brief description of changes.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring
- [ ] Other (describe):

## Checklist
- [ ] Code passes `bash -n scripts/orchestrate.sh`
- [ ] Shell scripts pass `bash -n` syntax check
- [ ] New skills/commands registered in `.claude-plugin/plugin.json`
- [ ] Version bump (if releasing): package.json + plugin/marketplace manifests + public adapter manifests + README.md + CHANGELOG.md
- [ ] Documentation updated (if applicable)
- [ ] CHANGELOG.md updated (for features/fixes)

## Testing
How was this tested? Which test suites were run?

For installation, setup, or package changes, record the applicable checks from
the [delivery contract](../RELEASING.md#delivery-contract-for-workflow-methods),
including the host version and any user paths that remain unverified.

```bash
# Run pre-push suite
bash tests/run-all-tests.sh

# Run specific test
bash tests/unit/test-<name>.sh
```

## Related Issues
Closes #
