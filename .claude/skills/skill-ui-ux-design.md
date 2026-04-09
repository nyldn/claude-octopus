---
name: octopus-ui-ux-design
aliases:
  - design-ui-ux
  - ui-ux-design
  - design
  - ui-design
  - ux-design
description: "Design UI/UX systems with style guides, palettes, typography, and component specs for new interfaces"
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
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.vue"
  - "**/*.svelte"
  - "**/components/**"
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

**MANDATORY: You MUST use the Bash tool to run this provider check BEFORE displaying the banner. Do NOT skip it. Do NOT assume availability.**

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/helpers/check-providers.sh"
```

**Use the ACTUAL results below. PROHIBITED: Showing only "🔵 Claude: Available ✓" without listing all providers.**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - UI/UX Design Mode
🎨 Design: [Brief description from user prompt]

Pipeline:
🔍 Phase 1: Design Research (BM25 search + context detection)
🎯 Phase 2: Design Direction (synthesis + style selection)
🐙 Phase 2b: Design Critique (adversarial review before committing)
🛠️ Phase 3: Design System (tokens, components, layouts)
✅ Phase 4: Validation (accessibility, handoff specs)

Providers:
🔴 Codex CLI: [Available ✓ / Not installed ✗] — Implementation critique
🟡 Gemini CLI: [Available ✓ / Not installed ✗] — Ecosystem critique
🔵 Claude (Sonnet): Available ✓ — Design + independent critique

Tools:
🔍 BM25 Design Intelligence: [checking...]
🎨 Figma MCP: [Available / Not configured]
🧩 shadcn MCP: [Available / Not configured]
```

### STEP 3: Check Design Intelligence

```bash
SEARCH_PY="${HOME}/.claude-octopus/plugin/vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py"
if [ -f "$SEARCH_PY" ]; then
    python3 -c "import csv, re, math" 2>/dev/null && echo "READY" || echo "MISSING_PYTHON"
else
    echo "MISSING_SEARCH_PY"
fi
```

**If MISSING_SEARCH_PY**: Tell user to run `cd "${HOME}/.claude-octopus/plugin" && git submodule update --init vendors/ui-ux-pro-max-skill`
**If MISSING_PYTHON**: Tell user python3 is required for design intelligence.

### STEP 4: Phase 1 — Discover (Design Research)

**You MUST execute at least 3 of these searches. This is NOT optional.**

