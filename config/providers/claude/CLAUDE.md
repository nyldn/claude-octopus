# Claude Provider Configuration

This file contains Claude-specific instructions for Claude Octopus workflows.

## Provider Information

- **Provider**: Claude (Anthropic)
- **Emoji**: 🔵
- **Access**: Included with Claude Code subscription
- **API**: Native integration via Claude Code

## Role in Workflows

Claude serves as the **orchestrator and synthesizer** in Claude Octopus workflows:

1. **Orchestration** - Coordinates multi-provider workflows
2. **Synthesis** - Combines insights from Codex and Gemini
3. **Strategic Analysis** - Provides high-level recommendations
4. **Quality Control** - Validates outputs from other providers
5. **User Interface** - Communicates results to users

## Strengths

Claude excels at:
1. **Strategic Synthesis** - Combining multiple perspectives
2. **Nuanced Analysis** - Understanding trade-offs and context
3. **Clear Communication** - Explaining complex topics simply
4. **Code Understanding** - Deep comprehension of codebases
5. **Ethical Considerations** - Security, privacy, safety analysis

## When to Use Claude

Claude is used in ALL workflow phases:
- **Discover**: Synthesize research from Codex + Gemini
- **Define**: Build consensus and clarify requirements
- **Develop**: Strategic implementation guidance
- **Deliver**: Final validation and quality certification

## Integration with Other Providers

Claude works alongside:
- **🔴 Codex**: Technical implementation details
- **🟡 Gemini**: Ecosystem and alternatives research

Claude's role is to:
- Coordinate provider invocations
- Aggregate and synthesize results
- Provide strategic recommendations
- Ensure quality and consistency

## No Additional Cost

- Claude usage is included with Claude Code
- No external API keys required
- No per-query costs
- Unlimited usage within Claude Code limits

## Model Selection: Opus 4.6 vs Sonnet 4.6

Claude Octopus supports two Claude model tiers via the `claude` and `claude-opus` agent types:

- **Claude Sonnet 4.6** (`claude`, `claude-sonnet`) - Default for most tasks. Balanced performance and cost. Pricing: $3/$15 per MTok input/output.
- **Claude Opus 4.6** (`claude-opus`) - Premium tier for strategic synthesis, complex architecture decisions, and research aggregation. Pricing: $5/$25 per MTok input/output.

### When to Route to Opus 4.6

Use `claude-opus` for:
- Strategic synthesis across multiple provider outputs
- Complex architectural decision-making
- Research synthesis requiring deep reasoning
- Premium quality gates and validation

Use `claude` (Sonnet 4.6) for:
- Standard orchestration and coordination
- Routine synthesis and aggregation
- Cost-sensitive workflows

### Agent Teams (v2.1.32+)

When Claude Code v2.1.32+ is detected, Agent Teams support is available. This enables peer-to-peer agent messaging for coordinated multi-agent workflows. Detection is automatic via `SUPPORTS_AGENT_TEAMS` flag in orchestrate.sh.

## Native Features

Claude has access to:
- File system operations (Read, Write, Edit)
- Command execution (Bash)
- Task management (TaskCreate, TaskUpdate)
- Web search and fetch
- MCP tools and resources
- Background agents
