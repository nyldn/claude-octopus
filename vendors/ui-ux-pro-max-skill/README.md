# [UI UX Pro Max](https://uupm.cc)

<p align="center">
  <a href="https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/README.zh.md">🇨🇳 简体中文</a> | 
  <a href="https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/README.md">🇺🇸 English</a>
</p>

<p align="center">
  <a href="https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/releases"><img src="https://img.shields.io/github/v/release/nextlevelbuilder/ui-ux-pro-max-skill?style=for-the-badge&color=blue" alt="GitHub Release"></a>
  <img src="https://img.shields.io/badge/reasoning_rules-161-green?style=for-the-badge" alt="161 Reasoning Rules">
  <img src="https://img.shields.io/badge/UI_styles-67-purple?style=for-the-badge" alt="67 UI Styles">
  <img src="https://img.shields.io/badge/python-3.x-yellow?style=for-the-badge&logo=python&logoColor=white" alt="Python 3.x">
  <a href="https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/LICENSE"><img src="https://img.shields.io/github/license/nextlevelbuilder/ui-ux-pro-max-skill?style=for-the-badge&color=green" alt="License"></a>
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/ui-ux-pro-max-cli"><img src="https://img.shields.io/npm/v/ui-ux-pro-max-cli?style=flat-square&logo=npm&label=CLI" alt="npm"></a>
  <a href="https://www.npmjs.com/package/ui-ux-pro-max-cli"><img src="https://img.shields.io/npm/dm/ui-ux-pro-max-cli?style=flat-square&label=downloads" alt="npm downloads"></a>
  <a href="https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/stargazers"><img src="https://img.shields.io/github/stars/nextlevelbuilder/ui-ux-pro-max-skill?style=flat-square&logo=github" alt="GitHub stars"></a>
  <a href="https://paypal.me/uiuxpromax"><img src="https://img.shields.io/badge/PayPal-Support%20Development-00457C?style=flat-square&logo=paypal&logoColor=white" alt="PayPal"></a>
</p>

An AI skill that provides design intelligence for building professional UI/UX across multiple platforms and frameworks.

<p align="center">
  <a href="https://uupm.cc">
    <img src="screenshots/website.png" alt="UI UX Pro Max" width="800">
  </a>
</p>

<p align="center">
  <b>If you find this useful, consider supporting the project:</b><br><br>
  <a href="https://paypal.me/uiuxpromax"><img src="https://img.shields.io/badge/PayPal-Donate-00457C?style=for-the-badge&logo=paypal&logoColor=white" alt="PayPal Donate"></a>
</p>

<p align="center">
  <i>Other projects</i><br>
  <a href="https://nextlevelbuilder.io">NextLevelBuilder.io</a> | <a href="https://goclaw.sh">GoClaw.sh</a> | <a href="https://claudekit.cc">ClaudeKit.cc</a> | <a href="https://tose.sh">TOSE.sh</a>
</p>

## What's New in v2.0

### Intelligent Design System Generation

The flagship feature of v2.0 is the **Design System Generator** - an AI-powered reasoning engine that analyzes your project requirements and generates a complete, tailored design system in seconds.

