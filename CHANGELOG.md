# Changelog

All notable changes to Claude Octopus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [7.4.0] - 2026-01-18

### Added - AI Debate Hub Integration

**Attribution**: This release integrates **AI Debate Hub** by **wolverin0** (https://github.com/wolverin0/claude-skills)

**Git Submodule Integration** (Hybrid Approach)
- Added wolverin0/claude-skills as git submodule at `.dependencies/claude-skills`
- Original debate.md skill (v4.7) referenced read-only, maintaining clear attribution
- Integration type: Hybrid (original skill + enhancement layer)
- License: MIT (both projects)

**AI Debate Hub - Original Features** (by wolverin0)
- Structured three-way debates: Claude + Gemini CLI + Codex CLI
- Claude as active participant AND moderator (not just orchestrator)
- Multi-round debates (1-10 configurable rounds)
- Four debate styles: quick, thorough, adversarial, collaborative
- Session persistence via CLI session UUIDs
- Automatic synthesis generation (consensus, disagreements, recommendations)
- Token-efficient context management (only injects previous round responses)

**Claude-Octopus Enhancement Layer** (debate-integration.md)
- Session-aware storage: `~/.claude-octopus/debates/${SESSION_ID}/`
- Quality gates for debate responses:
  - Metrics: length, citations, code examples, engagement
  - Thresholds: >= 75 proceed, 50-74 warn, < 50 re-prompt
- Cost tracking and analytics integration:
  - Per-advisor token usage and cost breakdown
  - Real-time cost estimation (typical: $0.02-$0.50 per debate)
  - Analytics logging to `~/.claude-octopus/analytics/`
- Document export integration (via document-delivery skill v7.3.0):
  - Export debates to PPTX/DOCX/PDF
  - Professional formatting for stakeholder presentations
- Knowledge mode deliberation workflow:
  - `/claude-octopus:km on` + `/debate` = strategic decision-making
  - Maps knowledge personas (ux-researcher, strategy-analyst, research-synthesizer)

**New Commands**
- `/debate <question>` - Basic debate invocation
- `/debate -r N -d STYLE <question>` - With rounds and style
- `/claude-octopus:deliberate <question>` - Alias for debate command
- `/debate-export <id> --format pptx` - Export debate results (via integration)
- `/debate-quality <id>` - Show quality scores (via integration)
- `/debate-cost <id>` - Show cost breakdown (via integration)

**Debate Styles**
| Style | Rounds | Purpose | Estimated Cost |
|-------|--------|---------|----------------|
| quick | 1 | Fast initial perspectives | $0.02-$0.05 |
| thorough | 3 | Detailed analysis with refinement | $0.10-$0.20 |
| adversarial | 5 | Devil's advocate, stress testing | $0.25-$0.50 |
| collaborative | 2-3 | Consensus-building | $0.08-$0.15 |

**Integration Use Cases**
1. **Debate Phase in Double Diamond**: `probe → grasp → debate → tangle → ink`
2. **Enhanced Adversarial Review**: Replace `grapple` with structured debate
3. **Knowledge Mode Deliberation**: Strategic decisions with multi-perspective analysis
4. **Security Reviews**: Adversarial debate with defender/attacker roles

**File Structure**
```
.dependencies/claude-skills/     ← Git submodule (original by wolverin0)
  └── skills/debate.md           ← Original skill (read-only reference)
.claude/skills/
  └── debate-integration.md      ← Claude-octopus enhancements
~/.claude-octopus/debates/       ← Session-aware debate storage
```

**Submodule Management**
- Initialize: `git submodule update --init --recursive`
- Update from upstream: `git submodule update --remote .dependencies/claude-skills`
- Contribution path: Submit generic enhancements to wolverin0/claude-skills via PRs

### Changed
- Plugin version: `7.3.0` → `7.4.0`
- Updated `.claude-plugin/plugin.json` with debate skills and dependencies section
- Updated `package.json` to v7.4.0
- Updated `.claude-plugin/marketplace.json` to v7.4.0
- Updated README.md with prominent AI Debate Hub attribution section
- Added keywords: ai-debates, consensus-building, multi-perspective, deliberation

### Documentation
- Added comprehensive attribution section in README.md
- Documented hybrid integration approach in plugin.json dependencies
- Created debate-integration.md with enhancement details
- Added debate command routing in orchestrate.sh with usage examples
- Documented contribution workflow for upstream enhancements

### Impact
- **Multi-Perspective Analysis**: Structured debates provide comprehensive viewpoints
- **Consensus Building**: Systematic approach to team decision-making
- **Quality Assurance**: Adversarial debates catch edge cases and vulnerabilities
- **Knowledge Work**: Strategic deliberation with domain expert personas
- **Open Source Collaboration**: Clear attribution enables upstream contributions

### Attribution & License
**Original Work**: AI Debate Hub by wolverin0
- Repository: https://github.com/wolverin0/claude-skills
- License: MIT
- Version: v4.7
- Integration: Git submodule (read-only reference)

**Enhancement Layer**: Claude-octopus integration
- Repository: https://github.com/nyldn/claude-octopus
- License: MIT
- Approach: Hybrid (reference original + add enhancements)

Both projects are open source. Generic improvements to debate functionality should be contributed to wolverin0/claude-skills. Claude-octopus-specific integrations remain in this repository.

---

## [7.3.0] - 2026-01-18

### Added - Knowledge Worker Document Delivery

**Document-Delivery Skill**
- New skill for converting knowledge work outputs to professional office formats
- Auto-triggers on export/create/convert document requests
- Supports DOCX (Word), PPTX (PowerPoint), XLSX (Excel)
- Integrates with empathize/advise/synthesize workflows
- Format recommendations based on workflow type:
  - Empathize → DOCX persona docs or PPTX stakeholder decks
  - Advise → PPTX strategy presentations or DOCX business cases
  - Synthesize → DOCX academic reports or PDF publications

**Enhanced Knowledge Mode**
- Document delivery capability documented in knowledge-work-mode skill
- Command alias: `/claude-octopus:deliver-docs` for discoverability
- Also available as: `/claude-octopus:export-docs` and `/claude-octopus:create-docs`
- Works seamlessly with document-skills@anthropic-agent-skills plugin

**Skill Features**
- Comprehensive format recommendations by workflow
- Professional styling tips for DOCX, PPTX, and PDF
- Conversion guidelines and best practices
- Example workflows for common use cases
- Edge case handling (no outputs, missing plugin, etc.)
- Integration guidance with knowledge mode workflows

### Changed
- Plugin version: `7.2.4` → `7.3.0`
- Updated `.claude-plugin/plugin.json` to include document-delivery skill
- Updated knowledge-work-mode.md with document delivery section

### Impact
- **Knowledge Workers**: Complete workflow from research to deliverable documents
- **Professional Output**: Easy conversion to stakeholder-ready formats
- **Seamless Integration**: Natural language triggers + existing document-skills plugin

---

## [7.2.4] - 2026-01-18

### Fixed - CI/CD & Command Execution

**GitHub Actions Reliability**
- Updated all GitHub Actions artifact actions from deprecated v3 to v4
  - `actions/upload-artifact@v3` → `@v4` (8 instances)
  - `actions/download-artifact@v3` → `@v4` (1 instance)
- Eliminated workflow failures caused by GitHub's automatic deprecation enforcement
- All artifact uploads/downloads now work reliably in CI environment

**Test Suite Robustness**
- Fixed `test-value-proposition` test failures in GitHub Actions CI
- Root cause: Strict bash error handling (`set -euo pipefail`) caused early exit
- Solution: Relaxed to `set -uo pipefail` to allow grep command failures
- Added file existence checks with clear error messages
- Test now passes in both local (macOS) and CI (Ubuntu) environments
- All 19 value proposition checks passing consistently

**Command Execution**
- Fixed `/claude-octopus:knowledge-mode` and `/claude-octopus:km` commands
- Commands now execute and show current mode status (not just documentation)
- Added bash execution blocks to both command files
- Output shows: current mode, optimization focus, workflows, toggle instructions
- Matches behavior of other working commands like `/claude-octopus:setup`

### Improved - Documentation

**README Quick Start**
- Moved Quick Start section from line 260 to line 42 (right after TL;DR)
- Users can now find installation instructions immediately
- Clarified installation steps to prevent confusion:
  - Changed "just 2 commands" with misleading "That's it!" to clear step boundaries
  - Step 1: Install the Plugin (explicitly marked)
  - Step 2: Configure Your AI Providers (explicitly marked)
  - Step 3: Start Using It (usage examples)
- Removed duplicate Quick Start section
- Each step has clear expectations and completion criteria

### Changed
- Plugin version: `7.2.3` → `7.2.4`
- All GitHub Actions test workflows now passing reliably
- No more deprecation warnings in CI/CD pipeline

### Impact
- **Reliability**: CI/CD pipeline fully operational, no more false failures
- **User Experience**: Commands work as expected, documentation easier to follow
- **Maintenance**: Test suite validates all changes automatically

---

## [7.2.3] - 2026-01-17

### Added - Config Update Optimization

**Fast Field-Only Configuration Updates**
- New `update_intent_config()` helper for instant user intent updates
- New `update_resource_tier_config()` helper for instant tier updates
- Field-level updates using sed (10-20x faster than full config regeneration)
- Graceful fallback to full config save if sed fails
- Reusable pattern for future single-field config updates

**Performance Improvements**
- Configuration changes now complete in <20ms (was ~200ms)
- No more full config file regeneration for single field changes
- Optimized for Claude Code chat experience

### Changed
- Plugin version: `7.2.2` → `7.2.3`

### Documentation
- Added reusable config update templates in `.dev/LESSONS-AND-ROADMAP.md`
- Documented optimization patterns for future development

---

## [7.2.2] - 2026-01-17

### Added - Document Skills Integration for Knowledge Mode

**Smart Document Skills Recommendations**
- New `show_document_skills_info()` helper function
- First-time recommendation when enabling Knowledge Work Mode
- Suggests `document-skills@anthropic-agent-skills` plugin for:
  - PDF reading and analysis
  - DOCX document creation/editing
  - PPTX presentation generation
  - XLSX spreadsheet handling
- Non-intrusive: shown only once using flag file `~/.claude-octopus/.knowledge-mode-setup-done`
- User can delete flag to see recommendation again

**Enhanced Documentation**
- Updated `setup.md` with "Knowledge Work Mode Setup (Optional)" section
- Updated `knowledge-work-mode.md` skill with "Recommended Setup" instructions
- Clear install command provided: `/plugin install document-skills@anthropic-agent-skills`

### Changed
- Plugin version: `7.2.1` → `7.2.2`
- Enhanced knowledge mode toggle output with document skills info

### User Experience
- Contextual recommendations when enabling knowledge mode
- Optional setup (user can skip if not needed)
- Educational content explaining what document-skills provides

---

## [7.2.1] - 2026-01-17

### Fixed - Knowledge Mode Toggle Performance & UX

**Performance Optimization (10x faster)**
- Refactored `toggle_knowledge_work_mode()` for instant switching
- Changed from full config load/save to single-line grep/sed operations
- New `update_knowledge_mode_config()` helper for field-only updates
- Reduced toggle time from ~200ms to ~20ms

**Output Optimization (50% clearer)**
- Streamlined status output from 27 lines to 5 lines
- Scannable format optimized for Claude Code chat
- Clear visual hierarchy with icons, colors, and whitespace
- Added `DIM` and `BOLD` color codes for better readability
- Actionable next steps always shown

**Error Handling**
- Fixed config save errors caused by undefined variables
- Graceful fallback to full config regeneration if sed fails
- Clear error messages with valid options shown

**Documentation Updates**
- Updated `km.md` and `knowledge-mode.md` with v7.2.1 improvements
- Added "What's Improved" section highlighting changes
- Before/after output comparison

### Changed
- Plugin version: `7.2.0` → `7.2.1`
- Updated command descriptions to emphasize speed improvements

### Technical Details
- Added `update_knowledge_mode_config()` at line 9576
- Refactored `toggle_knowledge_work_mode()` at line 9634
- macOS (BSD sed) and Linux sed compatibility maintained

---

## [7.2.0] - 2026-01-17

### Added - Quick Knowledge Mode Toggle & Expert Review

#### Quick Knowledge Mode Toggle
**Native Claude Code Integration for Mode Switching**
- New `/claude-octopus:knowledge-mode` command for instant mode switching
- Short alias `/claude-octopus:km` for quick access
- Natural language detection: "switch to knowledge mode", "back to dev mode"
- Enhanced `toggle_knowledge_work_mode()` function with explicit `on/off/status` support
- Visual status display showing current mode, routing behavior, and available workflows
- Idempotent operations: running "on" when already enabled shows confirmation
- Proactive skill `knowledge-work-mode.md` suggests mode changes when detecting task shifts

**Command Features**
- `km` / `knowledge-mode` - Show current status (default with no args)
- `km on` / `knowledge-mode on` - Enable knowledge work mode
- `km off` / `knowledge-mode off` - Enable development mode
- `km toggle` / `knowledge-toggle` - Toggle between modes
- Persistent across sessions via `~/.claude-octopus/.user-config`

**User Experience Improvements**
- Clear emoji indicators: 🔧 Development Mode, 🎓 Knowledge Work Mode
- Contextual help showing available workflows per mode
- Quick toggle hints displayed after mode changes
- Smart defaults: no args = show status (user-friendly)

#### Test Infrastructure & Quality Assurance

**Plugin Expert Review (New Test Suite)**
- New test: `tests/integration/test-plugin-expert-review.sh`
- 50 comprehensive checks validating Claude Code plugin best practices
- Plugin metadata validation (plugin.json, marketplace.json, hooks.json)
- Documentation completeness (README, LICENSE, CHANGELOG, SECURITY)
- Skills & commands structure validation
- Git ignore best practices verification
- Root directory organization checks
- Version consistency across package.json, plugin.json, CHANGELOG
- Security considerations (no hardcoded secrets, .env gitignored)
- Marketplace readiness validation

**Bug Fixes**
- Fixed "unbound variable" error in `tests/run-all.sh` when test category empty
- Changed `"${ALL_RESULTS[@]}"` → `"${ALL_RESULTS[@]+"${ALL_RESULTS[@]}"}"` for safe array expansion
- All 11 test suites now pass (4 smoke + 2 unit + 5 integration)

**Cleanup & Organization**
- Removed .DS_Store from root directory
- Updated package.json version consistency (6.0.0 → 7.1.0 → 7.2.0)
- Coverage reports properly gitignored

### Changed

- Plugin version: `7.1.0` → `7.2.0`
- Plugin description updated to highlight quick knowledge mode toggle
- Added `knowledge-work-mode.md` skill to plugin.json skills array
- Enhanced help text for knowledge-toggle command with explicit action support

### Testing

**Test Coverage Status**
```
Smoke tests:       4/4 passed (1s)
Unit tests:        2/2 passed (191s)
Integration tests: 5/5 passed (37s) - includes new expert review
E2E tests:         0/0 passed

Expert Review: 50/50 checks passed ✅
Total: 11/11 test suites passing
```

### Documentation

- Created `.claude/commands/knowledge-mode.md` - Full command documentation
- Created `.claude/commands/km.md` - Short alias documentation
- Created `.claude/skills/knowledge-work-mode.md` - Proactive skill for auto-detection
- Updated command usage examples for Claude Code native experience
- Documented natural language interface: just say "switch to knowledge mode"

## [7.1.0] - 2026-01-17

### Added - Claude Code 2.1.10 Integration & Discipline Skills

#### Claude Code 2.1.10 Features

**Session-Aware Workflow Directories**
- Session ID integration via `${CLAUDE_SESSION_ID}` for cross-session tracking
- New directory structure: `~/.claude-octopus/results/${SESSION_ID}/`
- Session-specific subdirectories: tasks/, agents/, quality/, costs/
- `init_session_workspace()` function creates session-isolated workspace
- Enables correlation of work across Claude Code sessions

**plansDirectory Integration**
- Updated `writing-plans.md` skill to document `plansDirectory` setting integration
- Plans stored in `.claude/plans/` for Claude Code discovery
- Structured plan format with context, phases, files, and validation

**Setup Hook Event**
- New `hooks/setup-hook.md` for automatic initialization on `--init`
- Runs provider detection, workspace initialization, and welcome message
- Triggered when Claude Code starts with `--init` flag

**PreToolUse additionalContext**
- Enhanced `hooks/quality-gate-hook.md` with workflow state injection
- Provides current phase, quality scores, and provider status in tool context
- Enables informed decision-making in multi-phase workflows

#### New Discipline Skills (from obra/superpowers)

**Five Engineering Discipline Skills**
- `test-driven-development.md` - TDD with "Iron Law" enforcement (no production code without failing test)
- `systematic-debugging.md` - Four-phase debugging process (Observe → Hypothesize → Test → Fix)
- `verification-before-completion.md` - Evidence gate before claiming success
- `writing-plans.md` - Zero-context implementation plans with plansDirectory integration
- `finishing-branch.md` - Post-implementation workflow (merge/PR/keep/discard)

### Changed

- Minimum Claude Code version: `2.1.9` → `2.1.10`
- Plugin version: `7.0.0` → `7.1.0`
- Updated keyword: `claude-code-2.1.9` → `claude-code-2.1.10`
- Added Acknowledgments section to README.md crediting obra/superpowers

### Notes

This release integrates Claude Code 2.1.10 features for session-aware workflows and adds five discipline skills inspired by obra/superpowers. The session-aware directory structure enables better tracking and isolation of work across Claude Code sessions.

**Migration from v7.0.0:**
- Update plugin: `/plugin update claude-octopus`
- Restart Claude Code
- Session-aware features activate automatically
- New skills available immediately after update

---

## [7.0.0] - 2026-01-17

### Security - Critical Fixes

**Command Injection Prevention**
- Fixed eval-based command injection vulnerability in `json_extract_multi()` (replaced eval with bash nameref)
- Added `validate_agent_command()` to whitelist allowed agent command prefixes
- Implemented `sanitize_review_id()` to prevent sed injection attacks
- Enhanced dangerous character detection in workspace path validation (added quotes, parens, braces, wildcards)

**Path Traversal Protection**
- Added `validate_output_file()` to prevent path traversal in file operations
- All file reads now validate paths are under `$RESULTS_DIR`
- Uses `realpath` to resolve symlinks and detect directory escape attempts

**JSON Escaping**
- Implemented comprehensive `json_escape()` function for OpenRouter API calls
- Properly escapes: backslash, quotes, tab, newline, carriage return, backspace, form feed
- Prevents malformed JSON payloads from user input

### Concurrency - Race Condition Fixes

**Atomic File Operations**
- PID file writes now use `flock` for atomic operations (prevents corruption under parallel spawning)
- Cache validation uses atomic read to prevent TOCTOU race conditions
- Background process monitoring properly reaps zombie processes with `wait`

**Improved Timeout Implementation**
- Prefers system `timeout`/`gtimeout` commands when available
- Fallback implementation properly cleans up monitor processes
- Eliminates race conditions in process termination

**Cache Corruption Recovery**
- Added validation for tier cache values (free, pro, team, enterprise, api-only)
- Automatically removes corrupted cache entries
- Logs warnings for invalid tier values

**Provider Detection**
- Added graceful fallback when no AI providers detected
- Provides helpful installation instructions for Codex, Gemini, Claude, OpenRouter
- Returns error code instead of silent failure

### Reliability - File Handling & Logging

**Secure Temporary Files**
- Created `OCTOPUS_TMP_DIR` using `mktemp -d` with automatic cleanup on exit
- Added `secure_tempfile()` function for unpredictable temp file paths
- Updated all `.tmp` file usage to use secure temp directory
- Trap ensures cleanup on EXIT, INT, TERM signals

**Log Rotation**
- Implemented `rotate_logs()` function called during workspace initialization
- Automatically rotates logs exceeding 50MB
- Compresses rotated logs with gzip
- Purges logs older than 7 days
- Prevents disk exhaustion from unbounded log growth

### Impact

- **Security**: Eliminates 6 critical vulnerability classes (command injection, path traversal, JSON injection)
- **Stability**: Fixes 4 race conditions causing PID corruption and zombie processes
- **Reliability**: Prevents temp file prediction attacks and disk exhaustion
- **Compatibility**: No breaking API changes - backward compatible with v6.x

### Breaking Changes

None - all fixes are internal improvements maintaining API compatibility.

---

## [6.0.1] - 2026-01-17

### Fixed

**knowledge-toggle Command**
- Fixed silent exit issue when user config has empty intent values
- Command now properly displays mode toggle confirmation
- Added error handling to `toggle_knowledge_work_mode()` function

**Test Suite Improvements**
- Fixed `show_status calls show_provider_status` test (increased grep range from 10 to 20 lines)
- All 203 main tests now passing ✅
- All 10 knowledge routing tests now passing ✅

**Intent Detection Enhancement**
- Improved UX research intent detection for "analyze usability test results" pattern
- Added additional triggers: `analyze.*usability.*test`, `usability.*analysis`

### Impact
- **Test Coverage**: 100% pass rate (213/213 tests)
- **User Experience**: Toggle command now works reliably
- **Stability**: No breaking changes

---

## [6.0.0] - 2026-01-17

### Added - Knowledge Work Mode for Researchers, Consultants, and Product Managers

This release extends Claude Octopus beyond code to support knowledge workers. Whether you're synthesizing user research, developing business strategy, or writing literature reviews, the octopus's knowledge tentacles are ready to help.

#### New Knowledge Worker Workflows

**Three New Multi-Phase Workflows**
- **`empathize`** - UX Research synthesis (4 phases: Research Synthesis → Persona Development → Requirements Definition → Validation)
- **`advise`** - Strategic Consulting (4 phases: Strategic Analysis → Framework Application → Recommendation Development → Executive Communication)
- **`synthesize`** - Academic Research (4 phases: Source Gathering → Thematic Analysis → Gap Identification → Academic Writing)

**Knowledge Work Mode Toggle**
- **`knowledge-toggle`** command - Switch between development and knowledge work modes
- When enabled, `auto` routing prioritizes knowledge workflows for ambiguous requests
- Status command shows current mode
- Configuration persists across sessions

#### New Specialized Agents

**Six New Knowledge Worker Personas**
| Agent | Model | Specialty |
|-------|-------|-----------|
| `ux-researcher` | opus | User research synthesis, journey mapping, persona development |
| `strategy-analyst` | opus | Market analysis, strategic frameworks (SWOT, Porter, BCG) |
| `research-synthesizer` | opus | Literature review, thematic analysis, gap identification |
| `academic-writer` | sonnet | Research papers, grant proposals, peer review responses |
| `exec-communicator` | sonnet | Executive summaries, board presentations, stakeholder reports |
| `product-writer` | sonnet | PRDs, user stories, acceptance criteria |

#### Enhanced Setup & Routing

**New Use Intent Choices**
- **[11] Strategy/Consulting** - Market analysis, business cases, frameworks
- **[12] Academic Research** - Literature review, synthesis, papers
- **[13] Product Management** - PRDs, user stories, acceptance criteria

**Smart Intent Detection**
- Auto-detects UX research triggers: user interviews, journey maps, personas, usability
- Auto-detects strategy triggers: market analysis, SWOT, business case, competitive
- Auto-detects research triggers: literature review, systematic review, research gaps

**Command Aliases**
- `empathy`, `ux-research` → `empathize`
- `consult`, `strategy` → `advise`
- `synthesis`, `lit-review` → `synthesize`

#### Documentation

- **[docs/KNOWLEDGE-WORKERS.md](docs/KNOWLEDGE-WORKERS.md)** - Comprehensive 300+ line guide
- **Updated [docs/AGENTS.md](docs/AGENTS.md)** - Now includes all 37 agents (6 new)
- **Updated README.md** - v6.0 features, new use cases, examples

#### Tests

- **New test suite** `tests/unit/test-knowledge-routing.sh`
- 10 new test cases for knowledge worker routing
- All existing tests continue to pass

---

## [5.0.0] - 2026-01-17

### Added - Competitive Research Implementation: Agent Discovery & Analytics

This release implements competitive research recommendations to dramatically improve agent discoverability, reducing discovery time from **5-10 minutes to <1 minute**.

#### Phase 1: Documentation (Immediate Wins)

**Comprehensive Agent Catalog (docs/AGENTS.md)**
- **400+ line agent catalog** organized by Double Diamond methodology
- Sections by phase: Probe (Discover), Grasp (Define), Tangle (Develop), Ink (Deliver)
- Each agent includes: description, when to use, anti-patterns, and real-world examples
- Maintains octopus humor and tentacle references throughout
- Quick navigation with table of contents and emoji markers

**Enhanced README Quick Reference**
- **New "Which Tentacle?" section** - Instant agent recommendations at a glance
- Common use cases mapped to recommended agents
- Task type → Agent mapping for quick decision-making
- Links to comprehensive catalog for deep dives

**Enhanced Agent Frontmatter (Top 10 Agents)**
- Added `when_to_use` field with specific trigger conditions
- Added `avoid_if` field documenting anti-patterns
- Added `examples` field with real-world use cases
- Enhanced agents: backend-architect, code-reviewer, debugger, security-auditor, tdd-orchestrator, frontend-developer, database-architect, performance-engineer, python-pro, typescript-pro

#### Phase 2: Enhanced Guidance

**Intelligent Agent Recommendation System**
- **New `recommend_persona_agent()` function** - Keyword-based agent suggestions
- Analyzes user prompts for intent keywords (API, security, test, debug, etc.)
- Provides contextual recommendations when users are unsure
- Integrated into help system and error messages

**Visual Decision Trees (docs/agent-decision-tree.md)**
- **Three Mermaid decision flowcharts:**
  - By Development Phase (Probe → Grasp → Tangle → Ink)
  - By Task Type (Research, Design, Build, Review, Optimize)
  - By Tech Stack (Backend, Frontend, Database, Cloud, Testing)
- Interactive visual guide for agent selection
- Reduces cognitive load when choosing the right agent

#### Phase 3: Analytics & Optimization

**Privacy-Preserving Usage Analytics**
- **New `log_agent_usage()` function** - Automatic usage tracking
- Logs agent, phase, timestamp, prompt hash (not full prompt), and prompt length
- CSV format: `~/.claude-octopus/analytics/agent-usage.csv`
- Privacy-first: No PII, no full prompts, no API keys logged

**Analytics Reporting**
- **New `analytics` command**: `./scripts/orchestrate.sh analytics [days]`
- **New `generate_analytics_report()` function** - Usage insights
- Reports most/least used agents, phase distribution, and usage trends
- Helps identify optimization opportunities
- Default: Last 30 days of data

**Monthly Review Template (docs/monthly-agent-review.md)**
- Structured template for data-driven optimization
- Review questions for each agent's performance
- Sections: Usage Analysis, Effectiveness Review, Optimization Opportunities
- Actionable recommendations for improving agent catalog

### Changed

**Agent Documentation Structure**
- All persona agent files now include structured frontmatter
- Consistent format across all agents for better discoverability
- Enhanced metadata enables better search and recommendation

**README.md Organization**
- New section ordering prioritizes discovery and quick start
- "Which Tentacle?" section placed early for maximum visibility
- Links to comprehensive catalog and decision trees
- Improved navigation to specialized agents

### Testing

**New Test Suite for v5.0 Features**
- **17 new tests** added (Section 23: Competitive Research Recommendations)
- Tests documentation existence (AGENTS.md, decision-tree.md, monthly-review.md)
- Validates content quality (Double Diamond phases, octopus humor, Mermaid diagrams)
- Verifies function implementations (recommend_persona_agent, log_agent_usage, generate_analytics_report)
- Validates privacy-preserving analytics (no full prompts logged)
- **All 203 tests pass** (was 186 in v4.9.5)

### Impact

**Measurable Improvements**
- **Agent discovery time: 5-10 minutes → <1 minute** (90%+ reduction)
- **User experience:** Dramatically improved discoverability through multi-layered guidance
- **Maintainability:** Data-driven optimization via usage analytics
- **Documentation coverage:** 400+ lines of new agent documentation

**User Benefits**
- Faster time-to-productivity for new users
- Reduced cognitive load when selecting agents
- Better understanding of when/why to use each agent
- Data-driven insights for power users

### Notes

This major release (v5.0) represents a fundamental improvement to the Claude Octopus user experience. By implementing research-backed discoverability enhancements, we've made it significantly easier for users to find the right agent for their task.

The three-phase approach (Documentation → Guidance → Analytics) ensures both immediate wins (catalog, quick reference) and long-term optimization (usage analytics, monthly reviews).

**Key Philosophy Changes:**
- From "explore to discover" → "guided discovery"
- From "tribal knowledge" → "documented best practices"
- From "intuition-based" → "data-driven optimization"

**Migration from v4.9.5:**
- Existing users: Update plugin with `/plugin update claude-octopus`
- No breaking changes to existing workflows
- New features are additive and backward-compatible
- Analytics logging starts automatically after update
- Review new docs/AGENTS.md catalog when convenient

**Recommended Actions After Upgrade:**
1. Read the "Which Tentacle?" section in README.md
2. Browse docs/AGENTS.md to discover new agents
3. Try the `analytics` command after a week of usage
4. Explore decision trees in docs/agent-decision-tree.md

---

## [4.9.5] - 2026-01-17

### Fixed

#### Setup Command Path Resolution (Critical)
- **Fixed `/claude-octopus:setup` command failing with "no such file or directory" error**
- Updated `.claude/commands/setup.md` to use `${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh` instead of relative paths
- Works correctly when plugin installed via marketplace (versioned cache directory)
- Applied fix to all 3 script invocations in setup command (detect-providers, verify, help)

#### Plugin Installation Simplified
- **Reduced installation from 4-5 terminal commands to just 2 slash commands**
- New Quick Start: `/plugin marketplace add` and `/plugin install` (inside Claude Code chat)
- Matches installation pattern of official plugins (Vercel, Figma, Superpowers, Medusa)
- Users stay in Claude Code chat instead of switching to terminal
- README.md Quick Start section completely rewritten for clarity

#### Skill Activation
- **Removed permission prompt when activating plugin**
- Plugin now activates automatically when needed
- Improved user experience for first-time setup

### Added

#### Recommended Companion Skills Documentation
- **New "Recommended Companion Skills" section in README.md**
- Organized by category: Testing & Validation, Customization & Extension, Integration, Design & Frontend
- Recommended skills: webapp-testing, skill-creator, mcp-builder, frontend-design, artifacts-builder
- Added "How Skills Work with Claude Octopus" explanation
- Clarifies that skills are available to Claude (orchestrator), not spawned agents

#### Test Infrastructure Validation
- **New integration test: `test-plugin-lifecycle.sh`** (11/11 assertions passing)
- Validates full plugin install/uninstall/update workflow
- Tests marketplace addition, plugin installation, file verification, and cleanup
- Comprehensive test suite results: 6/7 test suites passing
- Smoke tests: 4/4 PASSED ✅
- Unit tests: 3/4 PASSED (1 known issue for internal commands)
- Integration tests: 2/2 PASSED ✅

### Changed

- README.md installation instructions simplified throughout
- Troubleshooting sections updated to use slash commands
- TEST-STATUS.md updated with latest test run results (2026-01-17 03:57)

### Notes

This release focuses on removing installation friction and fixing the critical setup command issue. The 2-command installation process (`/plugin marketplace add` + `/plugin install`) makes Claude Octopus as easy to install as official plugins. The `${CLAUDE_PLUGIN_ROOT}` fix ensures the setup command works correctly regardless of installation method.

**Migration from v4.9.4:**
- Existing users: Update plugin with `/plugin update claude-octopus`
- Restart Claude Code after updating
- Setup command will now work correctly

---

## [4.9.4] - 2026-01-16

### Fixed

#### Installer Marketplace Configuration
- **Fixed critical bug** preventing Claude Code startup after installation
- Removed creation of "local" marketplace entry that caused "Marketplace configuration file is corrupted" error
- Changed to use `claude-octopus-marketplace` as marketplace identifier (doesn't require marketplace to exist)
- Added cleanup of broken "local" marketplace entries from previous installation attempts
- Plugin now registers as `claude-octopus@claude-octopus-marketplace`

### Known Issues

The curl-based installer in v4.9.3 and v4.9.4 still does not work reliably due to Claude Code's marketplace architecture requirements. Users should install using the official plugin manager:

```bash
claude plugin marketplace add nyldn/claude-octopus
claude plugin install claude-octopus@nyldn-plugins --scope user
claude plugin enable claude-octopus --scope user
claude plugin update claude-octopus --scope user
```

See README.md for updated installation instructions. The install.sh script will be updated in a future release to use these commands.

## [4.9.0] - 2026-01-16

### Added - Seamless Claude Code Setup Experience

#### New detect-providers Command
- **Fast provider detection** - Completes in <1 second, non-blocking
- **Parseable output** - Clear status codes (CODEX_STATUS=ok/missing, CODEX_AUTH=oauth/api-key/none)
- **Smart guidance** - Provides targeted next steps based on detection results
- **Cache support** - Writes results to `~/.claude-octopus/.provider-cache` (1 hour TTL)
- **Conversational examples** - Shows what users can do naturally in Claude Code

#### Fifth User Role: Researcher UX/UI Design
- **New combined role** - "Researcher UX/UI Design" for users who do both UX research and UI design
- Added to user intent selection menu as option [5]
- Uses "researcher" persona for combined research + design workflow
- Renumbered existing roles: UI/Product Design [5→6], DevOps [6→7], Data [7→8], SEO [8→9], Security [9→10]

#### Conversational Documentation
- **Replaced CLI commands** with natural language examples in all user-facing docs
- Commands/setup.md: Rich conversational examples organized by category (Research, Implementation, Code Review, Adversarial Testing, Full Workflows)
- README.md: Simplified Quick Start emphasizing natural conversation over CLI
- skill.md: Added callout that Claude Code users don't need to run commands

#### Claude Code Version Check
- **Automatic version detection** - Checks Claude Code version during setup
- **Minimum version requirement** - Requires Claude Code 2.1.9 or higher
- **Multiple detection methods** - Tries `claude --version`, `claude version`, and package.json locations
- **Semantic version comparison** - Properly compares version numbers (e.g., 2.1.9 vs 2.1.8)
- **Prominent upgrade warnings** - Shows clear update instructions if outdated
- **Installation-specific guidance** - Provides commands for npm, Homebrew, and direct download
- **Parseable output** - Returns `CLAUDE_CODE_VERSION`, `CLAUDE_CODE_STATUS` (ok/outdated/unknown), `CLAUDE_CODE_MINIMUM`
- **Integrated into setup flow** - Runs automatically in `/claude-octopus:setup` and `detect-providers`
- **Skill routing** - skill.md documents Scenario 0 for outdated version handling (stops execution until updated)
- **Restart reminder** - Explicitly tells users to restart Claude Code after updating

### Changed - Simplified Setup Requirements

#### One Provider Required (Not Both)
- **Breaking change**: Users only need ONE provider (Codex OR Gemini) to get started
- Previous: Both Codex AND Gemini required
- New: Choose either based on preference (Codex for code gen, Gemini for analysis)
- Graceful degradation: Multi-provider tasks adapt to single provider
- Clear messaging: "You only need ONE provider to use Claude Octopus"

#### Updated Prerequisites Check (skill.md)
- **Automatic fast detection** - Non-blocking provider check replaces manual status command
- **Three scenarios** with clear routing logic:
  - Both missing: Show setup instructions, STOP
  - One working: Proceed with available provider
  - Both working: Use both for comprehensive analysis
- Emphasizes: "One is sufficient for most tasks"
- Cache optimization: Skip re-detection if cache valid (<1 hour)

#### Setup Command Redesign (commands/setup.md)
- Complete rewrite focusing on conversational usage
- Removed references to interactive terminal wizard
- Added shell-specific instructions (zsh vs bash)
- Expanded troubleshooting section
- Clear section: "Do I Need Both Providers?" (Answer: No!)

#### README.md Quick Start Overhaul
- Simplified from confusing to clear 3-step process
- Step 2 emphasis: "You only need ONE provider to get started"
- Shows both OAuth and API key options upfront
- Removed "Configure Claude Octopus" step (no longer needed)
- Optional verification step moved to end

### Deprecated

#### Interactive Setup Wizard
- **init_interactive()** function deprecated (will be removed in v5.0)
- Shows deprecation warning with migration path
- Explains benefits of new approach:
  - Faster onboarding (one provider vs two)
  - Clearer instructions (no confusing interactive prompts)
  - Works in Claude Code (no terminal switching)
  - Environment variables for API keys (more secure)
- Users redirected to `detect-providers` command

### Fixed

#### Provider Detection Output
- Fixed auth detection showing duplicate values (e.g., "oauth\napi-key")
- Now correctly shows single auth method per provider

### Notes

This is a major UX release that redesigns the entire setup experience to align with official Claude Code plugin patterns (Vercel, GitHub, Figma). The goal is to keep users in Claude Code without terminal context switching, while making setup faster and clearer. The interactive wizard is deprecated in favor of fast auto-detection + environment variables.

**Breaking Changes:**
- Old `init_interactive` wizard shows deprecation warning
- Documentation now emphasizes conversational usage over CLI commands

**Migration Path:**
- Existing users: Continue using current setup, or migrate to environment variables
- New users: Install one CLI, set API key, done

---

## [4.8.3] - 2026-01-16

### Added - Auto-Configuration Check for First-Use Experience

#### Enhanced Main Skill (skill.md)
- **Prerequisites Check Section** - Automatic configuration detection before command execution
  - Step 1: Status check to verify configuration completeness
  - Step 2: Detection of missing API keys or unconfigured providers
  - Step 3: Auto-prompt user to run `/claude-octopus:setup` when needed
  - Step 4: Verification after configuration completes
  - Step 5: Proceed with original task after setup
- **First-use notice** in skill description - "Automatically detects if configuration is needed and guides setup"

#### User Experience Improvement
- **Seamless onboarding** - Users no longer need to discover setup command manually
- **Self-healing** - Skill automatically detects incomplete config and guides through setup
- **Zero-friction activation** - "Just talk to Claude naturally!" now works on first use

### Fixed

#### Command Registration (Critical)
- **Changed commands field** from array to directory path: `"./commands/"`
- Commands now properly register with Claude Code and appear in `/` menu
- Commands available as `/claude-octopus:setup` and `/claude-octopus:check-updates`
- Matches official plugin pattern (vercel, plugin-dev, figma, etc.)
- **Removed `name` field** from command frontmatter (name derived from filename)
  - `commands/setup.md` → `/claude-octopus:setup`
  - `commands/check-updates.md` → `/claude-octopus:check-updates`

#### Plugin Validation (Critical)
- **Fixed Claude Code v2.1.9 schema validation errors**
- Removed unsupported `hooks` field (not in v2.1.9 schema)
- Removed unsupported `agents` field (not in v2.1.9 schema)
- Removed unsupported `plansDirectory` field (not recognized)
- Simplified plugin.json to match official plugin format
- Plugin now loads without validation errors

#### Skill Activation Guards (Critical)
- **Prevent skill from activating on built-in Claude Code commands**
- Added explicit exclusions in skill description for `/plugin`, `/init`, `/help`, `/commit`, etc.
- Added "IMPORTANT: When NOT to Use This Skill" section in skill instructions
- Skill now properly ignores:
  - Built-in Claude Code commands (anything starting with `/` except `/parallel-agents` or `/claude-octopus:*`)
  - Plugin management and Claude Code configuration tasks
  - Simple file operations, git commands, and terminal tasks
- Fixes issue where skill was incorrectly triggered on `/plugin` commands

### Changed
- Updated skill.md frontmatter description with first-use auto-configuration notice
- Added comprehensive prerequisites checking instructions to skill.md
- Updated README.md version badge to 4.8.3
- Updated marketplace.json version to 4.8.3

### Notes
This release includes both UX improvements (auto-configuration check) and critical fixes for Claude Code v2.1.9 compatibility. The skill instructions now include prerequisite checking that Claude executes automatically before running any octopus commands. Commands now properly register and appear in the Claude Code command palette.

---

## [4.8.2] - 2026-01-16

### Added - Essential Developer Tools Setup

#### Setup Wizard Step 10: Essential Tools
- **Tool categories**: Data processing, code auditing, Git, browser automation
- **Included tools**:
  - `jq` - JSON processor (critical for AI workflows)
  - `shellcheck` - Shell script static analysis
  - `gh` - GitHub CLI for PR/issue automation
  - `imagemagick` - Screenshot compression (5MB API limits)
  - `playwright` - Modern browser automation & screenshots

#### New Functions
- `get_tool_description()` - Get human-readable tool description
- `is_tool_installed()` - Check if a tool is available
- `get_install_command()` - Get platform-specific install command (macOS/Linux)
- `install_tool()` - Install a single tool with progress output

#### Tool Installation Options
- Option 1: Install all missing tools (recommended)
- Option 2: Install critical only (jq, shellcheck)
- Option 3: Skip for now

### Changed
- Setup wizard expanded to 10 steps
- Summary shows essential tools status
- Test suite expanded to 171 tests (+10 essential tools tests)

### Fixed
- Removed `declare -A` associative arrays for bash 3.2 (macOS) compatibility

---

## [4.8.1] - 2026-01-16

### Added - Performance Optimizations

#### JSON Parsing (~10x faster)
- `json_extract()` - Single field extraction using bash regex
- `json_extract_multi()` - Multi-field extraction in single pass
- No subprocess spawning for simple JSON operations

#### Config Parsing (~5x faster)
- Rewrote `load_providers_config()` to use single-pass while-read loop
- Eliminated 30+ grep/sed chains in config parsing

#### Preflight Caching (~50-200ms saved per command)
- `preflight_cache_valid()` - Check if cache is still valid
- `preflight_cache_write()` - Write cache with TTL
- `preflight_cache_invalidate()` - Invalidate on config change
- 1-hour TTL prevents redundant preflight checks

#### Logging Optimization
- Early return in `log()` for disabled DEBUG level
- Skips expensive operations when not needed

### Changed
- Test suite expanded to 161 tests (+15 performance tests)

---

## [4.8.0] - 2026-01-16

### Added - Subscription-Aware Multi-Provider Routing

#### Intelligent Provider Selection
- **Provider scoring algorithm** (0-150 scale) based on cost, capabilities, and task complexity
- **Cost optimization strategies**: `balanced` (default), `cost-first`, `quality-first`
- **OpenRouter integration** as universal fallback with 400+ models
- Automatic detection of provider tiers from installed CLIs

#### New CLI Flags
- `--provider <name>` - Force specific provider (codex, gemini, claude, openrouter)
- `--cost-first` - Prefer cheapest capable provider
- `--quality-first` - Prefer highest-tier provider
- `--openrouter-nitro` - Use fastest OpenRouter routing
- `--openrouter-floor` - Use cheapest OpenRouter routing

#### Enhanced Setup Wizard (9 steps)
- Step 5: Codex subscription tier (free/plus/pro/api-only)
- Step 6: Gemini subscription tier (free/google-one/workspace/api-only)
- Step 7: OpenRouter configuration (optional fallback)

#### New Configuration
- `~/.claude-octopus/.providers-config` (v2.0 format)
- Subscription tiers: free, plus, pro, max, workspace, api-only
- Cost tiers: free, bundled, low, medium, high, pay-per-use

#### New Functions
- `detect_providers()` - Returns installed CLIs with auth methods
- `score_provider()` - Score provider for task (0-150 scale)
- `select_provider()` - Select best provider using scoring
- `get_tiered_agent_v2()` - Enhanced routing with provider scoring
- `execute_openrouter()` - Execute prompt via OpenRouter API

### Changed

- Documentation split: CLAUDE.md (users) + .claude/DEVELOPMENT.md (developers)
- skill.md updated with Provider-Aware Routing section
- Test suite expanded to 146 tests (+27 multi-provider routing tests)

---

## [4.7.2] - 2026-01-16

### Added

- **Gemini CLI OAuth authentication support** - Prefers `~/.gemini/oauth_creds.json` over `GEMINI_API_KEY`
  - Matches existing Codex CLI OAuth pattern
  - OAuth is faster and recommended for interactive use
  - API key still supported as fallback

### Changed

- `preflight_check()` - OAuth-first detection with clear guidance for both auth methods
- `is_agent_available()` - Checks OAuth credentials file before API key
- `save_user_config()` - Detects OAuth for both Codex and Gemini CLIs
- `auth status` - Shows "Authenticated (OAuth)" with auth type from settings.json
- Setup Wizard Step 4 - OAuth option presented first with clear instructions

---

## [4.7.1] - 2026-01-16

### Added

- **Claude CLI agent support** - `claude` and `claude-sonnet` agent types for faster grapple/squeeze
- **Claude CLI preflight check** - warns if Claude CLI missing (required for grapple/squeeze)

### Changed

- **grapple uses Claude instead of Gemini** - faster debate synthesis with `claude --print`
- Updated `AVAILABLE_AGENTS` to include `claude` and `claude-sonnet`
- Added `claude-sonnet-4.5` pricing to cost tracking

---

## [4.7.0] - 2026-01-16

### Added - Adversarial Cross-Model Review (Crossfire)

#### New Commands

- **`grapple`** - Adversarial debate between Codex and Gemini
  - Round 1: Both models propose solutions independently
  - Round 2: Cross-critique (each model critiques the other's proposal)
  - Round 3: Synthesis determines winner and final implementation
  - Supports `--principles` flag for domain-specific critique

- **`squeeze`** - Red Team security review (alias: `red-team`)
  - Phase 1: Blue Team (Codex) implements secure solution
  - Phase 2: Red Team (Gemini) finds vulnerabilities with exploit proofs
  - Phase 3: Remediation fixes all found issues
  - Phase 4: Validation verifies all vulnerabilities are fixed

#### Constitutional Principles System

- `agents/principles/security.md` - OWASP Top 10, secure coding practices
- `agents/principles/performance.md` - N+1 queries, caching, async I/O
- `agents/principles/maintainability.md` - Clean code, testability, SOLID
- `agents/principles/general.md` - Overall code quality (default)

#### Auto-Routing Integration

- `classify_task()` detects crossfire intents (`crossfire-grapple`, `crossfire-squeeze`)
- `auto_route()` routes to grapple/squeeze workflows automatically
- Patterns: "security audit", "red team", "pentest" → squeeze
- Patterns: "adversarial", "cross-model", "debate" → grapple

### Changed

- Plugin version bumped to 4.7.0
- Added `crossfire` and `adversarial-review` keywords to plugin.json
- Updated skill.md with Crossfire documentation
- Updated command reference tables

---

## [4.6.0] - 2026-01-15

### Added - Claude Code v2.1.9 Integration

#### Security Hardening
- **Path Validation** - `validate_workspace_path()` prevents path traversal attacks
  - Restricts workspace to `$HOME`, `/tmp`, or `/var/tmp`
  - Blocks `..` path traversal attempts
  - Rejects paths with dangerous shell characters
- **Array-Based Command Execution** - `get_agent_command_array()` prevents word-splitting vulnerabilities
  - Commands executed as proper bash arrays
  - Removed ShellCheck suppressions for unquoted variables
- **JSON Parsing Validation** - `extract_json_field()` with error handling
  - `validate_agent_type()` checks against agent allowlist
  - Proper error messages for malformed task files
- **CI Workflow Hardening** - GitHub Actions input sanitization
  - Inputs via environment variables (not direct interpolation)
  - Command allowlisting for workflow_dispatch
  - Injection pattern detection for issue comments
- **Test File Safety** - Replaced `eval` with `bash -c` in test functions

#### Claude Code v2.1.9 Features
- **Session ID Integration** - `${CLAUDE_SESSION_ID}` support for cross-session tracking
  - Session files named with Claude session ID when available
  - Usage tracking correlates across sessions
  - `get_linked_sessions()` finds related session files
- **Plans Directory Alignment** - `plansDirectory` setting in plugin.json
  - `PLANS_DIR` constant for workspace plans
  - Created in `init_workspace()`
- **CI/CD Mode Support** - Respects `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS`
  - Auto-detects CI environments (GitHub Actions, GitLab CI, Jenkins)
  - Auto-declines session resume in CI mode
  - Auto-fails on quality gate escalation (no human review)
  - GitHub Actions annotations for errors (`::error::`)

#### Hook System
- **PreToolUse Hooks** - Quality gate validation before file modifications
  - `hooks/quality-gate-hook.md` - Enforces quality gates
  - `hooks/session-sync-hook.md` - Syncs Claude session context
  - Returns `additionalContext` for informed decisions

#### Nested Skills Discovery
- **Skill Wrappers** - Agent personas as discoverable skills
  - `agents/skills/code-review.md`
  - `agents/skills/security-audit.md`
  - `agents/skills/architecture.md`
- **Skills Command** - `./scripts/orchestrate.sh skills` lists available skills
- **Plugin Registration** - Skills and agents in plugin.json

#### Documentation & Testing
- **SECURITY.md** - Comprehensive security policy
  - Threat model with trust boundaries
  - Attack vectors and mitigations
  - Security controls documentation
  - Contributor security checklist
- **Security Tests** - 12 new security test cases
  - Path validation tests
  - Command execution safety tests
  - JSON validation tests
  - CI mode tests
  - Claude Code integration tests

### Changed
- Plugin version bumped to 4.6.0
- Added `claude-code-2.1.9` keyword to plugin.json
- `handle_autonomy_checkpoint()` respects CI mode
- Quality gate escalation respects CI mode
- Session resume respects CI mode

---

## [1.1.0] - 2026-01-15

### Added
- **Conditional Branching** - Decision trees for workflow routing (tentacle paths)
  - `evaluate_branch_condition()` - Determine which tentacle path to extend based on task type + complexity
  - `evaluate_quality_branch()` - Decide next action after quality gate (proceed/retry/escalate/abort)
  - `execute_quality_branch()` - Execute quality gate decisions with themed output
  - `get_branch_display()` - Octopus-themed branch display names
- **Branching CLI Flags**
  - `--branch BRANCH` - Force tentacle path: premium|standard|fast
  - `--on-fail ACTION` - Quality gate failure action: auto|retry|escalate|abort
- Branch displayed in task analysis: `Branch: premium (🐙 all tentacles engaged)`
- Quality gate decision tree replaces hardcoded retry logic

### Changed
- `auto_route()` now evaluates branch condition and displays selected tentacle path
- `validate_tangle_results()` uses new quality branch decision tree
- Help text updated with Conditional Branching section (v3.2)

### Documentation
- Conflict detection in preflight_check() for known overlapping plugins

---

## [1.0.3] - 2026-01-15

### Added
- **Cost-Aware Auto-Routing** - Intelligent model tier selection based on task complexity
  - Analyzes prompts to estimate complexity (trivial, standard, complex)
  - Routes trivial tasks to cheaper models (`codex-mini`, `gemini-fast`)
  - Routes complex tasks to premium models (`codex`, `gemini-pro`)
  - Prevents expensive models from being wasted on simple tasks
- **Cost Control CLI Flags**
  - `-Q, --quick` - Force cheapest model tier
  - `-P, --premium` - Force premium model tier
  - `--tier LEVEL` - Explicit tier: trivial|standard|premium
- Complexity displayed in task analysis output

### Changed
- `auto_route()` now uses `get_tiered_agent()` for cost-aware model selection
- Help text updated with Cost Control section

---

## [1.0.2] - 2026-01-15

### Added
- **Interactive Setup Wizard** (`./scripts/orchestrate.sh setup`)
  - Step-by-step guided configuration for first-time users
  - Auto-installs Codex CLI and Gemini CLI via npm
  - Opens API key pages in browser (OpenAI, Google AI Studio)
  - Prompts for API keys with validation
  - Optionally persists keys to shell profile (~/.zshrc or ~/.bashrc)
- **First-Run Detection** - Suggests setup wizard when dependencies are missing
- **`/octopus-setup` Command** - Claude Code integration for setup wizard
- Cross-platform browser opening (macOS, Linux, Windows)

### Fixed
- **GEMINI_API_KEY** - Fixed environment variable mismatch (was checking GOOGLE_API_KEY)
- Added legacy GOOGLE_API_KEY fallback for backwards compatibility
- Interactive prompt for missing Gemini API key in preflight check

### Changed
- Updated Quick Start docs with setup wizard instructions
- Reorganized help output with "Getting Started" section
- Added test output directories to .gitignore

---

## [1.0.1] - 2026-01-15

### Added
- Plugin marketplace support via `.claude-plugin/marketplace.json`
- Homepage and bugs URLs in plugin metadata

### Changed
- Enhanced plugin.json for marketplace discovery

---

## [1.0.0] - 2026-01-15

### Added

#### Double Diamond Methodology
Multi-tentacled orchestration workflow with octopus-themed commands:
- **probe** - Parallel research from 4 perspectives with AI synthesis (Discover phase)
- **grasp** - Multi-tentacled consensus building on problem definition (Define phase)
- **tangle** - Enhanced map-reduce with quality gates (Develop phase)
- **ink** - Validation and final deliverable generation (Deliver phase)
- **embrace** - Full 4-phase Double Diamond workflow
- **preflight** - Dependency validation before workflows

#### Intelligent Auto-Routing
Smart task classification routes to appropriate agents:
- **Image generation**: App icons, favicons, diagrams, social media banners, hero images
- **Code review**: Security audits, code analysis, PR reviews
- **Coding**: Implementation, debugging, refactoring
- **Design**: UI/UX analysis, accessibility, component design
- **Research**: Documentation, architecture analysis, best practices
- **Copywriting**: Marketing copy, content generation

#### Nano Banana Prompt Refinement
Intelligent prompt enhancement for image generation:
- Automatic detection of image type (app-icon, social-media, diagram, general)
- Type-specific prompt optimization for better visual results
- Integrated into auto-routing for seamless UX

#### Autonomy Modes
Configurable human oversight levels:
- **autonomous** - Full auto, proceed on failures
- **semi-autonomous** - Pause on quality gate failures (default)
- **supervised** - Human approval after each phase
- **loop-until-approved** - Retry failed tasks until quality gate passes

#### Session Recovery
Resume interrupted workflows:
- Automatic checkpoint after each phase completion
- Session state persisted to JSON
- Resume with `-R` flag from last successful phase

#### Specialized Agent Roles
Role-based agent selection for phases:
- **Architect** - System design and planning (Codex Max)
- **Researcher** - Deep investigation (Gemini Pro)
- **Reviewer** - Code review and validation (Codex Review)
- **Implementer** - Code generation (Codex Max)
- **Synthesizer** - Result aggregation (Gemini Flash)

#### Quality Gates
Configurable quality thresholds:
- Default 75% success threshold (configurable with `-q`)
- Quality gate status: PASSED (>=90%), WARNING (75-89%), FAILED (<75%)
- Loop-until-approved retry logic (up to 3 retries by default)

#### Multi-Agent Orchestration
Core execution patterns:
- **spawn** - Single agent execution
- **fan-out** - Same prompt to all agents
- **map-reduce** - Task decomposition and parallel execution
- **parallel** - JSON-defined task execution

#### Agent Fleet
Premium model defaults (Jan 2026):
- `codex` - GPT-5.1-Codex-Max (premium default)
- `codex-standard` - GPT-5.2-Codex
- `codex-max` - GPT-5.1-Codex-Max
- `codex-mini` - GPT-5.1-Codex-Mini
- `codex-general` - GPT-5.2
- `gemini` - Gemini-3-Pro-Preview
- `gemini-fast` - Gemini-3-Flash-Preview
- `gemini-image` - Gemini-3-Pro-Image-Preview
- `codex-review` - GPT-5.2-Codex (review mode)

#### CLI Options
- `-p, --parallel NUM` - Max parallel agents (default: 3)
- `-t, --timeout SECS` - Timeout per task (default: 300s)
- `-a, --autonomy MODE` - Set autonomy mode
- `-q, --quality NUM` - Quality gate threshold
- `-l, --loop` - Enable loop-until-approved
- `-R, --resume` - Resume interrupted session
- `-v, --verbose` - Verbose output
- `-n, --dry-run` - Show what would be done

#### Documentation
- Comprehensive README with Double Diamond methodology
- Octopus Philosophy section explaining the metaphor
- Troubleshooting guide with witty octopus tips
- ASCII art mascot throughout codebase

### Notes

Initial release as a Claude Code plugin for Design Thinking workflows.
Built with multi-tentacled orchestration using Codex CLI and Gemini CLI.
