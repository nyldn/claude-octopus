---
name: octopus-ui-ux-design
description: "Design UI/UX systems with style guides, palettes, typography, and component specs for new interfaces"
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


## EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

<HARD-GATE>
**CRITICAL: You MUST call the BM25 search engine (search.py) via native shell command tool before producing
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
    },
    {
      question: "How adventurous should the design be?",
      header: "Dials",
      multiSelect: false,
      options: [
        {label: "Conservative (v3 m2 d4)", description: "Familiar patterns, minimal motion — enterprise, gov, finance"},
        {label: "Balanced (v5 m4 d5)", description: "Contemporary but safe — most SaaS and product work"},
        {label: "Expressive (v7 m6 d5)", description: "Distinctive direction, noticeable motion — marketing, launch pages"},
        {label: "Maximal (v9 m8 d6)", description: "Take real aesthetic risks — portfolios, creative brands"}
      ]
    }
  ]
})
```

The dial answer maps to `--variance/--motion/--density` values (v/m/d above) passed to
every `search.py` call and stated in the design direction. Infer instead of asking only
when the user's brief already names a vibe ("brutalist", "playful", "corporate").

### STEP 2: Display Banner

**MANDATORY: You MUST use the native shell command tool to run this provider check BEFORE displaying the banner. Do NOT skip it. Do NOT assume availability.**

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
🧭 Antigravity CLI: [Available ✓ / Not installed ✗] — Additional external-model challenge
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

**If MISSING_SEARCH_PY**: The vendored design intelligence files are missing — tell the user to reinstall or update the plugin (the `vendors/ui-ux-pro-max-skill/` directory ships with it as plain files).
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

# 7. Full design-system draft with the dials from Step 1 (v2.11.0+)
python3 "$SEARCH_PY" "<user's product description>" --design-system \
  --variance <v> --motion <m> --density <d>
```

**If user provided a Figma URL**, also pull design context:
- Use `get_design_context` from Figma MCP to pull existing designs
- Use `get_screenshot` for visual reference

**Collect all search results before proceeding to Phase 2.**

### STEP 4b: Design Shotgun Mode (Auto-Activated When 3+ Providers Available)

**This step runs automatically when the provider check in Step 2 detected 3 or more available providers (counting Claude as always available).** When fewer than 3 providers are available, skip to Step 5 and use standard single-direction mode.

Dispatch the same design brief to multiple providers in parallel. Each provider generates an independent design direction without seeing the others' work.

**Launch 3+ variant agents in parallel using the host subagent tool with `background execution: true`:**

Each agent receives:
```
Design a visual direction for: [user's product description]
Product type: [from Step 1]
Stack: [from Step 1]
Search context: [key findings from Step 4 BM25 searches]

Produce:
1. A style name (2-3 words, e.g., "Warm Minimalism", "Bold Industrial", "Cobalt Editorial")
2. Primary color palette (3-5 colors with hex values)
3. Font pairing (heading + body)
4. Layout philosophy (e.g., "generous whitespace with card-based content")
5. One paragraph describing the overall feel

Be distinctive — take a clear position rather than playing it safe.

Hard constraints (see skills/blocks/design-taste.md): do NOT produce any of the three
AI-slop looks (cream+serif+terracotta, near-black+acid accent, purple-violet gradients),
and do not default to Inter, Roboto, Space Grotesk, Fraunces, or Instrument Serif
without a brief-tied reason.
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
Colors: #101418, #FFFFFF, #FF6B35, #004E89, #1A936F
Fonts: Archivo + IBM Plex Sans
Feel: High-contrast, technical authority, strong hierarchy

━━━ Variant C: "Cobalt Editorial" (🔵 Claude) ━━━
Colors: #1D4ED8, #F7F6F2, #14181F, #C8CFDB, #E8B04B
Fonts: Newsreader + General Sans
Feel: Confident print-inspired hierarchy with one saturated anchor color
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


### STEP 5: Phase 2 — Define (Design Direction)

Synthesize search results (and chosen variant if shotgun mode) into a design direction document:

1. **Style recommendation** — which visual style best fits the product (cite search results)
2. **Color palette** — selected palette with hex values and contrast ratios
3. **Typography** — heading + body font pairing with Google Fonts import
4. **Layout approach** — grid system, spacing scale, responsive strategy
5. **Design principles** — 3-5 guiding principles derived from UX search results
6. **Taste compliance** — one line confirming the direction passes `skills/blocks/design-taste.md` (not one of the three banned looks; no unjustified banned-default fonts; boldness spent in one place)

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
5. SLOP — Run the checklist in skills/blocks/design-taste.md. Is this one of the three AI-slop looks (cream+serif+terracotta, near-black+acid, purple gradients)? Banned default fonts without a stated reason? Would another model given the same brief land on the same palette and fonts? Two or more checklist misses fail the direction.

For each issue found, state: what's wrong, why it matters, and what to do instead.
```