```
+----------------------------------------------------------------------------------------+
|  TARGET: Serenity Spa - RECOMMENDED DESIGN SYSTEM                                      |
+----------------------------------------------------------------------------------------+
|                                                                                        |
|  PATTERN: Hero-Centric + Social Proof                                                  |
|     Conversion: Emotion-driven with trust elements                                     |
|     CTA: Above fold, repeated after testimonials                                       |
|     Sections:                                                                          |
|       1. Hero                                                                          |
|       2. Services                                                                      |
|       3. Testimonials                                                                  |
|       4. Booking                                                                       |
|       5. Contact                                                                       |
|                                                                                        |
|  STYLE: Soft UI Evolution                                                              |
|     Keywords: Soft shadows, subtle depth, calming, premium feel, organic shapes        |
|     Best For: Wellness, beauty, lifestyle brands, premium services                     |
|     Performance: Excellent | Accessibility: WCAG AA                                    |
|                                                                                        |
|  COLORS:                                                                               |
|     Primary:    #E8B4B8 (Soft Pink)                                                    |
|     Secondary:  #A8D5BA (Sage Green)                                                   |
|     CTA:        #D4AF37 (Gold)                                                         |
|     Background: #FFF5F5 (Warm White)                                                   |
|     Text:       #2D3436 (Charcoal)                                                     |
|     Notes: Calming palette with gold accents for luxury feel                           |
|                                                                                        |
|  TYPOGRAPHY: Cormorant Garamond / Montserrat                                           |
|     Mood: Elegant, calming, sophisticated                                              |
|     Best For: Luxury brands, wellness, beauty, editorial                               |
|     Google Fonts: https://fonts.google.com/share?selection.family=...                  |
|                                                                                        |
|  KEY EFFECTS:                                                                          |
|     Soft shadows + Smooth transitions (200-300ms) + Gentle hover states                |
|                                                                                        |
|  AVOID (Anti-patterns):                                                                |
|     Bright neon colors + Harsh animations + Dark mode + AI purple/pink gradients       |
|                                                                                        |
|  PRE-DELIVERY CHECKLIST:                                                               |
|     [ ] No emojis as icons (use SVG: Heroicons/Lucide)                                 |
|     [ ] cursor-pointer on all clickable elements                                       |
|     [ ] Hover states with smooth transitions (150-300ms)                               |
|     [ ] Light mode: text contrast 4.5:1 minimum                                        |
|     [ ] Focus states visible for keyboard nav                                          |
|     [ ] prefers-reduced-motion respected                                               |
|     [ ] Responsive: 375px, 768px, 1024px, 1440px                                       |
|                                                                                        |
+----------------------------------------------------------------------------------------+
```

### How Design System Generation Works

```
┌─────────────────────────────────────────────────────────────────┐
│  1. USER REQUEST                                                │
│     "Build a landing page for my beauty spa"                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. MULTI-DOMAIN SEARCH (5 parallel searches)                   │
│     • Product type matching (161 categories)                    │
│     • Style recommendations (67 styles)                         │
│     • Color palette selection (161 palettes)                    │
│     • Landing page patterns (24 patterns)                       │
│     • Typography pairing (57 font combinations)                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. REASONING ENGINE                                            │
│     • Match product → UI category rules                         │
│     • Apply style priorities (BM25 ranking)                     │
│     • Filter anti-patterns for industry                         │
│     • Process decision rules (JSON conditions)                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. COMPLETE DESIGN SYSTEM OUTPUT                               │
│     Pattern + Style + Colors + Typography + Effects             │
│     + Anti-patterns to avoid + Pre-delivery checklist           │
└─────────────────────────────────────────────────────────────────┘
```

### 161 Industry-Specific Reasoning Rules

The reasoning engine includes specialized rules for:

| Category | Examples |
|----------|----------|
| **Tech & SaaS** | SaaS, Micro SaaS, B2B Service, Developer Tool / IDE, AI/Chatbot Platform, Cybersecurity Platform |
| **Finance** | Fintech/Crypto, Banking, Insurance, Personal Finance Tracker, Invoice & Billing Tool |
| **Healthcare** | Medical Clinic, Pharmacy, Dental, Veterinary, Mental Health, Medication Reminder |
| **E-commerce** | General, Luxury, Marketplace (P2P), Subscription Box, Food Delivery |
| **Services** | Beauty/Spa, Restaurant, Hotel, Legal, Home Services, Booking & Appointment |
| **Creative** | Portfolio, Agency, Photography, Gaming, Music Streaming, Photo/Video Editor |
| **Lifestyle** | Habit Tracker, Recipe & Cooking, Meditation, Weather, Diary, Mood Tracker |
| **Emerging Tech** | Web3/NFT, Spatial Computing, Quantum Computing, Autonomous Drone Fleet |

