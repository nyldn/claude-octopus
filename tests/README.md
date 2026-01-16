# Claude Octopus Test Suite

Comprehensive testing infrastructure for Claude Octopus multi-agent orchestration.

## Quick Start

```bash
# Run smoke + unit tests (default)
make test

# Run all tests
make test-all

# Run specific category
make test-smoke      # <30s
make test-unit       # 1-2min
make test-integration # 5-10min
make test-e2e        # 15-30min

# Using npm
npm test
npm run test:all
npm run test:smoke
```

## Test Categories

### Smoke Tests (`tests/smoke/`)
**Duration:** <30s | **Purpose:** Pre-commit validation

Quick sanity checks that run before every commit:
- `test-syntax.sh` - Shell script syntax validation
- `test-help-commands.sh` - Help and usage output
- `test-detect-providers.sh` - Provider detection logic
- `test-dry-run-all.sh` - Dry-run mode for all commands

**When to run:** Before every commit, automatically in CI

### Unit Tests (`tests/unit/`)
**Duration:** 1-2min | **Purpose:** Function-level tests

Tests individual functions in isolation using mocks:
- `test-classification.sh` - Intent classification accuracy
- `test-routing.sh` - Provider selection logic
- `test-version-compare.sh` - Version comparison utility
- `test-personas.sh` - All 21 personas validated
- `test-quality-gates.sh` - Quality threshold calculations
- `test-cost-tracking.sh` - Cost estimation logic

**When to run:** On every push, part of default `make test`

### Integration Tests (`tests/integration/`)
**Duration:** 5-10min | **Purpose:** Workflow validation

Tests complete workflows with mocked CLI responses:
- `test-probe-workflow.sh` - Research phase
- `test-grasp-workflow.sh` - Requirements definition
- `test-tangle-workflow.sh` - Implementation with quality gates
- `test-ink-workflow.sh` - Refinement phase
- `test-embrace-full.sh` - Complete Double Diamond (all 4 phases)
- `test-grapple-debate.sh` - Adversarial debate (3 rounds)
- `test-squeeze-security.sh` - Security review (4 phases)
- `test-auto-routing.sh` - Intent-based command routing
- `test-provider-failover.sh` - Provider fallback logic
- `test-context-passing.sh` - Multi-phase context continuity
- `test-error-recovery.sh` - Timeout and retry handling

**When to run:** On PR to main branch

### E2E Tests (`tests/e2e/`)
**Duration:** 15-30min | **Purpose:** Real execution validation

Tests with actual API calls (small, fast prompts):
- `test-simple-task.sh` - Basic probe with real CLI
- `test-parallel-agents.sh` - Multi-agent coordination
- `test-full-embrace.sh` - Complete workflow end-to-end
- `test-quality-gate-fail.sh` - Real quality gate rejection
- `test-ci-mode.sh` - CI/CD integration

**When to run:** On main branch + nightly builds

## Test Framework

### Core Components

**`tests/helpers/test-framework.sh`** - Core testing infrastructure:
- Test suite/case organization
- Advanced assertions (equals, contains, matches, JSON, files, performance)
- Mock infrastructure for commands
- JUnit XML report generation
- Before/after hooks
- Test summary and reporting

**`tests/helpers/mock-helpers.sh`** - CLI mocking utilities:
- Mock codex/gemini responses
- Quality score simulation
- Timeout/rate limit/error mocking
- Multi-phase workflow mocking (grapple, squeeze)
- Context and session mocking
- Provider availability mocking

### Writing Tests

#### Basic Test Structure

```bash
#!/bin/bash
# tests/unit/test-example.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Example Test Suite"

test_basic_functionality() {
    test_case "Feature works as expected"

    local result=$(some_command "input")

    assert_equals "expected" "$result" "Output should match"
    assert_contains "$result" "keyword" "Should contain keyword"

    test_pass
}

# Run tests
test_basic_functionality

test_summary
```

#### Using Mocks

```bash
source "$SCRIPT_DIR/../helpers/mock-helpers.sh"

test_with_mock() {
    test_case "Works with mocked CLI"

    # Create mock response
    local response=$(create_success_response "codex" "Mock output")
    mock_codex "$response" 0

    # Run command that uses codex
    local result=$(orchestrate probe -n "test")

    # Verify mock was called
    assert_mock_called "codex" 1

    test_pass
}
```

#### Quality Score Testing

```bash
test_quality_gate() {
    test_case "Quality gate passes with 90% score"

    mock_with_quality "codex" 90 "High quality implementation"
    mock_with_quality "gemini" 95 "Excellent solution"

    local result=$(orchestrate tangle -n "test")

    assert_contains "$result" "PASS\|quality gate"

    test_pass
}
```

### Available Assertions

**Basic:**
- `assert_equals expected actual [message]`
- `assert_not_equals not_expected actual [message]`
- `assert_contains haystack needle [message]`
- `assert_not_contains haystack needle [message]`
- `assert_matches string pattern [message]`
- `assert_true condition [message]`
- `assert_false condition [message]`

**Files:**
- `assert_file_exists file [message]`
- `assert_file_not_exists file [message]`
- `assert_file_contains file pattern [message]`
- `assert_dir_exists dir [message]`

**Exit Codes:**
- `assert_exit_code expected actual [message]`
- `assert_success exit_code [message]`
- `assert_failure exit_code [message]`

**JSON:**
- `assert_json_equals expected actual [message]`
- `assert_json_contains json key value [message]`