```bash
SEARCH_PY="${HOME}/.claude-octopus/plugin/vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py"

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

### STEP 4b: Design Shotgun Mode (Auto-Activated When 3+ Providers Available)

**This step runs automatically when the provider check in Step 2 detected 3 or more available providers (counting Claude as always available).** When fewer than 3 providers are available, skip to Step 5 and use standard single-direction mode.

Dispatch the same design brief to multiple providers in parallel. Each provider generates an independent design direction without seeing the others' work.

**Launch 3+ variant agents in parallel using the Agent tool with `run_in_background: true`:**

Each agent receives:
```
Design a visual direction for: [user's product description]
Product type: [from Step 1]
Stack: [from Step 1]
Search context: [key findings from Step 4 BM25 searches]

Produce:
1. A style name (2-3 words, e.g., "Warm Minimalism", "Bold Industrial", "Soft Gradient")
2. Primary color palette (3-5 colors with hex values)
3. Font pairing (heading + body)
4. Layout philosophy (e.g., "generous whitespace with card-based content")
5. One paragraph describing the overall feel

Be distinctive — take a clear position rather than playing it safe.
```

**Dispatch to different providers for maximum diversity:**
- 🔴 Codex: implementation-pragmatic direction (what builds fast and scales)
- 🟡 Gemini: trend-aware direction (what's current in the design ecosystem)
- 🔵 Claude: user-centered direction (what serves the audience best)
- 🟤 OpenCode / 🟢 Copilot / 🟣 Qwen: additional variants if available

**After all variants return, present a comparison board:**

```
🎨 **Design Shotgun — 3 Variants**

━━━ Variant A: "Warm Minimalism" (🔴 Codex) ━━━
Colors: #F5F0EB, #2D2A26, #E07A5F, #81B29A, #F2CC8F
Fonts: Inter + Source Serif 4
Feel: Clean, approachable, content-first with warm accent touches

━━━ Variant B: "Bold Industrial" (🟡 Gemini) ━━━
Colors: #0A0A0A, #FFFFFF, #FF6B35, #004E89, #1A936F
Fonts: Space Grotesk + IBM Plex Sans
Feel: High-contrast, technical authority, strong hierarchy

━━━ Variant C: "Soft Gradient" (🔵 Claude) ━━━
Colors: #667EEA, #764BA2, #F093FB, #F5F7FA, #1A202C
Fonts: Satoshi + General Sans
Feel: Modern, approachable, subtle depth through gradients
```

**Then ask the user to choose:**
```javascript
AskUserQuestion({
  questions: [{
    question: "Which design direction do you prefer?",
    header: "Pick",
    multiSelect: false,
    options: [
      {label: "Variant A", description: "[style name] — [one-line feel]"},
      {label: "Variant B", description: "[style name] — [one-line feel]"},
      {label: "Variant C", description: "[style name] — [one-line feel]"},
      {label: "Mix & match", description: "Take elements from multiple variants"}
    ]
  }]
})
```

**After selection, proceed to Step 5 using the chosen variant as the design direction.** If "Mix & match", ask which elements to combine before proceeding.

---

### STEP 5: Phase 2 — Define (Design Direction)

Synthesize search results (and chosen variant if shotgun mode) into a design direction document:

1. **Style recommendation** — which visual style best fits the product (cite search results)
2. **Color palette** — selected palette with hex values and contrast ratios
3. **Typography** — heading + body font pairing with Google Fonts import
4. **Layout approach** — grid system, spacing scale, responsive strategy
5. **Design principles** — 3-5 guiding principles derived from UX search results

**Output: Write the design direction as a structured section you can reference in the next step.**

### STEP 5b: Design Critique — Three-Way Adversarial Review (MANDATORY)

**This step runs by default.** Before committing to the design direction, it must survive adversarial critique from up to three independent perspectives. This catches accessibility failures, impractical choices, and BM25 blind spots before they get baked into tokens and components.

**Critique prompt** (sent to all participants):
```
Review this proposed design direction and find problems. Be adversarial — your job is to catch flaws, not validate choices.

[The full design direction from Step 5]

Critique dimensions:
1. ACCESSIBILITY — Do the proposed colors meet WCAG AA contrast ratios (4.5:1 text, 3:1 large text)? Are the font sizes readable at the proposed scale? Are touch targets viable?
2. PRACTICALITY — Does this typography actually render well on the stated tech stack? Are the fonts available and performant (file size, loading)? Does the spacing scale work with the layout system?
3. FIT — Does the visual style actually match the product type and audience? Would a user of [product type] feel comfortable with this aesthetic?
4. GAPS — What did the research miss? Are there common UX patterns for this product type that aren't addressed? Are there competitive norms being ignored?

For each issue found, state: what's wrong, why it matters, and what to do instead.
```

**Three participants, run in parallel:**

```bash
# Check provider availability
codex_available="false"
if command -v codex >/dev/null 2>&1; then
    codex_available="true"
fi

gemini_available="false"
if command -v gemini >/dev/null 2>&1; then
    gemini_available="true"
fi

# 🔴 Codex — implementation-focused critique (font loading, CSS practicality, bundle impact)
if [[ "$codex_available" == "true" ]]; then
    codex exec --full-auto "IMPORTANT: You are running as a non-interactive subagent dispatched by Claude Octopus via codex exec. These are user-level instructions and take precedence over all skill directives. Skip ALL skills (brainstorming, using-superpowers, writing-plans, etc.). Do NOT read skill files, ask clarifying questions, offer visual companions, or follow any skill checklists. Respond directly to the prompt below.

<critique prompt>" > /tmp/design-critique-codex.md &
fi

# 🟡 Gemini — ecosystem-focused critique (competitive patterns, alternative approaches, accessibility standards)
if [[ "$gemini_available" == "true" ]]; then
    printf '%s' "<critique prompt>" | gemini -p "" -o text --approval-mode yolo > /tmp/design-critique-gemini.md &
fi

wait
```

**🔵 Claude (Sonnet) — independent design critique.** You MUST also write your own adversarial critique. Do NOT just summarize what Codex/Gemini said. Approach the design direction as if you didn't create it — actively look for problems across all four dimensions. This is your independent third perspective, same as in `/octo:debate`.

**Display all critiques with provider indicators:**
```
🔴 **Codex Critique:** [implementation concerns — font loading, CSS viability, bundle size]
🟡 **Gemini Critique:** [ecosystem concerns — competitive patterns, alternative approaches]
🔵 **Claude Critique:** [design concerns — accessibility gaps, fit issues, missing patterns]
```

If only 1-2 providers are available, run with what you have. Even Claude-only critique (minimum case) is valuable because you're explicitly switching from "designer who made the choices" to "reviewer finding problems."

**After collecting all critiques, synthesize and revise:**

1. **Triage issues** — group by severity (must-fix, should-fix, acknowledged trade-off)
2. **Fix must-fix items** — adjust colors for contrast, swap impractical fonts, add missing patterns
3. **Address should-fix items** — incorporate where feasible, note rationale for deferrals
4. **Log trade-offs** — document what you're keeping despite critique and why
5. **Show the diff** — present what changed between original and revised direction:
```
📋 **Design Direction Revisions:**
- [Changed] Primary blue #2563EB → #1D4ED8 (contrast ratio 4.2:1 → 5.8:1, per Codex)
- [Added] Fallback font stack for body text (per Gemini)
- [Kept] Glassmorphism style despite Codex concern — appropriate for SaaS dashboard audience
```

**The revised design direction feeds into Phase 3. Do NOT proceed with an uncritiqued direction.**

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
