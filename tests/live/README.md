# Live Tests

Real Claude Code integration tests that run actual sessions to verify plugin behavior.

## Why Live Tests?

Some behaviors can't be tested with mocks:
- Skill loading patterns
- Natural language trigger matching
- Claude's interpretation of instructions
- Recursive loop detection

## Running Live Tests

```bash
# Run all live tests
make test-live

# Run with verbose output
VERBOSE=true make test-live

# Run specific test
bash tests/live/test-prd-skill.sh
```

## Requirements

- Claude Code CLI installed (`claude` command available)
- Plugin installed locally or via symlink
- ~2-5 minutes per test (real API calls)

## Writing Live Tests

```bash
#!/bin/bash
source tests/helpers/live-test-harness.sh

live_test "My Test Name" \
    "prompt to send to claude" \
    --timeout 120 \
    --max-skill-loads 2 \
    --expect "pattern that must appear" \
    --reject "pattern that must NOT appear" \
    --workdir "/path/to/test/dir"

live_test_summary
```

## Options

| Option | Description |
|--------|-------------|
| `--timeout N` | Max seconds to wait (default: 120) |
| `--expect PATTERN` | Regex that MUST appear in output |
| `--reject PATTERN` | Regex that must NOT appear |
| `--max-skill-loads N` | Max allowed `Skill()` calls |
| `--workdir DIR` | Working directory for Claude |

## Test Files

| File | Tests |
|------|-------|
| `test-prd-skill.sh` | PRD creation without skill loops |
| `test-skill-loading.sh` | General skill loading efficiency |

## Logs

Test logs are saved to `/tmp/claude-octopus-live-tests/logs/`

## Cost Warning

Live tests make real API calls. Each test typically uses:
- Claude: Included with subscription
- Codex/Gemini: $0.01-0.10 per test (if invoked)

Run sparingly and use `--timeout` to limit runaway tests.