**Performance:**
- `assert_within_time max_seconds command [message]`

**Mocks:**
- `assert_mock_called command [times] [message]`
- `assert_mock_called_with command args [message]`
- `assert_agents_called_in_order agent1 agent2`
- `assert_parallel_execution agent1 agent2 [max_diff]`

## Test Fixtures

### Using Fixtures

Fixtures are stored in `tests/fixtures/`:

```bash
# Load fixture
local sample=$(load_fixture "sample-tasks/probe-research.md")

# Create temp file
local temp=$(create_temp_file "content" "filename.txt")
```

### Available Fixtures

**`tests/fixtures/mock-agents/`** - Canned CLI responses
- `codex-success.txt` - Successful codex response
- `gemini-success.txt` - Successful gemini response
- `quality-90.txt` - Response with 90% quality score

**`tests/fixtures/sample-tasks/`** - Task definitions
- `probe-research.md` - Research task
- `tangle-implementation.md` - Implementation task
- `grapple-debate.md` - Debate scenario

**`tests/fixtures/expected-outputs/`** - Golden files
- `embrace-summary.md` - Expected embrace output
- `quality-report.md` - Expected quality assessment

## Coverage Tracking

### Generate Coverage Report

```bash
make test-coverage
```

Generates:
- Function coverage percentage
- List of untested functions
- HTML report (coverage.html)

### Coverage Goals

| Component | Target | Current |
|-----------|--------|---------|
| Core Functions | 95% | 95%+ |
| Workflows | 100% | 100% |
| Error Handlers | 90% | 90%+ |
| Overall | 95% | 95%+ |

## CI/CD Integration

### GitHub Actions

Tests run automatically on:
- **Every push:** Smoke + Unit tests
- **PRs to main:** Smoke + Unit + Integration
- **Main branch:** All tests including E2E
- **Nightly:** Complete test suite + coverage

### Configuration

See `.github/workflows/test.yml`

### Local CI Simulation

```bash
# Run same tests as CI
JUNIT_OUTPUT=test-results.xml make test-all
```

## Common Scenarios

### Testing New Features

1. Write unit tests first (TDD)
2. Run `make test-unit` frequently
3. Add integration test for workflow
4. Update coverage report
5. Ensure coverage doesn't drop

### Debugging Test Failures

```bash
# Run with verbose output
make test-verbose

# Run specific test
bash tests/unit/test-routing.sh

# Check test logs
ls /tmp/test_*.log
```

### Before Committing

```bash
# Quick pre-commit check
make test-smoke

# Full pre-commit check
make test
```

## Troubleshooting

### "Mock not called" errors

Ensure mocks are set up before running commands:

```bash
mock_codex "$response_file" 0
# Now run command
result=$(orchestrate probe -n "test")
```

### "Fixture not found" errors

Check fixture path is relative to fixtures directory:

```bash
# Wrong
load_fixture "/full/path/to/fixture"

# Right
load_fixture "sample-tasks/probe-research.md"
```

### Tests passing locally but failing in CI

- Check environment variables (CI may not have same setup)
- Verify file paths are absolute when needed
- Check for timing-dependent tests
- Ensure mocks don't depend on local state

## Performance Guidelines

### Test Speed Targets

- Smoke tests: <30s total
- Unit tests: <2min total
- Integration tests: <10min total
- E2E tests: <30min total

### Optimization Tips

1. Use mocks instead of real API calls
2. Run independent tests in parallel
3. Skip slow tests in smoke suite
4. Cache fixture files
5. Clean up test artifacts regularly

## Contributing

### Adding New Tests

1. Choose appropriate category (smoke/unit/integration/e2e)
2. Follow naming convention: `test-feature-name.sh`
3. Use test framework assertions
4. Add documentation to this README
5. Update coverage tracking
6. Ensure tests are idempotent

### Test Naming Conventions

- Smoke: `test-quick-check.sh`
- Unit: `test-function-name.sh`
- Integration: `test-workflow-name.sh`
- E2E: `test-real-scenario.sh`

### Code Review Checklist

- [ ] Tests are deterministic (no random failures)
- [ ] Tests clean up after themselves
- [ ] Tests don't depend on external services (except E2E)
- [ ] Tests have clear failure messages
- [ ] Tests run in reasonable time
- [ ] Coverage maintained or improved

## FAQ

### Q: Do I need both Codex and Gemini to run tests?

A: No! Most tests use mocks. E2E tests can run with just one provider.

### Q: How do I test without making API calls?

A: Use `-n` (dry-run) flag or mocks. All smoke/unit/integration tests use mocks.

### Q: Why are some tests skipped?

A: Tests skip when prerequisites aren't met (e.g., no providers installed). This is normal.

### Q: Can I run tests in parallel?

A: Unit tests can run in parallel. Integration/E2E tests should run sequentially.

### Q: How do I test my local changes?

A: Run `make test` after changes. It runs smoke + unit tests (~2min).

## Resources

- [Main README](../README.md)
- [GitHub Actions Workflow](../.github/workflows/test.yml)
- [Test Framework Source](helpers/test-framework.sh)
- [Mock Helpers Source](helpers/mock-helpers.sh)

## Support

Issues? Questions? Open an issue on GitHub or check existing test implementations for examples.

---

**Current Test Statistics:**

- Total test suites: 25+
- Total test cases: 150+
- Function coverage: 95%+
- Test execution time: <5min (smoke+unit), <40min (all)
- Last updated: 2026-01-16
