# PDF Page Selection

Save tokens by selectively reading specific pages from large PDFs.

## Overview

When working with large PDF documents (>10 pages), reading the entire document can consume significant API tokens. The PDF page selection utility allows you to:

- Automatically detect PDF page counts
- Ask users which pages they want to extract
- Generate page range strings compatible with Claude Code's Read tool

## Usage in Workflows

### Bash (orchestrate.sh)

```bash
# Method 1: Get page count only
page_count=$(get_pdf_page_count "/path/to/document.pdf")
echo "PDF has $page_count pages"

# Method 2: Ask user for page selection
pages=$(ask_pdf_page_selection "/path/to/document.pdf" "$page_count")

# Method 3: Convenience wrapper (combines both)
pages=$(process_pdf_with_selection "/path/to/document.pdf")
# Returns: "" (all pages), "1-10", "5", "1-5,10-15", etc.

# Use with Claude Code agent
if [[ -n "$pages" ]]; then
    # Pass to Claude Code with page parameter
    echo "Reading pages: $pages"
else
    echo "Reading all pages"
fi
```

### Integration in Extract Command

Add to `.claude/commands/extract.md`:

```javascript
// Before processing PDF files
if (filePath.endsWith('.pdf')) {
  const pageCount = await getPdfPageCount(filePath);

  if (pageCount > 10) {
    console.log(`📄 Large PDF detected: ${pageCount} pages`);

    const pages = await AskUserQuestion({
      questions: [{
        question: `This PDF has ${pageCount} pages. Which pages would you like to extract?`,
        header: "Page Selection",
        multiSelect: false,
        options: [
          {label: "First 10 pages", description: "Quick overview (pages 1-10)"},
          {label: "Last 10 pages", description: "Recent content (pages " + (pageCount-9) + "-" + pageCount + ")"},
          {label: "All pages", description: "Full document (may use many tokens)"},
          {label: "Custom range", description: "Specify page numbers"}
        ]
      }]
    });

    // Convert answer to page parameter
    let pageParam = "";
    if (pages === "First 10 pages") {
      pageParam = "1-10";
    } else if (pages === "Last 10 pages") {
      pageParam = `${pageCount-9}-${pageCount}`;
    } else if (pages === "Custom range") {
      pageParam = await askForInput("Enter page range (e.g., 1-5, 10, 15-20):");
    }
    // else "All pages" - use empty string

    // Use with Read tool
    const content = Read(filePath, { pages: pageParam });
  }
}
```

### Integration in Research Workflow

Add to `.claude/skills/skill-deep-research.md`:

```markdown
## PDF Handling

When research prompts reference PDF files:

1. Check file size/page count before reading
2. For PDFs > 10 pages, ask which sections to focus on
3. Use page selection to minimize token usage

Example workflow:
\`\`\`bash
# In orchestrate.sh research workflow
if [[ -f "$research_file" && "$research_file" =~ \.pdf$ ]]; then
    pages=$(process_pdf_with_selection "$research_file")

    # Pass page selection to agent
    if [[ -n "$pages" ]]; then
        prompt="Analyze pages $pages of $research_file..."
    else
        prompt="Analyze $research_file..."
    fi

    run_agent_sync "gemini" "$prompt" 180
fi
\`\`\`
```

## Available Tools

The utility supports multiple PDF page counting methods:

| Tool | Platform | Installation |
|------|----------|--------------|
| `pdfinfo` | Linux/macOS | `brew install poppler` or `apt-get install poppler-utils` |
| `mdls` | macOS | Built-in (uses Spotlight metadata) |
| `qpdf` | Linux/macOS | `brew install qpdf` or `apt-get install qpdf` |

At least one tool must be available for page counting. If no tools are found, the utility returns 0 pages.

## Page Range Format

Page ranges use the same format as Claude Code's Read tool:

- `"1-10"` - Pages 1 through 10
- `"5"` - Just page 5
- `"1-5,10-15"` - Pages 1-5 and 10-15
- `""` (empty) - All pages

## Configuration

### Page Threshold

By default, PDFs with ≤10 pages are read entirely. Change the threshold:

```bash
# Use 20-page threshold instead
pages=$(ask_pdf_page_selection "/path/to/file.pdf" "$page_count" 20)

# Or with wrapper
pages=$(process_pdf_with_selection "/path/to/file.pdf" 20)
```

### Non-Interactive Mode

For CI/CD or automated workflows, set page ranges programmatically:

