# Claude Octopus v7.25.0 Release Notes

**Release Date:** February 3, 2026

## Overview

Version 7.25.0 introduces three major features focused on **monitoring, debugging, and token optimization**. This release improves observability, troubleshooting capabilities, and cost efficiency without breaking any existing workflows.

## 🎯 Key Features

### 1. Task Metrics Integration

Track real-time task progress with comprehensive metrics and analytics.

**What's New:**
- Task count tracking (completed, pending, in_progress)
- Task duration metrics (min, max, average, median)
- Integration with Claude Code v2.1.16+ native task system
- JSON and human-readable reporting formats

**Usage:**
```bash
# Get task metrics
./scripts/orchestrate.sh metrics

# View in JSON format
./scripts/orchestrate.sh metrics --format json
```

**Benefits:**
- Monitor workflow progress in real-time
- Identify bottlenecks with duration analytics
- Better visibility into multi-agent orchestration
- Native Claude Code UI integration

**Implementation:** `scripts/state-manager.sh`

---

### 2. Debug Mode

Comprehensive debug logging system for troubleshooting and development.

**What's New:**
- `OCTOPUS_DEBUG` environment variable
- `--debug` command-line flag
- Debug functions: `debug_log()`, `debug_var()`, `debug_section()`
- Strategic logging at startup, provider detection, and agent execution
- Enhanced error messages with full context

**Usage:**
```bash
# Environment variable
export OCTOPUS_DEBUG=1
./scripts/orchestrate.sh <command>

# Command-line flag
./scripts/orchestrate.sh --debug <command>

# Inline
OCTOPUS_DEBUG=1 ./scripts/orchestrate.sh <command>
```

**Debug Output Example:**
```
[DEBUG] ═══ Orchestrate.sh starting ═══
[DEBUG] COMMAND=probe
[DEBUG] OCTOPUS_DEBUG=1
[DEBUG] WORKSPACE_DIR=/Users/chris/.claude-octopus
[DEBUG] PROJECT_ROOT=/Users/chris/git/my-project

[DEBUG] ═══ Detecting AI providers ═══
[DEBUG] Checking for Codex CLI...
[DEBUG] ✓ Codex CLI found with auth: oauth
[DEBUG] Checking for Gemini CLI...
[DEBUG] ✓ Gemini CLI found with auth: oauth
```

**Benefits:**
- Troubleshoot provider detection issues
- Debug agent execution failures
- Understand workflow execution flow
- Zero performance cost when disabled

**Documentation:** `docs/DEBUG_MODE.md`

---

### 3. PDF Page Selection

Smart token optimization for large PDF documents.

**What's New:**
- Automatic PDF page counting (pdfinfo, mdls, qpdf support)
- Interactive page selection for PDFs >10 pages
- Integrated with extract and research workflows
- Token cost estimates in user prompts
- Configurable page threshold

**Usage:**

**Automatic (Extract Workflow):**
```bash
/octo:extract ./docs/architecture.pdf
# → Detects: 45 pages
# → Prompts: "Which pages to extract?"
# → Options: First 10, Specific range, All pages
# → Shows: "Reading all pages may use 33,750 tokens (~34 API calls)"
```

**Manual (Bash):**
```bash
# Get page count
pages=$(process_pdf_with_selection "/path/to/document.pdf")

# Use with research
./scripts/orchestrate.sh research "Analyze pages $pages of document.pdf"
```

**Token Savings:**

| PDF Size | All Pages | First 10 Pages | Savings |
|----------|-----------|----------------|---------|
| 20 pages | 15,000 tokens | 7,500 tokens | **50%** |
| 50 pages | 37,500 tokens | 7,500 tokens | **80%** |
| 100 pages | 75,000 tokens | 7,500 tokens | **90%** |

**Benefits:**
- Dramatically reduce token costs for large PDFs
- Focus on relevant sections instead of entire documents
- Better iterative research workflow
- Clear cost visibility for users

**Documentation:** `docs/PDF_PAGE_SELECTION.md`

---

## 📊 Impact Summary

| Improvement Area | Feature | Impact |
|------------------|---------|--------|
| **Monitoring** | Task Metrics | Real-time workflow visibility |
| **Debugging** | Debug Mode | Faster troubleshooting |
| **Cost** | PDF Pages | 50-90% token savings on PDFs |
| **UX** | All Features | Better transparency and control |

---

## 🔄 Upgrade Guide

### Requirements

- Claude Code v2.1.16+ (for task metrics integration)
- Bash 4.0+
- Optional: PDF tools for page counting (pdfinfo, mdls, or qpdf)