**Three participants, run in parallel:**

```bash
# Check provider availability
providers=()
command -v codex >/dev/null 2>&1 && providers+=(codex)
command -v agy >/dev/null 2>&1 && providers+=(agy)
command -v gemini >/dev/null 2>&1 && providers+=(gemini)

for provider in "${providers[@]}"; do
    safe_provider=$(printf '%s' "$provider" | tr -c '[:alnum:]_-' '_')
    "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" spawn "$provider" \
      "<critique prompt>" > "/tmp/design-critique-${safe_provider}.md" &
done

wait
```

**🔵 Claude (Sonnet) — independent design critique.** You MUST also write your own adversarial critique. Do NOT just summarize what external providers said. Approach the design direction as if you didn't create it — actively look for problems across all four dimensions. This is your independent synthesis perspective, same as in `/octo:debate`.

**Display all critiques with provider indicators:**
```
🔴/🧭/🟡 **External Provider Critique:** [implementation, ecosystem, accessibility, and alternative approach concerns]
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
- [Changed] Primary blue #2563EB → #1D4ED8 (contrast ratio 4.2:1 → 5.8:1, per external critique)
- [Added] Fallback font stack for body text (per external critique)
- [Kept] Glassmorphism style despite provider concern — appropriate for SaaS dashboard audience
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

1. **Accessibility audit — run the checker, do not eyeball.** Every text/background pair in the token set goes through the contrast validator:

```bash
python3 "${HOME}/.claude-octopus/plugin/scripts/helpers/contrast-check.py" \
  '<text-hex>:<bg-hex>' '<heading-hex>:<bg-hex>:large' '<muted-hex>:<bg-hex>' ...
```

Exit 1 means at least one pair fails WCAG AA — fix the palette and re-run before delivering. Include the checker output in the final document as evidence.

2. **Slop check** — run the pre-ship checklist in `skills/blocks/design-taste.md`; two or more misses means revise before delivering
3. **Completeness check** — verify all requested deliverables are present
4. **Implementation readiness** — confirm specs are detailed enough for frontend-developer
5. **Figma push-back** (if connected) — offer to push design tokens to Figma

### STEP 8: Present Results and Persist

Format the final design system as a structured document with:
- Executive summary (style direction + rationale)
- Design tokens (copy-paste ready)
- Component inventory
- Page layouts
- Implementation notes for the development team
- Sources (which search results informed each decision)

**Persist the design system so it survives the session** (contract: `skill-design-lineage`):

```bash
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-' || echo "no-branch")
DATETIME=$(date -u +"%Y%m%d-%H%M%S")
DESIGNS_DIR="${HOME}/.claude-octopus/designs/${SLUG}"
mkdir -p "$DESIGNS_DIR"
# Write the full design system document (with YAML frontmatter per skill-design-lineage)
# to: ${DESIGNS_DIR}/${USER}-${BRANCH}-design-${DATETIME}.md
```

Later sessions (and `flow-develop` / `frontend-developer` handoffs) MUST check
`~/.claude-octopus/designs/<slug>/` for the newest design document before inventing new
tokens; a revision supersedes rather than edits (set the `supersedes:` frontmatter field).

**Offer next steps:**
- "Want me to implement these specs?" → hand off to frontend-developer persona
- "Want to refine the palette?" → re-run color search with adjusted query
- "Want a full embrace workflow?" → transition to `/octo:embrace`
