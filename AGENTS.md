# Claude Octopus Agents

This file describes the autonomous agents available in this repository for
AI coding tools that support agent discovery (e.g., GitHub Copilot coding agent).

## Available Agents

| Agent | Description | Tools |
|-------|-------------|-------|
| `backend-architect` | Scalable API design, microservices, distributed systems | Read-only |
| `code-reviewer` | Code quality, security vulnerabilities, production reliability | Read-only |
| `debugger` | Errors, test failures, unexpected behavior | All |
| `docs-architect` | Technical documentation from codebases | Read + execute |
| `frontend-developer` | React components, responsive layouts, client-side state | All |
| `performance-engineer` | Optimization, observability, scalable performance | Read-only |
| `security-auditor` | DevSecOps, OWASP compliance, vulnerability assessment | Read-only |
| `tdd-orchestrator` | Red-green-refactor discipline, test-driven development | All |
| `database-architect` | Data modeling, schema design, migration planning | Read-only |
| `cloud-architect` | AWS/Azure/GCP infrastructure, IaC, FinOps | Read + execute |

## Agent Definitions

Agents are defined in two formats for cross-platform compatibility:

- **Claude Code**: `.claude/agents/*.md` — YAML frontmatter with Claude Code tool names
- **GitHub Copilot**: `.github/agents/*.agent.md` — YAML frontmatter with Copilot tool aliases

Both formats describe the same 10 agents with platform-native tool mappings:

| Claude Code Tool | Copilot Alias |
|-----------------|---------------|
| Read | read |
| Write, Edit | edit |
| Bash | execute |
| Grep, Glob | search |

## MCP Integration

The MCP server (`mcp-server/`) exposes Claude Octopus workflows as MCP tools.
For MCP-aware coding agents, connect to the MCP server rather than invoking
agents directly.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:

   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```

5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
