# Security Tests

This directory contains security-focused tests for the Claude Octopus project.

## Test Files

### test-secret-disclosure.sh

Comprehensive security test suite for detecting accidental API key/token disclosure.

**What it checks:**

1. **Current Files:**
   - No OpenAI API keys (sk-...) in current codebase
   - No Gemini API keys (AIza...) in current codebase
   - No GitHub tokens (ghp_, gho_, ghs_, ghu_) in current codebase
   - No AWS access keys (AKIA...) in current codebase
   - No hardcoded credentials in config files (JSON, YAML, TOML, INI)
   - No private keys (.pem, .key files) committed
   - No .env files committed

2. **Git History:**
   - No OpenAI keys in git history (last 100 commits)
   - No Gemini keys in git history (last 100 commits)

3. **.gitignore Protection:**
   - .env files are in .gitignore
   - Private key patterns (*.pem, *.key) in .gitignore
   - Credential patterns (*credentials*) in .gitignore

4. **Documentation Safety:**
   - No API keys accidentally pasted in markdown/text files
   - Example configs use placeholders, not real keys

5. **Log File Safety:**
   - No API keys leaked in log files

## Running Security Tests

```bash
# Run security tests only
./tests/security/test-secret-disclosure.sh

# Run all tests including security
./tests/run-all.sh
```

## Test Results

- **13 tests** (14 total, 1 skipped when no logs exist)
- **100% pass rate** required for CI/CD
- **Any failure** indicates potential security issue requiring immediate attention

## What to Do If Tests Fail

### If current files contain secrets:

1. **Remove the secret immediately:**
   ```bash
   # Edit the file and remove the secret
   git add <file>
   git commit -m "security: Remove exposed secret"
   ```

2. **Rotate the compromised secret:**
   - Generate a new API key from the provider
   - Update your local environment
   - Delete the old key from the provider

3. **Add pattern to .gitignore** if needed

### If git history contains secrets:

**CRITICAL:** Secrets in git history are permanently exposed even if removed from current files.

1. **Rotate the secret immediately** - assume it's compromised
2. **Contact security team** if this is a production key
3. **Consider git history rewrite** (advanced):
   ```bash
   # Use BFG Repo-Cleaner or git filter-branch
   # WARNING: This rewrites history and requires force push
   ```

4. **For public repositories:** Assume the key is public knowledge

## API Key Patterns Detected

| Provider | Pattern | Example |
|----------|---------|---------|
| OpenAI | `sk-[a-zA-Z0-9]{48}` | sk-proj-abc123... |
| Gemini | `AIza[0-9A-Za-z_-]{35}` | AIzaSyAbc123... |
| GitHub | `gh[pousr]_[A-Za-z0-9]{36,255}` | ghp_abc123... |
| AWS | `AKIA[0-9A-Z]{16}` | AKIAIOSFODNN7... |

## Best Practices

### ✅ DO:
- Use environment variables for all secrets
- Add .env* to .gitignore
- Use placeholder values in example configs
- Store secrets in password managers
- Rotate keys if you suspect exposure
- Use short-lived tokens when possible

### ❌ DON'T:
- Commit .env files
- Hardcode API keys in code
- Include keys in config files
- Paste keys in documentation
- Share keys via git
- Store keys in plaintext

## Integration with CI/CD

Security tests run automatically in:
- Pre-push hooks (version check includes basic validation)
- CI/CD pipelines
- Test suite runs

**Exit code 1** = Security issue detected (blocks merge/deploy)
**Exit code 0** = All security checks passed

## Adding New Secret Patterns

To detect additional secret types:

1. Add pattern to `test-secret-disclosure.sh`
2. Create test function following naming convention
3. Add to test runner at bottom of file
4. Document the pattern in this README

Example:
```bash
test_no_slack_tokens_in_files() {
    test_case "No Slack tokens in current files"
    local findings=$(grep -r -E "xox[baprs]-[0-9a-zA-Z]{10,}" "$PROJECT_ROOT" ...)
    # ... test logic
}
```

## False Positives

The test suite filters common false positives:
- Placeholder values (YOUR_API_KEY, your-api-key)
- Environment variable names (OPENAI_API_KEY without value)
- Documentation examples
- Test fixtures with "example" or "placeholder"

If you encounter false positives, update the filter patterns in the test.

## Security Contact

For security issues found by these tests:
- **Public repo**: Create issue (if not sensitive) or contact maintainers
- **Private repo**: Follow your organization's security reporting process
- **Exposed production keys**: Escalate immediately

## License

MIT - Same as Claude Octopus project