```bash
# Skip interactive prompts
PAGES="1-10"
export PAGES

# Or pass directly to agent
run_agent_sync "codex" "Analyze pages 1-10 of report.pdf" 120
```

## Debug Mode

Enable debug logging to troubleshoot PDF processing:

```bash
OCTOPUS_DEBUG=1 ./scripts/orchestrate.sh research "analyze report.pdf"
```

Debug output includes:
- PDF file path
- Page count detection method used
- User's page selection
- Final page range passed to agent

## Examples

### Example 1: Research Workflow

```bash
#!/usr/bin/env bash
# Research workflow with PDF page selection

research_file="research/paper.pdf"

if [[ -f "$research_file" && "$research_file" =~ \.pdf$ ]]; then
    # Get page count
    page_count=$(get_pdf_page_count "$research_file")

    if [[ "$page_count" -gt 10 ]]; then
        echo "Large PDF detected: $page_count pages"

        # Ask user for pages
        pages=$(ask_pdf_page_selection "$research_file" "$page_count")

        echo "Researching pages: ${pages:-all}"

        # Pass to research agent
        ./scripts/orchestrate.sh research "Analyze ${pages:+pages $pages of }$research_file"
    else
        ./scripts/orchestrate.sh research "Analyze $research_file"
    fi
fi
```

### Example 2: Extract Workflow

```bash
#!/usr/bin/env bash
# Extract workflow with PDF documentation

doc_file="docs/architecture.pdf"

if [[ -f "$doc_file" && "$doc_file" =~ \.pdf$ ]]; then
    # Use convenience wrapper
    pages=$(process_pdf_with_selection "$doc_file")

    # Extract architecture from selected pages
    if [[ -n "$pages" ]]; then
        ./scripts/orchestrate.sh extract "$doc_file" \
            --pages "$pages" \
            --mode product \
            --depth standard
    else
        ./scripts/orchestrate.sh extract "$doc_file" \
            --mode product \
            --depth standard
    fi
fi
```

### Example 3: Batch Processing

```bash
#!/usr/bin/env bash
# Process multiple PDFs with same page range

page_range="1-5"  # First 5 pages of each PDF

for pdf in docs/*.pdf; do
    echo "Processing: $pdf (pages $page_range)"
    ./scripts/orchestrate.sh research "Summarize pages $page_range of $pdf"
done
```

## Best Practices

1. **Start Small**: For unfamiliar PDFs, start with first 10 pages to understand structure
2. **Check TOC**: If PDF has table of contents, read that first to identify relevant sections
3. **Token Budget**: Estimate ~750 tokens per page for typical documents
4. **Quality**: Reading fewer pages with high-quality prompts beats reading entire document with generic prompts
5. **Iteration**: Extract in phases - overview first, then deep-dive on specific sections

## Token Savings

Estimated token savings by page selection:

| PDF Size | All Pages | First 10 Pages | Savings |
|----------|-----------|----------------|---------|
| 20 pages | ~15,000 tokens | ~7,500 tokens | 50% |
| 50 pages | ~37,500 tokens | ~7,500 tokens | 80% |
| 100 pages | ~75,000 tokens | ~7,500 tokens | 90% |

*Assumes ~750 tokens per page for standard documents*

## Troubleshooting

### "Could not determine PDF page count"

**Cause**: No PDF tools installed

**Solution**: Install poppler-utils or qpdf:
```bash
# macOS
brew install poppler

# Linux (Debian/Ubuntu)
sudo apt-get install poppler-utils

# Linux (Fedora/RHEL)
sudo dnf install poppler-utils
```

### "Invalid page range format"

**Cause**: Page range doesn't match expected format

**Solution**: Use formats like:
- Single page: `5`
- Range: `1-10`
- Multiple ranges: `1-5,10-15`
- All pages: `all` or leave empty

### Page selection not prompting

**Cause**: PDF is below threshold (≤10 pages by default)

**Solution**: Lower the threshold or force prompting:
```bash
pages=$(ask_pdf_page_selection "$pdf_file" "$page_count" 5)  # 5-page threshold
```

## Related Features

- **Debug Mode**: See [DEBUG_MODE.md](DEBUG_MODE.md)
- **Extract Workflow**: See `.claude/commands/extract.md`
- **Research Skills**: See `.claude/skills/skill-deep-research.md`

## Version History

- **v7.23.0**: Initial implementation of PDF page selection utility
  - `get_pdf_page_count()` function
  - `ask_pdf_page_selection()` function
  - `process_pdf_with_selection()` wrapper
  - Multi-tool support (pdfinfo, mdls, qpdf)
  - Debug mode integration