### Installation

```bash
# Update to latest version
cd ~/.claude/plugins/cache/nyldn-plugins/claude-octopus
git pull origin main

# Or reinstall via Claude Code plugin manager
```

### Configuration

**Enable Debug Mode (Optional):**
```bash
# Add to ~/.bashrc or ~/.zshrc for persistent debug mode
export OCTOPUS_DEBUG=1

# Or use inline for ad-hoc debugging
OCTOPUS_DEBUG=1 ./scripts/orchestrate.sh <command>
```

**Install PDF Tools (Optional):**
```bash
# macOS
brew install poppler  # Provides pdfinfo

# Linux (Debian/Ubuntu)
sudo apt-get install poppler-utils

# Linux (Fedora/RHEL)
sudo dnf install poppler-utils
```

### Verification

```bash
# Test debug mode
./scripts/orchestrate.sh --debug help | grep DEBUG

# Test PDF page counting (if PDF tools installed)
# This will only work if you have a test PDF
# get_pdf_page_count "/path/to/test.pdf"

# Test task metrics
./scripts/orchestrate.sh metrics
```

---

## 🔧 Technical Details

### New Functions (orchestrate.sh)

**Debug Mode:**
- `debug_log()` - Log debug messages with timestamps
- `debug_var()` - Display variable names and values
- `debug_section()` - Mark debug sections visually

**PDF Page Selection:**
- `get_pdf_page_count()` - Detect PDF page counts
- `ask_pdf_page_selection()` - Interactive page range prompting
- `process_pdf_with_selection()` - Convenience wrapper

**State Management:**
- Enhanced `get_task_metrics()` with duration analytics
- Task status aggregation functions

### Modified Files

- `scripts/orchestrate.sh` - Core logic additions
- `scripts/state-manager.sh` - Task metrics implementation
- `.claude/commands/extract.md` - PDF page selection integration
- `.claude/skills/skill-deep-research.md` - PDF handling documentation
- `package.json` - Version bump to 7.25.0
- `CHANGELOG.md` - Complete feature documentation

### New Documentation

- `docs/DEBUG_MODE.md` - Debug mode usage guide
- `docs/PDF_PAGE_SELECTION.md` - PDF optimization guide
- `RELEASE_NOTES_7.25.0.md` - This file

### Test Coverage

- `tests/test-debug-mode.sh` - Debug functionality tests
- `tests/test-pdf-pages.sh` - PDF page selection tests
- Syntax validation for all new bash functions

---

## 🐛 Known Issues

### PDF Page Counting

**Issue:** Page count returns 0 if no PDF tools installed

**Workaround:** Install at least one tool:
```bash
brew install poppler      # macOS
apt-get install poppler-utils  # Linux
```

**Behavior:** PDFs will default to reading all pages if page count is 0

### Debug Mode Output

**Issue:** Debug output may be verbose for long-running workflows

**Workaround:** Pipe to file or use grep to filter:
```bash
OCTOPUS_DEBUG=1 ./scripts/orchestrate.sh research "X" 2>&1 | tee debug.log
```

---

## 🚀 What's Next

### Planned for v7.26.0+

- **Enhanced Metrics Dashboard**: Visual progress bars and charts
- **PDF Caching**: Cache extracted page content for repeated analysis
- **Smart Page Recommendations**: AI-suggested page ranges based on TOC
- **Metrics Export**: CSV/JSON export for external analysis tools
- **Debug Profiles**: Pre-configured debug levels (minimal, standard, verbose)

---

## 📚 Resources

### Documentation

- [CHANGELOG.md](./CHANGELOG.md) - Full version history
- [DEBUG_MODE.md](./docs/DEBUG_MODE.md) - Debug mode guide
- [PDF_PAGE_SELECTION.md](./docs/PDF_PAGE_SELECTION.md) - PDF optimization guide
- [README.md](./README.md) - Project overview

### Support

- **Issues:** https://github.com/nyldn/claude-octopus/issues
- **Discussions:** https://github.com/nyldn/claude-octopus/discussions
- **Documentation:** https://github.com/nyldn/claude-octopus/tree/main/docs

---

## 🙏 Acknowledgments

This release was developed with a focus on user feedback around:
- Need for better debugging capabilities
- Token cost optimization for document analysis
- Progress visibility in complex workflows

Thank you to all contributors and users who provided feedback!

---

## 📝 License

MIT License - See [LICENSE](./LICENSE) for details

---

**Version:** 7.25.0
**Release Date:** February 3, 2026
**Git Tag:** v7.25.0