Each rule includes:
- **Recommended Pattern** - Landing page structure
- **Style Priority** - Best matching UI styles
- **Color Mood** - Industry-appropriate palettes
- **Typography Mood** - Font personality matching
- **Key Effects** - Animations and interactions
- **Anti-Patterns** - What NOT to do (e.g., "AI purple/pink gradients" for banking)

## Features

- **67 UI Styles** - Glassmorphism, Claymorphism, Minimalism, Brutalism, Neumorphism, Bento Grid, Dark Mode, AI-Native UI, and more
- **161 Color Palettes** - Industry-specific palettes aligned 1:1 with the 161 product types
- **57 Font Pairings** - Curated typography combinations with Google Fonts imports
- **25 Chart Types** - Recommendations for dashboards and analytics
- **22 Tech Stacks** - React, Next.js, Astro, Vue, Nuxt.js, Nuxt UI, Svelte, SwiftUI, React Native, Flutter, HTML+Tailwind, shadcn/ui, Jetpack Compose, Angular, Laravel, Three.js, JavaFX, WPF, WinUI 3, UWP, Avalonia, Uno Platform
- **99 UX Guidelines** - Best practices, anti-patterns, and accessibility rules
- **161 Reasoning Rules** - Industry-specific design system generation (NEW in v2.0)

### Available Styles (67)

<details>
<summary><b>General Styles (49)</b></summary>

| # | Style | Best For |
|---|-------|----------|
| 1 | Minimalism & Swiss Style | Enterprise apps, dashboards, documentation |
| 2 | Neumorphism | Health/wellness apps, meditation platforms |
| 3 | Glassmorphism | Modern SaaS, financial dashboards |
| 4 | Brutalism | Design portfolios, artistic projects |
| 5 | 3D & Hyperrealism | Gaming, product showcase, immersive |
| 6 | Vibrant & Block-based | Startups, creative agencies, gaming |
| 7 | Dark Mode (OLED) | Night-mode apps, coding platforms |
| 8 | Accessible & Ethical | Government, healthcare, education |
| 9 | Claymorphism | Educational apps, children's apps, SaaS |
| 10 | Aurora UI | Modern SaaS, creative agencies |
| 11 | Retro-Futurism | Gaming, entertainment, music platforms |
| 12 | Flat Design | Web apps, mobile apps, startup MVPs |
| 13 | Skeuomorphism | Legacy apps, gaming, premium products |
| 14 | Liquid Glass | Premium SaaS, high-end e-commerce |
| 15 | Motion-Driven | Portfolio sites, storytelling platforms |
| 16 | Micro-interactions | Mobile apps, touchscreen UIs |
| 17 | Inclusive Design | Public services, education, healthcare |
| 18 | Zero Interface | Voice assistants, AI platforms |
| 19 | Soft UI Evolution | Modern enterprise apps, SaaS |
| 20 | Neubrutalism | Gen Z brands, startups, Figma-style |
| 21 | Bento Box Grid | Dashboards, product pages, portfolios |
| 22 | Y2K Aesthetic | Fashion brands, music, Gen Z |
| 23 | Cyberpunk UI | Gaming, tech products, crypto apps |
| 24 | Organic Biophilic | Wellness apps, sustainability brands |
| 25 | AI-Native UI | AI products, chatbots, copilots |
| 26 | Memphis Design | Creative agencies, music, youth brands |
| 27 | Vaporwave | Music platforms, gaming, portfolios |
| 28 | Dimensional Layering | Dashboards, card layouts, modals |
| 29 | Exaggerated Minimalism | Fashion, architecture, portfolios |
| 30 | Kinetic Typography | Hero sections, marketing sites |
| 31 | Parallax Storytelling | Brand storytelling, product launches |
| 32 | Swiss Modernism 2.0 | Corporate sites, architecture, editorial |
| 33 | HUD / Sci-Fi FUI | Sci-fi games, space tech, cybersecurity |
| 34 | Pixel Art | Indie games, retro tools, creative |
| 35 | Bento Grids | Product features, dashboards, personal |
| 36 | Spatial UI (VisionOS) | Spatial computing apps, VR/AR |
| 37 | E-Ink / Paper | Reading apps, digital newspapers |
| 38 | Gen Z Chaos / Maximalism | Gen Z lifestyle, music artists |
| 39 | Biomimetic / Organic 2.0 | Sustainability tech, biotech, health |
| 40 | Anti-Polish / Raw Aesthetic | Creative portfolios, artist sites |
| 41 | Tactile Digital / Deformable UI | Modern mobile apps, playful brands |
| 42 | Nature Distilled | Wellness brands, sustainable products |
| 43 | Interactive Cursor Design | Creative portfolios, interactive |
| 44 | Voice-First Multimodal | Voice assistants, accessibility apps |
| 45 | 3D Product Preview | E-commerce, furniture, fashion |
| 46 | Gradient Mesh / Aurora Evolved | Hero sections, backgrounds, creative |
| 47 | Editorial Grid / Magazine | News sites, blogs, magazines |
| 48 | Chromatic Aberration / RGB Split | Music platforms, gaming, tech |
| 49 | Vintage Analog / Retro Film | Photography, music/vinyl brands |

