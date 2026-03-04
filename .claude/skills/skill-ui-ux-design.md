---
name: octopus-ui-ux-design
aliases:
  - ui-ux-design
  - design
  - ui-design
  - ux-design
description: "Design UI/UX with style guides, palettes, and component specs"
context: fork
agent: Explore
task_management: true
execution_mode: enforced
pre_execution_contract:
  - interactive_questions_answered
  - visual_indicators_displayed
  - design_intelligence_checked
validation_gates:
  - search_py_executed
  - design_spec_produced
invocation: human_only
trigger: |
  Use this skill when the user wants to "design a UI", "create a design system",
  "pick a color palette", "choose fonts for", "design a dashboard", "create component specs",
  "style guide for", or "UI/UX for my app".

  Execution: BM25 search via search.py + Claude synthesis with ui-ux-designer persona
---

## EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

<HARD-GATE>
**CRITICAL: You MUST call the BM25 search engine (search.py) via Bash tool before producing
any design recommendations. Do NOT rely solely on your own design knowledge. The search engine
provides curated, data-driven design intelligence. If you produce a design system without
at least 3 search.py calls, you have violated this contract.**
</HARD-GATE>

This skill uses **ENFORCED execution mode**. You MUST follow this exact sequence.

### STEP 1: Interactive Questions (BLOCKING)

**You MUST call AskUserQuestion before any other action.**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What type of product are you designing for?",
      header: "Product Type",
      multiSelect: false,
      options: [
        {label: "SaaS/Dashboard", description: "Analytics, admin panels, B2B tools"},
        {label: "E-commerce", description: "Shopping, marketplace, product pages"},
        {label: "Landing page", description: "Marketing, conversion, product launch"},
        {label: "Mobile app", description: "iOS/Android native or responsive"}
      ]
    },
    {
      question: "What tech stack are you using?",
      header: "Stack",
      multiSelect: false,
      options: [
        {label: "React + Tailwind (Recommended)", description: "React/Next.js with Tailwind CSS"},
        {label: "React + shadcn/ui", description: "React with shadcn component library"},
        {label: "HTML + Tailwind", description: "Static or server-rendered HTML"},
        {label: "Vue/Nuxt", description: "Vue.js or Nuxt framework"}
      ]
    },
    {
      question: "What design deliverables do you need?",
      header: "Deliverables",
      multiSelect: true,
      options: [
        {label: "Design tokens", description: "Colors, spacing, typography as CSS/Tailwind config"},
        {label: "Component specs", description: "Component anatomy, states, props"},
        {label: "Page layouts", description: "Wireframe-level layout specifications"},
        {label: "Style guide", description: "Visual style direction with rationale"}
      ]
    }
  ]
})
```

### STEP 2: Display Banner

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - UI/UX Design Mode
🎨 Design: [Brief description from user prompt]

Pipeline:
🔍 Phase 1: Design Research (BM25 search + context detection)
🎯 Phase 2: Design Direction (synthesis + style selection)
🛠️ Phase 3: Design System (tokens, components, layouts)
✅ Phase 4: Validation (accessibility, handoff specs)

Tools:
🔍 BM25 Design Intelligence: [checking...]
🎨 Figma MCP: [Available / Not configured]
🧩 shadcn MCP: [Available / Not configured]
🔵 Claude (ui-ux-designer): Available
```

### STEP 3: Check Design Intelligence

```bash
SEARCH_PY="${CLAUDE_PLUGIN_ROOT}/vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py"
if [ -f "$SEARCH_PY" ]; then
    python3 -c "import csv, re, math" 2>/dev/null && echo "READY" || echo "MISSING_PYTHON"
else
    echo "MISSING_SEARCH_PY"
fi
```

**If MISSING_SEARCH_PY**: Tell user to run `cd "${CLAUDE_PLUGIN_ROOT}" && git submodule update --init vendors/ui-ux-pro-max-skill`
**If MISSING_PYTHON**: Tell user python3 is required for design intelligence.

### STEP 4: Phase 1 — Discover (Design Research)

**You MUST execute at least 3 of these searches. This is NOT optional.**

```bash
SEARCH_PY="${CLAUDE_PLUGIN_ROOT}/vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py"

# 1. Product type search — what design patterns fit this product?
python3 "$SEARCH_PY" "<user's product description>" --domain product

# 2. Style search — what visual styles match?
python3 "$SEARCH_PY" "<user's aesthetic or product type>" --domain style

# 3. Color palette search — data-driven palette selection
python3 "$SEARCH_PY" "<user's product type or mood>" --domain color

# 4. Typography search — font pairings
python3 "$SEARCH_PY" "<user's product type>" --domain typography

# 5. UX guidelines search — relevant best practices
python3 "$SEARCH_PY" "<key user flow>" --domain ux

# 6. Stack-specific search (if user specified a stack)
python3 "$SEARCH_PY" "<user's requirements>" --stack <stack>
```

**If user provided a Figma URL**, also pull design context:
- Use `get_design_context` from Figma MCP to pull existing designs
- Use `get_screenshot` for visual reference

**Collect all search results before proceeding to Phase 2.**

### STEP 5: Phase 2 — Define (Design Direction)

Synthesize search results into a design direction document:

1. **Style recommendation** — which visual style best fits the product (cite search results)
2. **Color palette** — selected palette with hex values and contrast ratios
3. **Typography** — heading + body font pairing with Google Fonts import
4. **Layout approach** — grid system, spacing scale, responsive strategy
5. **Design principles** — 3-5 guiding principles derived from UX search results

If Codex/Gemini are available via orchestrate.sh, run a quick debate on the design direction:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" grapple "Which design direction is better for <product>: <option A> vs <option B>" --rounds 1
```

### STEP 6: Phase 3 — Develop (Design System)

Generate the design system based on user's requested deliverables:

**Design Tokens** (if requested):
- CSS custom properties or Tailwind config
- Color scales (50-950)
- Spacing scale (4px base)
- Typography scale with line heights
- Shadow, border-radius, and transition tokens

**Component Specs** (if requested):
- Component anatomy diagrams (ASCII)
- Props/variants table
- State variants (default, hover, active, disabled, error, loading)
- Accessibility requirements (ARIA, keyboard, focus)

**Page Layouts** (if requested):
- Grid-based layout with responsive breakpoints
- Content hierarchy and visual flow
- Above-the-fold content strategy
- Navigation and interaction patterns

**Style Guide** (if requested):
- Visual style rationale with evidence from search results
- Do's and don'ts with examples
- Icon and illustration guidelines
- Motion and animation principles

If shadcn MCP is available, search for matching components:
```javascript
// Search shadcn registries for components matching the design system
mcp__shadcn__search_items_in_registries({ query: "<component name>" })
```

### STEP 7: Phase 4 — Deliver (Validation)

1. **Accessibility audit** — validate all colors against WCAG AA (4.5:1 for text, 3:1 for large text)
2. **Completeness check** — verify all requested deliverables are present
3. **Implementation readiness** — confirm specs are detailed enough for frontend-developer
4. **Figma push-back** (if connected) — offer to push design tokens to Figma

### STEP 8: Present Results

Format the final design system as a structured document with:
- Executive summary (style direction + rationale)
- Design tokens (copy-paste ready)
- Component inventory
- Page layouts
- Implementation notes for the development team
- Sources (which search results informed each decision)

**Offer next steps:**
- "Want me to implement these specs?" → hand off to frontend-developer persona
- "Want to refine the palette?" → re-run color search with adjusted query
- "Want a full embrace workflow?" → transition to `/octo:embrace`
