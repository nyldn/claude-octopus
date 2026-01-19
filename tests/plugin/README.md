# Plugin Integration Tests

This directory contains integration tests for claude-octopus **as a Claude Code plugin**, not just as standalone bash scripts.

## What These Tests Do

Unlike the bash-level tests in other directories, these tests:

- ✅ Load claude-octopus as an actual Claude Code plugin
- ✅ Test plugin registration and validation
- ✅ Test skill and command discovery
- ✅ Test `/co:command` invocations
- ✅ Test natural language skill triggering
- ✅ Test backward compatibility (probe/grasp/tangle/ink aliases)
- ✅ Test error handling and performance

## Test Architecture

### Test Workspace Isolation

Each test creates an isolated workspace:

```bash
/tmp/claude-octopus-plugin-test-{pid}/
├── src/
│   └── test.js (sample file)
└── settings.json (test config)
```

### Claude Code Integration

Tests use Claude Code's CLI flags:

```bash
claude --plugin-dir /path/to/claude-octopus/.claude-plugin \  # Load plugin
       --print \                                               # Non-interactive
       --no-session-persistence \                              # Don't save session
       --max-budget-usd 0.01 \                                 # Limit API cost
       "/co:discover --help"                                   # Test command
```

## Running Plugin Tests

### Run All Plugin Tests

```bash
./tests/plugin/test-plugin-integration.sh
```

### Run Through Main Test Runner

```bash
./tests/run-all.sh plugin
```

### Run Specific Test Category

```bash
# Just validation
./tests/plugin/test-plugin-integration.sh 2>&1 | grep "Plugin manifest"

# Just command tests
./tests/plugin/test-plugin-integration.sh 2>&1 | grep "command"
```

## Test Categories

### 1. Plugin Validation Tests

**`test_plugin_manifest_valid`**
- Validates `.claude-plugin/plugin.json` using `claude plugin validate`
- Ensures plugin meets Claude Code's requirements

### 2. Plugin Loading Tests

**`test_plugin_loads_in_claude_code`**
- Loads plugin via `--plugin-dir` flag
- Verifies no errors during initialization

**`test_plugin_skills_registered`**
- Checks if skills (discover/define/develop/deliver) are discoverable
- Uses natural language to list available skills

### 3. Command Invocation Tests

**`test_setup_command_works`**
- Tests `/co:setup` command recognition
- Verifies command help is accessible

**`test_dev_command_works`**
- Tests `/co:dev` mode switching command
- Added in v7.6.x for two-mode system

**`test_discover_command_works`**
- Tests `/co:discover` (formerly /co:probe)
- Validates renamed phase commands

### 4. Natural Language Triggering Tests

**`test_natural_language_skill_trigger`**
- Tests skill activation via natural language prompts
- Example: "Help me research authentication patterns"
- May skip if API access unavailable (requires small budget)

### 5. Configuration Tests

**`test_plugin_respects_settings`**
- Tests plugin behavior with custom settings
- Validates settings integration

### 6. Backward Compatibility Tests

**`test_backward_compatible_aliases`**
- Tests old command names (probe, grasp, tangle, ink)
- Ensures v7.6 → v7.7 migration doesn't break workflows

### 7. Error Handling Tests

**`test_graceful_error_handling`**
- Tests plugin behavior without full setup
- Verifies helpful error messages

### 8. Performance Tests

**`test_plugin_load_time`**
- Measures plugin initialization time
- Fails if loading takes >5 seconds

## Test Requirements

### Required

- **Claude Code CLI** installed (`claude --version`)
- **Plugin manifest** valid (`.claude-plugin/plugin.json`)
- **Bash 4.0+** for test framework

### Optional (for some tests)

- **Claude API access** (for natural language triggering tests)
- **Budget allowance** (tests use max $0.01 if API calls needed)
- **Internet connection** (for plugin validation against schemas)

## Test Output Format

