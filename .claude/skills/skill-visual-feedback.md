---
name: skill-visual-feedback
aliases:
  - visual-feedback
  - ui-ux-fixes
  - image-feedback
description: |
  Process image-based UI/UX feedback to identify, analyze, and fix visual issues.
  Handles screenshots with descriptions, button styling issues, layout problems.
trigger: |
  AUTOMATICALLY ACTIVATE when user provides visual feedback:
  - "[Image X] The /settings should be Y"
  - "[Image X] these button styles need to be fixed"
  - "[Image X] When X is set to Y, it shows as Z"
  - "button styles need to be fixed everywhere"
  - "UI is a hot mess" or "UX still a hot mess"
  - Screenshots with descriptions of visual issues

  DO NOT activate for:
  - Text-only feedback without visual context
  - General feature requests
  - Code-only issues
  - Performance problems
---

# Visual Feedback Processing

## Overview

Systematic approach to processing image-based UI/UX feedback, identifying visual issues, and implementing fixes.

**Core principle:** Analyze image → Identify issues → Locate code → Fix systematically → Verify visually.

---

## When to Use

**Use this skill when user provides:**
- Screenshots with UI/UX problems
- "[Image]" prefix with description of visual issues
- Complaints about "messy UI" or "hot mess UX"
- Button styling or layout issues with visual examples
- "This should look like X but shows as Y" with images

**Do NOT use for:**
- Pure code issues without visual context
- Feature requests without UI mockups
- Performance or functional bugs
- Backend issues

---

## The Process

### Phase 1: Visual Analysis

When user provides image feedback:

#### Step 1: Acknowledge and Examine

```markdown
I can see the screenshot showing [describe what you observe].

Let me analyze the visual issues:

**Observed Problems:**
1. [Issue 1: e.g., Button styles inconsistent]
2. [Issue 2: e.g., Layout misaligned]
3. [Issue 3: e.g., Colors don't match design system]

**Expected Behavior (from description):**
- [What user said it should be]

**Actual Behavior (from image):**
- [What the image shows]
```

#### Step 2: Categorize Issues

| Issue Type | Examples |
|------------|----------|
| **Styling** | Colors, fonts, spacing, borders |
| **Layout** | Alignment, positioning, responsive behavior |
| **Component** | Wrong component used, missing component |
| **State** | Hover states, active states, disabled states |
| **Consistency** | Inconsistent patterns across UI |

```markdown
**Issue Categories:**
- Styling: [list specific styling issues]
- Layout: [list layout issues]
- Component: [list component issues]
- State: [list state-related issues]
- Consistency: [list inconsistency issues]
```

---

### Phase 2: Code Investigation

#### Step 1: Locate Relevant Components

```bash
# Search for component files related to the issue
# Example: For settings page issues
```

Use Glob to find component files:
```
**/*settings*.{tsx,jsx,ts,js,vue,svelte}
**/*button*.{tsx,jsx,ts,js,vue,svelte}
```

Use Grep to find specific elements:
```
# Search for className patterns
pattern: "className.*button|btn-"

# Search for style definitions
pattern: "style={{|styled\.|makeStyles"
```

#### Step 2: Identify Styling System

```markdown
**Styling Approach Detected:**
- [ ] CSS Modules
- [ ] Styled Components
- [ ] Tailwind CSS
- [ ] Emotion/styled
- [ ] Plain CSS
- [ ] CSS-in-JS (other)

**Design System:**
- [ ] Custom design system
- [ ] Material-UI
- [ ] Ant Design
- [ ] Chakra UI
- [ ] Other: [name]
```

#### Step 3: Read Affected Files

Read the component files and associated styles to understand current implementation.

---

### Phase 3: Root Cause Analysis

#### Step 1: Identify Why Issue Exists

Common root causes:

| Root Cause | Indicators |
|------------|------------|
| **Inconsistent styling** | Multiple ways to style same element |
| **Missing design tokens** | Hard-coded colors/spacing |
| **Wrong component variant** | Using primary when should use secondary |
| **State not handled** | Missing hover/active/disabled styles |
| **Responsive issues** | Fixed widths, missing breakpoints |
| **Override conflicts** | Specificity wars, !important overuse |
| **Deprecated patterns** | Old styling approach still in use |

```markdown
**Root Cause Analysis:**

Issue: [specific visual problem]
Root Cause: [why it's happening]
Evidence: [code snippet or pattern showing the cause]

Impact:
- Affects: [which pages/components]
- Frequency: [how often users see this]
- Scope: [single instance or systemic]
```

#### Step 2: Scope the Fix

```markdown
**Fix Scope:**

Option 1: **Targeted Fix** (fix just this instance)
- Files to modify: [list]
- Risk: Low
- Coverage: Fixes reported issue only

Option 2: **Systematic Fix** (fix pattern everywhere)
- Files to modify: [list]
- Risk: Medium
- Coverage: Fixes all instances of this pattern

Option 3: **Design System Fix** (update base component)
- Files to modify: [design system files]
- Risk: Higher (affects many components)
- Coverage: Fixes root cause system-wide

**Recommendation:** [which option and why]
```

Use AskUserQuestion to get user preference on scope.

---

### Phase 4: Implementation

#### Step 1: Create Fix Plan

For each identified issue:

```markdown
**Fix Plan:**

Issue: [description]
File: [file path]
Change: [what to change]
Before: [code snippet or description]
After: [code snippet or description]
```

