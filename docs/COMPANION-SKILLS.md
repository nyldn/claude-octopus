# Recommended Companion Skills

Claude Octopus focuses on multi-AI orchestration. These official Claude Code skills extend its capabilities for specific domains.

## For Testing & Validation 🧪

**`webapp-testing`** - Automated UI testing with Playwright
- Complements Claude Octopus's `ink` (deliver) phase
- Test web apps automatically after development
- Install: `/plugin install webapp-testing`

## For Customization & Extension 🛠️

**`skill-creator`** - Build custom orchestration patterns
- Create domain-specific workflows for your team
- Make repeatable task templates
- Install: `/plugin install skill-creator`

## For Integration 🔌

**`mcp-builder`** - Connect to external APIs via MCP servers
- Extend multi-provider capabilities
- Build custom integrations with your services
- Install: `/plugin install mcp-builder`

## For Design & Frontend 🎨

**`frontend-design`** - Bold, opinionated design decisions
- Avoid generic aesthetics in React/Tailwind projects
- Install: `/plugin install frontend-design`

**`artifacts-builder`** - React component building with shadcn/ui
- Build polished UI components
- Install: `/plugin install artifacts-builder`

**`shadcn`** (via MCP) - shadcn/ui component library
- Browse and install shadcn components
- See: [shadcn MCP server docs](https://github.com/modelcontextprotocol/servers/tree/main/src/shadcn)

## All Available Official Skills

### Document Processing 📄
- `docx` - Word document creation/editing
- `pdf` - PDF manipulation and extraction
- `pptx` - PowerPoint presentations
- `xlsx` - Excel spreadsheets with formulas

### Creative & Visual 🎨
- `algorithmic-art` - Generative art with p5.js
- `canvas-design` - Visual design in PNG/PDF
- `slack-gif-creator` - Animated GIFs for Slack

### Communication 💬
- `brand-guidelines` - Apply brand colors/typography
- `internal-comms` - Status reports and newsletters

**Install any skill:** `/plugin install <skill-name>`

**Browse all skills:** [Awesome Claude Skills](https://github.com/travisvn/awesome-claude-skills)

## How Skills Work with Claude Octopus

**Important:** Installed skills are available to **Claude (the orchestrator)**, not to the individual agents (Codex/Gemini CLIs) spawned by Claude Octopus.

**Typical workflow:**
```
1. User requests a task
   ↓
2. Claude (has all skills) uses Claude Octopus for multi-AI orchestration
   ↓
3. Octopus spawns Codex/Gemini agents (separate CLIs without skills)
   ↓
4. Agents return parallel results
   ↓
5. Claude (with skills) validates, tests, and polishes results
```

**Example:**
- **Before orchestration:** Claude might use `frontend-design` to establish design principles
- **During orchestration:** Agents generate code following those principles
- **After orchestration:** Claude uses `webapp-testing` to validate the result

This separation keeps agents focused on their core tasks while Claude coordinates and applies domain-specific skills.

---

[← Back to README](../README.md)