Tests use the standard test framework from `tests/helpers/test-framework.sh`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Claude Code Plugin Integration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✓ Plugin manifest passes Claude Code validation
  ✓ Plugin loads successfully in Claude Code
  ✓ Plugin skills are registered and discoverable
  ✓ /co:setup command is recognized
  ✓ /co:dev command is recognized
  ✓ /co:discover command is recognized
  ⊘ Natural language triggering requires API access
  ✓ Plugin respects Claude Code settings
  ✓ Old command aliases still work
  ✓ Plugin handles errors gracefully
  ✓ Plugin loads within reasonable time

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Test Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Total:   11
Passed:  10
Failed:  0
Skipped: 1
Duration: 8s
```

## Writing New Plugin Tests

### Test Template

```bash
test_new_feature() {
    test_case "Description of what this tests"

    setup_test_workspace

    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --print \
                         --no-session-persistence \
                         "your test prompt or /command" 2>&1)

    local exit_code=$?

    cleanup_test_workspace

    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q "expected output"; then
        test_pass
    else
        test_fail "What went wrong"
        echo "$result" | head -20
        return 1
    fi
}
```

### Best Practices

1. **Always use isolated workspace** - Call `setup_test_workspace` and `cleanup_test_workspace`
2. **Capture full output** - Use `2>&1` to capture both stdout and stderr
3. **Check exit codes** - Verify command succeeded before checking output
4. **Show helpful failures** - Include relevant output in failure messages
5. **Use skip for optional tests** - `test_skip "reason"` for tests requiring API/setup
6. **Keep tests fast** - Use `--no-session-persistence` to avoid disk I/O
7. **Limit API costs** - Use `--max-budget-usd 0.01` for tests that might call API

### Testing Different Scenarios

**Test command exists:**
```bash
claude --plugin-dir "$PLUGIN_DIR" --print "/co:command --help" 2>&1
```

**Test skill triggers:**
```bash
claude --plugin-dir "$PLUGIN_DIR" --print "natural language prompt" 2>&1
```

**Test with custom settings:**
```bash
claude --plugin-dir "$PLUGIN_DIR" --settings config.json --print "..." 2>&1
```

**Test specific session:**
```bash
claude --plugin-dir "$PLUGIN_DIR" --session-id "test-uuid" --print "..." 2>&1
```

## Integration with CI/CD

Plugin tests can run in CI pipelines:

```yaml
# .github/workflows/test.yml
- name: Run Plugin Integration Tests
  run: |
    ./tests/plugin/test-plugin-integration.sh
  env:
    CLAUDE_API_KEY: ${{ secrets.CLAUDE_API_KEY }}  # Optional for API tests
```

**Exit Codes:**
- `0` = All tests passed
- `1` = One or more tests failed
- Tests with skipped results still exit 0

## Troubleshooting

### "Plugin validation failed"

Check plugin.json syntax:
```bash
claude plugin validate .claude-plugin
```

### "Plugin failed to load"

Check for errors in plugin initialization:
```bash
claude --plugin-dir .claude-plugin --debug --print "hello" 2>&1 | less
```

### "Skills not registered"

Verify skill files exist and have proper frontmatter:
```bash
ls -la .claude/skills/
head -20 .claude/skills/discover.md
```

### "Command not recognized"

Check command is in plugin.json:
```bash
jq '.commands[]' .claude-plugin/plugin.json
```

### Tests timeout or hang

Ensure you're using `--no-session-persistence` to avoid interactive prompts:
```bash
claude --plugin-dir .claude-plugin --print --no-session-persistence "test"
```

## Future Enhancements

Potential additions to plugin test suite:

1. **Hook Testing** - Test PreToolUse, PostToolUse, Stop hooks
2. **MCP Integration Testing** - Test MCP server integration
3. **Multi-Session Testing** - Test session persistence and resumption
4. **Concurrent Testing** - Test multiple Claude instances with plugin
5. **Workflow E2E Testing** - Test full discover→define→develop→deliver flow
6. **AI Provider Mocking** - Mock Codex/Gemini responses for deterministic tests
7. **Performance Benchmarking** - Track plugin overhead on Claude response time
8. **Settings Validation** - Test all configuration combinations

## Related Documentation

- Main tests: `tests/README.md`
- Security tests: `tests/security/README.md`
- Plugin development: `.claude-plugin/README.md`
- Natural language triggers: `docs/TRIGGER_PATTERNS.md`

## License

MIT - Same as Claude Octopus project
