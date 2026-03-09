---
command: design-ui-ux
description: "Design UI/UX systems with style guides, palettes, typography, and component specs"
aliases:
  - design
  - ui-design
  - ux-design
---

# /octo:design-ui-ux - UI/UX Design Workflow

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:design-ui-ux <arguments>`):

### Step 1: Detect Mode

Parse the user's intent to determine which mode to run:

| Intent | Mode | What Happens |
|--------|------|-------------|
| "design a dashboard" | Full design system | 4-phase workflow via skill |
| "pick colors for X" | Quick search | Single BM25 query, immediate results |
| "review this Figma" | Design review | Pull Figma context, create specs |
| "create component specs" | Component spec | Focused spec generation |

**For full design system requests**, invoke the skill `skill-ui-ux-design.md` which runs the 4-phase Double Diamond workflow.

**For quick searches**, run the search directly:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py" "<query>" --domain <domain>
```

### Step 2: Check Design Intelligence Availability

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py" ]; then
    python3 -c "import csv, re, math" 2>/dev/null && echo "Design intelligence: ready" || echo "Design intelligence: python3 required"
else
    echo "Design intelligence: not installed (run: git submodule update --init)"
fi
```

If unavailable, fall back to Claude's built-in design knowledge with a note to the user.

### Step 3: Display Banner

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - UI/UX Design Mode
🎨 Design: [Brief description of what's being designed]

Tools:
🔍 BM25 Design Intelligence - Style, palette, typography, UX databases
🔵 Claude (ui-ux-designer) - Design synthesis and specification
🎨 Figma MCP - [Available ✓ / Not configured]
🧩 shadcn MCP - [Available ✓ / Not configured]
```

### Step 4: Execute

**Quick mode**: Run search, present results, offer to expand into full design system.

**Full mode**: Execute the design workflow:
1. Discover - Search BM25 databases, detect project context, pull Figma if available
2. Define - Synthesize search results into design direction (style, palette, typography, layout)
3. Critique - Adversarial review of the design direction via Codex/Gemini (or Claude self-critique). Catches accessibility failures, impractical choices, and research blind spots before they become tokens
4. Develop - Generate design tokens, component specs, page layouts (incorporating critique fixes)
5. Deliver - Validate accessibility, create handoff specs, push to Figma if connected

### Step 5: Present Results

Format output as a structured design spec:
- Design tokens (CSS custom properties or Tailwind config)
- Component inventory with state variants
- Page layouts with responsive breakpoints
- Font imports and usage guidelines
- Color palette with contrast ratios

## Usage Examples

```
/octo:design-ui-ux SaaS analytics dashboard
/octo:design health tech mobile app
/octo:ui-design e-commerce checkout flow
/octo:ux-design landing page for developer API
```

## Quick Search Domains

| Domain | What You Get |
|--------|-------------|
| style | UI style recommendations (glassmorphism, minimalism, etc.) |
| color | Color palettes by product type |
| typography | Font pairings with Google Fonts |
| ux | UX best practices and anti-patterns |
| landing | Landing page structure and CTA strategies |
| chart | Data visualization recommendations |
| product | Product type design patterns |

## Related Commands

- `/octo:extract` - Reverse-engineer design systems from existing codebases
- `/octo:review` - Code review including frontend quality
- `/octo:embrace` - Full lifecycle when design leads to implementation
