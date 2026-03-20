# OpenCLI Provider Configuration

This file contains OpenCLI-specific instructions for Claude Octopus workflows.

## Provider Information

- **Provider**: OpenCLI (Universal CLI Hub)
- **Emoji**: 🌐
- **API Key**: None required (uses Chrome browser session)
- **CLI Command**: `opencli`

## Usage Patterns

### Invoking OpenCLI

```bash
# List all available commands
opencli list

# Web data retrieval
opencli twitter trending
opencli reddit hot
opencli hackernews hot
opencli bilibili hot

# Search across platforms
opencli twitter search "your query"
opencli reddit search "your query"
opencli youtube search "your query"

# Desktop App control
opencli cursor status
opencli antigravity status

# External CLI passthrough
opencli gh pr list --limit 5
opencli docker ps
```

### OpenCLI Strengths

OpenCLI excels at:
1. **Real-time Web Data** - Live data from Twitter, Reddit, HN, YouTube, etc.
2. **Browser Session Reuse** - Uses Chrome's logged-in state, account-safe
3. **Desktop App Control** - CLI-ify Electron apps (Cursor, Antigravity, etc.)
4. **External CLI Hub** - Unified discovery of local CLI tools
5. **AI Agent Discovery** - `opencli list` for automatic tool discovery

### When to Use OpenCLI

Use OpenCLI for:
- Gathering real-time data from social platforms during research
- Accessing website content using existing browser sessions
- Controlling desktop applications programmatically
- Discovering and invoking external CLI tools
- Downloading media from supported platforms

### Cost Considerations

- OpenCLI is **free** — no API keys or subscriptions required
- Uses your existing Chrome browser session
- No rate limits beyond the target platform's own limits
- Estimated cost: $0.00 per query

## Security

- Reuses Chrome's logged-in state; credentials never leave the browser
- No API keys stored or transmitted
- Browser Bridge extension communicates locally only
- All data stays on your machine

## Timeout Configuration

Default timeout: 30 seconds
Can be configured:
```bash
OPENCLI_TIMEOUT=60  # 1 minute for slow page loads
```

## Error Handling

Common errors:
- `Extension not connected`: Install Browser Bridge extension in Chrome
- `Unauthorized/Empty data`: Login session expired, re-login in Chrome
- `Timeout`: Page took too long to load, retry or increase timeout

## Integration with Workflows

OpenCLI is used in:
- **Discover Phase**: Real-time social/web data gathering for research
- **Define Phase**: Competitive analysis via platform search
- **Develop Phase**: Code snippet extraction from AI chat apps
- **Deliver Phase**: Content publishing to social platforms

## Prerequisites

- Node.js >= 20.0.0
- Chrome running with Browser Bridge extension installed
- `npm install -g opencli`