#### Step 2: Implement Fixes

Apply fixes one at a time, using Edit tool:

```markdown
Fixing [Issue 1]...
- File: [path]
- Change: [description]
✓ Fixed

Fixing [Issue 2]...
- File: [path]
- Change: [description]
✓ Fixed
```

#### Step 3: Ensure Consistency

If "everywhere" or "all instances" is mentioned:

```bash
# Search for all instances of the pattern
# Example: Find all primary buttons
```

Use Grep to find all instances, then fix each one:

```markdown
**Pattern Search:** "button.*primary"

Found in:
1. src/components/Header.tsx:45
2. src/pages/Settings.tsx:123
3. src/pages/Dashboard.tsx:67

Fixing all instances...
```

Fix each file systematically.

---

### Phase 5: Verification

#### Step 1: Visual Verification Checklist

```markdown
**Verification Checklist:**

Visual Issues:
- [ ] Button styles consistent
- [ ] Layout aligned properly
- [ ] Colors match design system
- [ ] Spacing is uniform
- [ ] Typography consistent

Responsive:
- [ ] Works on mobile
- [ ] Works on tablet
- [ ] Works on desktop

States:
- [ ] Default state correct
- [ ] Hover state correct
- [ ] Active state correct
- [ ] Disabled state correct
- [ ] Focus state accessible

**How to verify:**
1. Run dev server: `npm run dev`
2. Navigate to [affected page]
3. Check all items above
4. Compare with original screenshot
```

#### Step 2: Request User Confirmation

```markdown
✅ **Fixes Applied**

Changes made:
1. [Change 1]
2. [Change 2]
3. [Change 3]

**Please verify:**
- Open [URL or page]
- Check that [specific issue] is now resolved
- Verify no new issues introduced

Let me know if the visual issues are resolved or if further adjustments are needed.
```

---

## Common Patterns

### Pattern 1: Button Style Consistency

```
User: "[Image] these button styles need to be fixed everywhere"

Process:
1. Analyze image - identify button style issues
2. Search for all button components
3. Identify design system button component
4. Update base button component OR
5. Update all instances to use correct variant
6. Verify consistency across app
```

### Pattern 2: Layout Misalignment

```
User: "[Image] When logo position is set to Top right, it shows as Middle right"

Process:
1. Analyze image - see position mismatch
2. Find logo positioning code
3. Identify why "Top right" maps to "Middle right"
4. Fix the mapping or positioning logic
5. Test all position options
6. Verify with user
```

### Pattern 3: Settings UI Issues

```
User: "[Image] The /settings should be dropdowns not text inputs"

Process:
1. Analyze image - see text inputs instead of dropdowns
2. Navigate to settings component code
3. Identify field definitions
4. Replace input components with select/dropdown
5. Ensure options are populated correctly
6. Verify all settings fields
```

### Pattern 4: General "Hot Mess" Feedback

```
User: "why is the Display Ad Creator UX still a hot mess?"

Process:
1. Ask for specific issues or screenshot
2. If provided, analyze systematically
3. Create prioritized list of issues
4. Fix highest-impact issues first
5. Verify improvements with user
```

---

## Integration with Other Skills

### With skill-debug

```
Visual issue that doesn't make sense?
→ Use skill-debug to investigate why visual state is incorrect
```

### With skill-audit

```
User says "fix these everywhere"?
→ Use skill-audit to find all instances
→ Use skill-visual-feedback to fix each systematically
```

### With flow-tangle

```
Visual feedback requires new component?
→ Use flow-tangle to implement the component
→ Use skill-visual-feedback to verify it matches design
```

---

## Best Practices

### 1. Always Acknowledge the Visual Evidence

**Good:**
```
I can see in the screenshot that the button has inconsistent padding and the wrong color scheme compared to other primary buttons in the interface.
```

**Poor:**
```
I'll fix the button.
```

### 2. Be Specific About Changes

**Good:**
```
Changing:
- Button background: #3498db → #2563eb (primary-600)
- Padding: 8px 12px → 12px 16px
- Border radius: 4px → 6px
```

**Poor:**
```
Updating button styles.
```

### 3. Consider Mobile/Responsive

Always check if the fix works across breakpoints:

```markdown
**Responsive Verification:**
- Mobile (< 768px): [status]
- Tablet (768px - 1024px): [status]
- Desktop (> 1024px): [status]
```

---

## Red Flags - Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Fix without analyzing the image | Might fix wrong thing |
| Change only one instance when user says "everywhere" | Incomplete fix |
| Use !important to force styles | Creates specificity problems |
| Hard-code colors instead of using design tokens | Inconsistent with system |
| Skip verification | User has to report same issue again |
| Make assumptions without asking | Might not match user's vision |

---

## Quick Reference

| User Feedback Pattern | Action Required |
|----------------------|-----------------|
| "[Image] X should be Y" | Analyze image → Find code → Fix → Verify |
| "Button styles everywhere" | Find all instances → Fix systematically |
| "UI is a mess" | Request specifics → Prioritize → Fix incrementally |
| "When X, shows Y instead of Z" | Debug state/logic → Fix mapping → Test all cases |

---

## The Bottom Line

```
Visual feedback → Image analysis + Systematic fix + Visual verification
Otherwise → Guessing at fixes + Incomplete coverage
```

**See the issue. Understand the root cause. Fix it everywhere. Verify visually.**
