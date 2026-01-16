# Security Policy for Claude Octopus

## Threat Model

Claude Octopus orchestrates external AI CLI tools (Codex CLI, Gemini CLI) with user-provided prompts. This creates the following threat surfaces:

### Trust Boundaries

| Boundary | Description | Risk Level |
|----------|-------------|------------|
| User Input | Prompts and commands from CLI | Medium |
| Environment Variables | API keys, workspace paths | Medium |
| Task Files | JSON files defining parallel execution | Medium |
| CI/CD Environment | GitHub Actions workflow inputs | High |
| External CLIs | Codex and Gemini CLI responses | Low |

### Attack Vectors and Mitigations

| Vector | Risk | Mitigation |
|--------|------|------------|
| Shell injection via prompts | Medium | Prompts passed as single quoted arguments; array-based execution |
| Path traversal in workspace | Medium | `validate_workspace_path()` restricts to `$HOME` or `/tmp` |
| Malicious task.json | Medium | `validate_agent_type()` checks against allowlist; JSON parsing with error handling |
| CI workflow injection | High | Environment variable sanitization; command allowlisting |
| API key exposure | Low | Keys never logged or echoed; masked in verbose output |

## Security Controls

### 1. Input Validation (v4.6.0)

- **Workspace Path Validation**: All workspace paths validated against safe locations
- **Agent Type Validation**: All agent types checked against `AVAILABLE_AGENTS` allowlist
- **JSON Parsing**: Safe extraction with `extract_json_field()` function
- **CI Input Sanitization**: Workflow inputs passed via environment variables

### 2. Command Execution Safety

- User prompts passed as single arguments (prevents word splitting)
- Array-based command execution in `spawn_agent()` and `run_agent_sync()`
- `set -f` disables glob expansion in subshells
- No use of `eval` with user-provided data in production code

### 3. Secrets Management

- API keys read from environment variables only
- Keys masked in verbose output with `***`
- No keys written to log files or results
- Regex validation for key formats

### 4. CI/CD Hardening (v4.6.0)

- Workflow inputs via `env:` blocks (not direct interpolation)
- Command allowlisting for `workflow_dispatch`
- File list sanitization with `tr -cd`
- Injection pattern detection for issue comments

## Supported Versions

| Version | Supported |
|---------|-----------|
| 4.6.x   | Yes - Full security updates |
| 4.5.x   | Yes - Critical patches only |
| 4.0-4.4 | Security patches only |
| < 4.0   | No |

## Reporting Vulnerabilities

**Please DO NOT create public GitHub issues for security vulnerabilities.**

To report a vulnerability:

1. Email: Create a private issue via GitHub Security Advisories
2. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### Response Timeline

| Stage | Timeline |
|-------|----------|
| Initial acknowledgment | 24-48 hours |
| Severity assessment | 5 business days |
| Fix development | Based on severity |
| Public disclosure | After fix released |

## Security Checklist for Contributors

Before submitting PRs, verify:

- [ ] No `eval` with user input
- [ ] No unquoted variable expansion in commands
- [ ] API keys not logged or echoed
- [ ] File paths validated before use
- [ ] JSON parsing has error handling
- [ ] Agent types validated against allowlist
- [ ] CI workflow inputs use environment variables

## Security Features by Version

### v4.6.0 (Claude Code v2.1.9 Integration)

- Path traversal protection via `validate_workspace_path()`
- Array-based command execution (replaces word-splitting)
- JSON field extraction with validation
- CI workflow input hardening
- Session ID tracking for audit trails

### v4.5.0

- Smart setup wizard with validation
- Resource-aware configuration
- Improved error handling

### v4.4.0

- Human-in-the-loop review system
- CI/CD integration with audit logging

## Audit Logging

Claude Octopus logs security-relevant events to `~/.claude-octopus/audit.log`:

```json
{
  "timestamp": "2026-01-15T14:30:00Z",
  "action": "quality_gate_override",
  "phase": "tangle",
  "decision": "proceed",
  "reason": "Manual review approved",
  "reviewer": "user",
  "session_id": "claude-abc123"
}
```

## Dependencies

Claude Octopus depends on:
- **Codex CLI** (`@openai/codex-cli`)
- **Gemini CLI** (`@anthropic-ai/gemini-cli`)
- **jq** (JSON processing)

Keep these dependencies updated to receive security patches.
