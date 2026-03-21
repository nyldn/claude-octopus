# GitHub Copilot Provider Configuration

This file contains GitHub Copilot-specific instructions for Claude Octopus workflows.

## Provider Information

- **Provider**: GitHub Copilot (via GitHub API)
- **Emoji**: 🟢
- **Auth**: GitHub OAuth via `gh auth login` + Copilot subscription
- **API Endpoint**: `https://api.githubcopilot.com/chat/completions`
- **Token Exchange**: `https://api.github.com/copilot_internal/v2/token`
- **Agent Types**: `copilot`, `copilot-code`, `copilot-research`, `copilot-fast`

## Role-Based Model Selection

GitHub Copilot is a **multi-model gateway**. Available models are controlled by your
organization policy — models cannot be hardcoded. Claude Octopus uses role-based
dynamic selection with automatic fallback:

| Agent Type       | Role        | Preferred Models (in order)                    |
|------------------|-------------|------------------------------------------------|
| `copilot-code`   | Code/Impl   | gpt-4.1 → claude-3.7-sonnet → gemini-2.0-flash |
| `copilot-research`| Research   | claude-3.7-sonnet → gpt-4.1 → gemini-2.0-flash |
| `copilot-fast`   | Fast/Budget | o3-mini → gpt-4.1 → gpt-4o-mini               |
| `copilot`        | Auto        | gpt-4.1 → claude-3.7-sonnet → gemini-2.0-flash |

If a model is restricted by org policy (HTTP 400/403/404), Octopus automatically
tries the next preference. This ensures compatibility across individual, team,
and enterprise Copilot subscriptions.

## Usage Patterns

### Invoking Copilot

```bash
# Spawn a code-focused Copilot agent
spawn_agent "copilot-code" "Implement X following the existing patterns..."

# Research via Copilot (Claude-preferred for understanding/planning)
spawn_agent "copilot-research" "Research the best approach for..."

# Fast/budget Copilot for quick tasks
spawn_agent "copilot-fast" "Explain this error briefly..."

# Auto-select model based on task
spawn_agent "copilot" "Review and suggest improvements for..."
```

### Probe Discover Integration

Copilot is automatically added to `probe_discover()` when available, providing
an implementation-focused perspective alongside Codex's technical analysis
and Gemini's ecosystem research.

## Authentication Setup

### Method 1: gh CLI + Extension (Recommended)

```bash
# Install gh CLI
# macOS: brew install gh
# Ubuntu: sudo apt install gh

# Authenticate
gh auth login

# Install Copilot extension
gh extension install github/gh-copilot

# Verify
gh copilot --help
```

### Method 2: Token-Based Access

```bash
# Set GitHub token with Copilot scope
export GH_TOKEN="your-github-pat-with-copilot-scope"
# or
export GITHUB_TOKEN="your-github-pat-with-copilot-scope"
```

## Copilot Strengths

GitHub Copilot excels at:
1. **Code Implementation** — Practical, production-ready code patterns
2. **GitHub Ecosystem** — Deep integration with GitHub-native workflows
3. **Multi-Model Access** — GPT, Claude, and Gemini via single subscription
4. **Developer Workflow** — Optimized for developer-centric tasks
5. **Codebase Context** — Understanding existing code conventions

### When to Use Copilot

Use Copilot for:
- Implementation tasks where you want GitHub-optimized AI
- Research when you have a Copilot subscription but not other API keys
- Code review with role-based model selection
- Teams with GitHub Copilot enterprise subscriptions

## Cost Considerations

- **Cost model**: Bundled with GitHub Copilot subscription
  - Individual: $10/month
  - Business: $19/user/month
  - Enterprise: $39/user/month
- **Premium requests**: Some models (claude, o1) count as "premium" with quotas
- **No per-token billing**: Unlike Codex/Gemini/Perplexity, all calls included
- Claude Octopus marks Copilot as `bundled` cost tier (not `pay-per-use`)

## Organization Policy Constraints

Enterprise organizations can restrict which models are available to Copilot users.
Claude Octopus handles this transparently:

1. Tries preferred model for the task role
2. If model is restricted (HTTP 400/403/404), automatically tries next in list
3. Falls back through all preferences before failing
4. Logs a warning if all preferences are exhausted

**No configuration needed** — org restrictions are handled automatically at runtime.

## Token Caching

Copilot tokens are cached in `${TMPDIR}/.octo-copilot-token-<user>` for 90 minutes
(Copilot tokens expire after ~3 hours). The cache file has 600 permissions (owner-only).
The cache is invalidated automatically on 401 responses.

## Security

- GitHub OAuth token obtained via `gh auth token` (uses keyring when available)
- Copilot token exchanged securely, stored in temp file with 600 permissions
- Env isolation via `build_provider_env()`: only passes `GH_TOKEN`/`GITHUB_TOKEN`
- Output wrapped in trust markers (same as Codex/Gemini/Perplexity)
- Never logs or exposes token values in output

## Timeout Configuration

Default timeout: 90 seconds (Copilot can be slower than direct APIs)
Can be adjusted via `--max-time` in `copilot_execute()`.

## Error Handling

| HTTP Code | Meaning | Octopus Action |
|-----------|---------|----------------|
| 200 | Success | Extract content and return |
| 400/403/404 | Model restricted by org | Try next model preference |
| 401 | Token expired | Invalidate cache, return error |
| 429 | Rate limited / quota exceeded | Return error with warning |
| Other | API error | Log and try next model |

## Integration with Workflows

Copilot is used in:
- **Discover Phase**: Auto-injected as implementation perspective when available
- **Develop Phase**: Can be explicitly requested for code generation
- **Review Phase**: `copilot-research` for understanding, `copilot-code` for review
- **Any Phase**: User can specify `copilot` agent type directly
