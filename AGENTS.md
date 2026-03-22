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