</details>

<details>
<summary><b>Landing Page Styles (8)</b></summary>

| # | Style | Best For |
|---|-------|----------|
| 1 | Hero-Centric Design | Products with strong visual identity |
| 2 | Conversion-Optimized | Lead generation, sales pages |
| 3 | Feature-Rich Showcase | SaaS, complex products |
| 4 | Minimal & Direct | Simple products, apps |
| 5 | Social Proof-Focused | Services, B2C products |
| 6 | Interactive Product Demo | Software, tools |
| 7 | Trust & Authority | B2B, enterprise, consulting |
| 8 | Storytelling-Driven | Brands, agencies, nonprofits |

</details>

<details>
<summary><b>BI/Analytics Dashboard Styles (10)</b></summary>

| # | Style | Best For |
|---|-------|----------|
| 1 | Data-Dense Dashboard | Complex data analysis |
| 2 | Heat Map & Heatmap Style | Geographic/behavior data |
| 3 | Executive Dashboard | C-suite summaries |
| 4 | Real-Time Monitoring | Operations, DevOps |
| 5 | Drill-Down Analytics | Detailed exploration |
| 6 | Comparative Analysis Dashboard | Side-by-side comparisons |
| 7 | Predictive Analytics | Forecasting, ML insights |
| 8 | User Behavior Analytics | UX research, product analytics |
| 9 | Financial Dashboard | Finance, accounting |
| 10 | Sales Intelligence Dashboard | Sales teams, CRM |

</details>

## 💎 Basic vs. Premium Version Comparison

Many users ask about the differences between the open-source and premium versions. Here is a detailed breakdown to help you choose the right fit for your workflow.

### 🟢 Basic Version (This Repository)
* **Fully Open Source:** Perfect for individual developers, hobbyists, and standard projects.
* **Core UI/UX Intelligence:** Full access to 67 UI styles, 161 product types, color palettes, and curated font pairings.
* **Smart Recommendations:** Built-in BM25 search engine for highly accurate design matching.
* **Cross-Platform Support:** Stack-specific guidelines supporting 13+ major frameworks (React, Vue, Tailwind, iOS, Android, etc.).
* **Design System Generation:** Instantly generate tailored UI rules, patterns, and logic via CLI.

