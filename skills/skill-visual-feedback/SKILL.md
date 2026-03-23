---
name: skill-visual-feedback
version: 1.0.0
description: "Process screenshot-based UI/UX feedback by analyzing images, locating affected components, fixing visual issues systematically, and verifying results. Use when: user provides a screenshot with UI complaints, says '[Image] X should be Y', reports button styling or layout issues with visual examples, or describes visual mismatches between expected and actual UI."
---

# Visual Feedback Processing

Analyze image → Identify issues → Locate code → Fix systematically → Verify visually.

---

## When to Use

- Screenshots with UI/UX problems or "[Image]" prefix descriptions
- Button styling, layout, or consistency issues with visual examples
- "This should look like X but shows as Y" with images

**Not for:** Pure code issues without visuals, feature requests without mockups, performance/functional bugs, backend issues.

---

## Process

### Phase 1: Visual Analysis

1. **Acknowledge and examine** — Describe what the screenshot shows, list observed problems, compare expected vs actual behavior
2. **Categorize issues** — Styling (colors, fonts, spacing), Layout (alignment, positioning), Component (wrong variant), State (hover/active/disabled), Consistency

### Phase 2: Code Investigation

1. **Locate components** — Use Glob for component files, Grep for className patterns and style definitions
2. **Identify styling system** — CSS Modules, Styled Components, Tailwind, Emotion, plain CSS, etc.
3. **Read affected files** to understand current implementation

### Phase 3: Root Cause Analysis

Common root causes:

| Root Cause | Indicators |
|------------|------------|
| Inconsistent styling | Multiple ways to style same element |
| Missing design tokens | Hard-coded colors/spacing |
| Wrong component variant | Using primary when should be secondary |
| State not handled | Missing hover/active/disabled styles |
| Responsive issues | Fixed widths, missing breakpoints |
| Override conflicts | Specificity wars, !important overuse |

**Scope the fix:** Offer targeted (single instance), systematic (all instances), or design-system-level fix. Use AskUserQuestion for user preference.

### Phase 4: Implementation

1. **Create fix plan** — Issue, file, before/after for each change
2. **Apply fixes** one at a time using Edit tool
3. **Ensure consistency** — If "everywhere" mentioned, Grep for all instances and fix each

### Phase 5: Verification

Checklist: button styles consistent, layout aligned, colors match design system, spacing uniform, responsive across mobile/tablet/desktop, all states (default/hover/active/disabled/focus) correct.

Request user confirmation with specific changes made and instructions to verify.

---

## Anti-Patterns

| Don't | Why |
|-------|-----|
| Fix without analyzing the image | Might fix wrong thing |
| Change only one instance when user says "everywhere" | Incomplete fix |
| Use !important to force styles | Creates specificity problems |
| Hard-code colors instead of design tokens | Inconsistent with system |
| Skip verification | User reports same issue again |

---

## Integration

- **skill-debug** — When visual issue doesn't make sense, investigate underlying state
- **skill-audit** — When "fix everywhere", find all instances first
- **flow-tangle** — When fix requires a new component
