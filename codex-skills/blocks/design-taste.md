# Design Taste — Anti-Slop Rules (shared block)

Shared constraint set for design-producing skills (`octopus-ui-ux-design`, `skill-extract`,
`skill-deck`, frontend work in `flow-develop`). Rules are binary and mechanically checkable
on purpose: "use sparingly" phrasing has been shown to fail under generation pressure, while
countable rules hold. Derived from the highest-signal public taste rulebooks (Anthropic
frontend-design, Leonxlnx/taste-skill, ui-ux-pro-max) plus octopus review experience.

## 1. Aesthetic direction first

Before any tokens or code, commit to a named aesthetic direction in one sentence
("Reading this as: <page kind> for <audience>, with a <vibe> visual language").
Then run the convergence check: **would another model, given the same brief, land on the
same palette and fonts?** If yes, you are at the statistical center — move at least one
axis (palette, type, or layout) somewhere deliberate. Spend boldness in ONE place;
everything else stays quiet.

## 2. Banned defaults (the three AI-slop looks)

Never land on these unless the brief explicitly asks:

1. **Warm-cream heritage**: cream background (#F4F1EA-family) + high-contrast display serif + terracotta accent
2. **Dark acid**: near-black background + single acid-green or vermilion accent
3. **AI purple**: #667EEA/#764BA2-family purple-violet gradients, purple glows on dark

Palette rules:
- No pure `#000000` backgrounds or text
- Do not reuse the same palette family across consecutive projects in a session
- Every text/background pair must pass WCAG AA — verify with the contrast checker
  (`scripts/helpers/contrast-check.py`), never by eye

## 3. Font rules

- **Banned as unjustified defaults**: Inter, Roboto, Arial, Space Grotesk, Fraunces, Instrument Serif
  (the statistically overused AI picks). Any of these requires a stated reason tied to the brief.
- No mixed-family word emphasis inside a headline (serif word inside sans headline); use
  weight or italic of the same family
- Two families maximum; pair by contrast of role (display vs text), not by trend

## 4. Layout and structure tells

- Hero: headline ≤ 2 lines, subtext ≤ 20 words; "big number + small label + gradient accent" is the template answer — do something else
- No third consecutive image/text zigzag split; 8+ sections need at least 4 distinct layout families
- Numbered section markers (01/02/03) only when content is genuinely sequential
- Eyebrow labels (uppercase tracking-wide): at most 1 per 3 sections
- No div-built fake app screenshots; render real content or omit
- No scroll-cue arrows, no decorative version badges (`V2.0`, `BETA`) in heroes

## 5. Content tells

- No placeholder personas: "Jane Doe", "John Smith", "Acme Corp", "Sarah Chen"
- No fake-perfect stats (99.99%, 10x, "trusted by 10,000+ teams"); use organic numbers (47.2%) or none
- No em dashes in UI copy; commas, semicolons, parentheses, or sentence breaks instead
- Buttons name the action ("Save changes", not "Submit"); state persists through the flow
  ("Publish" button leads to a "Published" toast); errors state the fix, never apologize
- Copy self-audit before ship: flag anything that reads like an LLM trying to sound thoughtful

## 6. Quality floor (never announce, always meet)

- Responsive at 360px, 768px, 1280px without horizontal scroll
- Visible focus states on all interactive elements; touch targets ≥ 44px
- `prefers-reduced-motion` respected when motion is present
- Real font fallback stacks, not a single family name

## 7. Pre-ship slop check (binary, all must pass)

- [ ] Aesthetic direction stated before code, and it is not one of the three banned looks
- [ ] No banned default font without a stated, brief-tied reason
- [ ] Contrast checker run on every text/background pair (not eyeballed)
- [ ] Zero placeholder personas, fake-perfect stats, or em dashes in visible copy
- [ ] Eyebrow count ≤ ceil(sections / 3); no third consecutive zigzag
- [ ] Focus states, reduced-motion, and 360px responsiveness verified

When any design output is critiqued (Step 5b of `octopus-ui-ux-design`, `/octo:review` on
frontend diffs), SLOP is a first-class critique dimension: reviewers check this list and
fail the direction if two or more items miss.