### 🟡 Premium Version
* **Extended Brand Design Skills:** Goes beyond UI/UX to include Brand Identity generation, Logo Design, Corporate Identity Programs (CIP), Banners, Presentation Slides, and custom Iconography.
* **Advanced Asset Creation:** Deep integration with AI-powered image generation to create real visual assets, not just placeholders.
* **Enterprise Architecture:** A more comprehensive and scalable Design Token architecture, built for large-scale team deployments.
* **Priority Support:** Dedicated technical assistance for teams and professionals who need an uninterrupted full design workflow.

👉 *For more details on upgrading to the Premium tier, visit [uupm.cc](https://uupm.cc).*

## Installation

### Using Claude Marketplace (Claude Code)

Install directly in Claude Code with two commands:

```
/plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
/plugin install ui-ux-pro-max@ui-ux-pro-max-skill
```

### Using CLI (Recommended)

```bash
# Install CLI globally
npm install -g ui-ux-pro-max-cli

# Go to your project
cd /path/to/your/project

# Install for your AI assistant
uipro init --ai claude      # Claude Code
uipro init --ai cursor      # Cursor
uipro init --ai windsurf    # Windsurf
uipro init --ai antigravity # Antigravity
uipro init --ai copilot     # GitHub Copilot
uipro init --ai kiro        # Kiro
uipro init --ai codex       # Codex CLI
uipro init --ai qoder       # Qoder
uipro init --ai roocode     # Roo Code
uipro init --ai gemini      # Gemini CLI
uipro init --ai trae        # Trae
uipro init --ai opencode    # OpenCode
uipro init --ai continue    # Continue
uipro init --ai codebuddy   # CodeBuddy
uipro init --ai droid       # Droid (Factory)
uipro init --ai kilocode    # KiloCode
uipro init --ai warp        # Warp
uipro init --ai augment     # Augment
uipro init --ai codewhale   # CodeWhale
uipro init --ai all         # All assistants
```

The npm package is `ui-ux-pro-max-cli`; it still installs the `uipro` command. Older `uipro-cli` releases are stale and should not be used for current assets.

### Global Install (Available for All Projects)

```bash
uipro init --ai claude --global   # Install to ~/.claude/skills/
uipro init --ai cursor --global   # Install to ~/.cursor/skills/
```

### Other CLI Commands

```bash
uipro versions              # List available versions
uipro update                # Refresh skill files from installed CLI package
uipro init --offline        # Compatibility flag; installs bundled templates
uipro uninstall             # Remove skill (auto-detect platform)
uipro uninstall --ai claude # Remove specific platform
uipro uninstall --global    # Remove from global install
```

## Prerequisites

Python 3.x is required for the search script (standard library only — the scripts install nothing and make no network calls).

Check if Python is installed:

```bash
python3 --version
```

If it is missing, install it yourself from [python.org](https://www.python.org/downloads/) or with your OS package manager (Homebrew, apt, winget). These install steps are for **you, the human user** — AI agents using this skill should never install software on your machine; they are instructed to ask you instead.

## Usage

### Skill Mode (Auto-activate)

**Supported:** Claude Code, Cursor, Windsurf, Antigravity, Codex CLI, Continue, Gemini CLI, OpenCode, Qoder, CodeBuddy, Droid (Factory), KiloCode, Warp, Augment, CodeWhale

The skill activates automatically when you request UI/UX work. Just chat naturally:

```
Build a landing page for my SaaS product
```

> **Trae**: Switch to **SOLO** mode first. The skill will activate for UI/UX requests.

### Workflow Mode (Slash Command)

**Supported:** Kiro, GitHub Copilot, Roo Code, KiloCode

Use the slash command to invoke the skill:

```
/ui-ux-pro-max Build a landing page for my SaaS product
```

### Example Prompts

```
Build a landing page for my SaaS product

Create a dashboard for healthcare analytics

Design a portfolio website with dark mode

Make a mobile app UI for e-commerce

Build a fintech banking app with dark theme
```

### How It Works

1. **You ask** - Request any UI/UX task (build, design, create, implement, review, fix, improve)
2. **Design System Generated** - The AI automatically generates a complete design system using the reasoning engine
3. **Smart recommendations** - Based on your product type and requirements, it finds the best matching styles, colors, and typography
4. **Code generation** - Implements the UI with proper colors, fonts, spacing, and best practices
5. **Pre-delivery checks** - Validates against common UI/UX anti-patterns

### Supported Stacks

The skill provides stack-specific guidelines for:

| Category | Stacks |
|----------|--------|
| **Web (HTML)** | HTML + Tailwind (default) |
| **React Ecosystem** | React, Next.js, shadcn/ui |
| **Vue Ecosystem** | Vue, Nuxt.js, Nuxt UI |
| **Angular** | Angular |
| **PHP** | Laravel (Blade, Livewire, Inertia.js) |
| **Other Web** | Svelte, Astro, Three.js |
| **Desktop** | JavaFX |
| **iOS** | SwiftUI |
| **Android** | Jetpack Compose |
| **Cross-Platform** | React Native, Flutter |

Just mention your preferred stack in the prompt, or let it default to HTML + Tailwind.

## Design System Command (Advanced)

For direct access to the design system generator:

> Note: If you installed via Continue, replace `.claude/skills/` with `.continue/skills/` in the commands below. For Droid (Factory), use `.factory/skills/`.

```bash
# Generate design system with ASCII output
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "beauty spa wellness" --design-system -p "Serenity Spa"

# Generate with Markdown output
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "fintech banking" --design-system -f markdown

# Domain-specific search
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "glassmorphism" --domain style
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "elegant serif" --domain typography
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "dashboard" --domain chart

# Stack-specific guidelines
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "form validation" --stack react
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "responsive layout" --stack html-tailwind
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "tableview binding" --stack javafx
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "atlantafx primer enterprise theme" --stack javafx
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "enterprise tableview density permission" --stack javafx
```

### Persist Design System (Master + Overrides Pattern)

Save your design system to files for **hierarchical retrieval across sessions**:

```bash
# Generate and persist to design-system/MASTER.md
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "SaaS dashboard" --design-system --persist -p "MyApp"

# Also create a page-specific override file
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "SaaS dashboard" --design-system --persist -p "MyApp" --page "dashboard"
```

This creates a `design-system/` folder structure:

```
design-system/
├── MASTER.md           # Global Source of Truth (colors, typography, spacing, components)
└── pages/
    └── dashboard.md    # Page-specific overrides (only deviations from Master)
```

**How hierarchical retrieval works:**
1. When building a specific page (e.g., "Checkout"), first check `design-system/pages/checkout.md`
2. If the page file exists, its rules **override** the Master file
3. If not, use `design-system/MASTER.md` exclusively

**Context-aware retrieval prompt:**
```
I am building the [Page Name] page. Please read design-system/MASTER.md.
Also check if design-system/pages/[page-name].md exists.
If the page file exists, prioritize its rules.
If not, use the Master rules exclusively.
Now, generate the code...
```

## Architecture & Contributing

### For Users

The codebase has been restructured to use a **template-based generation system**. All platform-specific files (`.cursor/`, `.windsurf/`, `.kiro/`, `.factory/`, etc.) are now generated dynamically by the CLI.

**Always use the CLI to install:**

```bash
npm install -g ui-ux-pro-max-cli
uipro init --ai <platform>
```

This ensures you get the latest templates bundled with the installed CLI package and the correct file structure for your AI assistant. Update the npm package first when a new release is published.

### For Contributors

If you want to contribute to this project:

```bash
# 1. Clone the repository
git clone https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.git
cd ui-ux-pro-max-skill

# 2. Understand the structure
src/ui-ux-pro-max/           # Source of truth (data, scripts, templates)
cli/                         # CLI installer (generates files from templates)
.claude/                     # Local dev/test for Claude Code skill
.factory/                    # Local dev/test for Droid (Factory) skill

# 3. Make changes in src/ui-ux-pro-max/
# - data/*.csv              → Database files
# - scripts/*.py            → Search engine & design system
# - templates/              → Platform-specific templates

# 4. Sync to CLI and test locally
cd cli
npm run sync:assets
npm run check:assets
npm run validate:csv
npm run smoke:domains
npm run smoke:stacks
npm run typecheck

# 5. Build and test CLI
# `npm run build` uses Bun when available and falls back to TypeScript compiler output after `npm ci`.
npm run build
node dist/index.js init --ai claude --offline  # Test in a temp folder

# 6. Create PR (never push directly to main)
git checkout -b feat/your-feature
git commit -m "feat: description"
git push -u origin feat/your-feature
gh pr create
```

See [CLAUDE.md](CLAUDE.md) for detailed development guidelines.


## Automated Releases

This repository uses semantic-release with Conventional Commits to create GitHub releases automatically:

- `dev` branch creates beta GitHub prereleases such as `2.6.0-beta.1`.
- `main` branch creates official stable GitHub releases such as `2.6.0`.

Release notes and `CHANGELOG.md` are generated from Conventional Commit messages. Version numbers are synchronized across `skill.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `cli/package.json`, and `cli/package-lock.json` during release preparation.

Use these commit types for correct version bumps:

- `fix:` -> patch release
- `feat:` -> minor release
- `feat!:` or `BREAKING CHANGE:` -> major release

The release workflow uses the default `GITHUB_TOKEN` for GitHub releases and the repository `NPM_TOKEN` secret to publish `ui-ux-pro-max-cli` to npm.

## Troubleshooting

### `uipro: unknown command 'uninstall'` or `unknown command 'update'`

Your installed version of `ui-ux-pro-max-cli` is outdated. Update it and retry:

```bash
npm install -g ui-ux-pro-max-cli@latest
uipro uninstall
```

### `uipro uninstall` says "No installed AI skill directories detected"

The skill was installed in a different directory than where you're running the command. Either:

```bash
# Option A — run from the project root where you originally installed it
cd /path/to/your/project
uipro uninstall

# Option B — remove the global install
uipro uninstall --global

# Option C — remove manually
rm -rf .claude/skills/ui-ux-pro-max   # Claude Code
rm -rf .cursor/skills/ui-ux-pro-max   # Cursor
rm -rf .windsurf/skills/ui-ux-pro-max # Windsurf
rm -rf .agents/skills/ui-ux-pro-max   # Antigravity
```

### Claude Marketplace install fails with "Zip file contains a symbolic link"

This is a known issue with versions prior to v2.5.1. The repository used symlinks internally which some installation tools can't handle. **Fix:** use the CLI installer instead:

```bash
npm install -g ui-ux-pro-max-cli
uipro init --ai claude
```

Or wait for the next release where this is resolved.

### `npm install -g ui-ux-pro-max-cli` fails with permission error

Use a Node version manager (recommended), or skip the global install entirely:

```bash
# npx without installing globally
npx ui-ux-pro-max-cli init --ai claude
```

### Python not found when running design system commands

The search scripts require Python 3.x. Install it manually from [python.org](https://www.python.org/downloads/) or with your OS package manager (Homebrew, apt, winget). AI agents should not install it for you — they are instructed to ask you instead.

### Design system output is cut off / fields truncated

Use the `--max-length` flag to increase (or remove) the truncation limit:

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "SaaS" --domain style --max-length 0
#                                                                               ^ 0 = unlimited
```

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=nextlevelbuilder/ui-ux-pro-max-skill&type=Date)](https://star-history.com/#nextlevelbuilder/ui-ux-pro-max-skill&Date)

## License

This project is licensed under the [MIT License](LICENSE).

## Compatible Agents

This skill works with:
- [Claude Code](https://claude.com/product/claude-code)
- [AdaL](https://sylph.ai/) - Self-evolving AI coding agent ([Docs](https://docs.sylph.ai/) | [GitHub](https://github.com/SylphAI-Inc/adal-cli))
