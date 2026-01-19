# PowerPoint Setup Guide for Claude Octopus

Complete guide to set up PowerPoint/PPTX creation capabilities in claude-octopus.

## Quick Start (5 Minutes)

### Step 1: Install document-skills Plugin

```bash
/plugin install document-skills@anthropic-agent-skills
```

This plugin provides PPTX, DOCX, PDF, and XLSX creation capabilities.

### Step 2: Verify Installation

```bash
/plugin list | grep document-skills
```

You should see: `document-skills@anthropic-agent-skills`

### Step 3: Test PPTX Creation

Try creating a simple presentation:

```
"Create a 3-slide executive summary about AI adoption trends"
```

Claude will:
1. Use the exec-communicator persona
2. Apply the executive-summary template
3. Generate PPTX with proper formatting
4. Save to `~/.claude-octopus/exports/pptx/`

### Step 4: Explore Templates

```bash
cat templates/README.md
```

Review the 5 executive templates and choose the right one for your needs.

## Complete Setup

### 1. Verify Prerequisites

**Required:**
- Claude Code v2.1.10 or later
- Claude Pro/Max/Team/Enterprise (Skills not available on free plan)
- document-skills plugin installed

**Check Claude Code version:**
```bash
claude --version
```

**Check plugin:**
```bash
/plugin list
```

### 2. Template System

The template system is already set up in your repository:

```
templates/
├── README.md                        # Template documentation
├── pptx/                           # PowerPoint templates
│   ├── executive-summary.json      # 5-slide quick update
│   ├── board-presentation.json     # 10-slide board deck
│   ├── business-case.json          # 9-slide investment proposal
│   ├── status-update.json          # 6-slide progress report
│   └── workshop-readout.json       # 7-slide workshop synthesis
└── themes/
    └── executive-theme.json        # Professional design system
```

### 3. Integration Points

**skill-doc-delivery.md** - Already configured to:
- Detect when PPTX export is requested
- Suggest appropriate templates
- Apply executive themes
- Use document-skills /pptx skill

**exec-communicator persona** - Already configured to:
- Structure content using pyramid principle
- Apply BLUF (Bottom Line Up Front) formatting
- Select appropriate templates
- Ensure C-suite appropriate tone

### 4. Workflow Integration

```
Knowledge Mode → doc-delivery → Template Selection → PPTX Generation
     |              |                 |                    |
  /co:km on     skill triggers    Auto-suggested     document-skills
  "advise X"    when you say      based on          /pptx skill
                "export to pptx"   content type
```

## Usage Patterns

### Pattern 1: After Knowledge Mode Workflow

```bash
# Step 1: Run knowledge mode workflow
/co:km on
"Analyze the competitive landscape for our new product"

# Step 2: Export to PowerPoint
"Export this analysis to a board presentation"

# Result: 10-slide board deck with:
# - Executive summary
# - Market analysis
# - Competitive landscape
# - Strategic recommendations
```

### Pattern 2: From Markdown Files

```bash
# If you have existing markdown in ~/.claude-octopus/results/
"Convert the latest strategy synthesis to a business case presentation"

# Claude will:
# 1. Read the markdown file
# 2. Select business-case template
# 3. Apply executive theme
# 4. Generate PPTX
```

### Pattern 3: From Scratch

```bash
"Create an executive summary about our Q4 performance using these metrics:
- Revenue: $10M (120% of target)
- Customer growth: 2,500 new customers
- Churn: 2.5% (down from 3.8%)
- Key win: Enterprise deal with Fortune 500 company"

# Claude will:
# 1. Structure using pyramid principle
# 2. Apply executive-summary template
# 3. Create 5-slide deck
# 4. Lead with key message
```

## Template Selection Guide

| Your Need | Template | Slide Count | Best For |
|-----------|----------|-------------|----------|
| Quick update for exec | Executive Summary | 5 | Decision requests, briefs |
| Board meeting | Board Presentation | 10 | Quarterly reviews, governance |
| Seeking approval | Business Case | 9 | Investments, initiatives |
| Regular update | Status Update | 6 | Weekly/monthly progress |
| Workshop results | Workshop Readout | 7 | Synthesis, alignment |

## Customization

### Custom Templates

1. Copy an existing template:
```bash
cp templates/pptx/executive-summary.json templates/pptx/my-custom-template.json
```

2. Edit the structure:
```json
{
  "name": "My Custom Template",
  "description": "Custom template for specific use case",
  "slides": [
    {"number": 1, "type": "title", "title": "[Custom Title]"},
    {"number": 2, "type": "content", "title": "[Custom Content]"}
  ]
}
```

3. Reference in doc-delivery skill or use directly:
```bash
"Create a presentation using my-custom-template"
```

### Custom Themes

1. Copy the executive theme:
```bash
cp templates/themes/executive-theme.json templates/themes/my-brand-theme.json
```

2. Customize colors and fonts:
```json
{
  "name": "My Brand Theme",
  "colors": {
    "primary": "#YOUR_BRAND_COLOR",
    "secondary": "#YOUR_SECONDARY_COLOR"
  },
  "fonts": {
    "heading": {"family": "YourFont", "weight": "bold"}
  }
}
```

3. Reference in template .json files

## Best Practices

### Executive Communication

1. **Lead with conclusions** (Pyramid Principle)
2. **Use BLUF** (Bottom Line Up Front)
3. **Quantify everything** possible
4. **One main idea per slide**
5. **5-7 bullets maximum** per slide
6. **Prepare appendix** for Q&A

### Design Guidelines

**Do:**
- Use executive theme (navy blue, professional)
- Include slide numbers
- Add clear headlines that carry the message
- Use charts instead of tables
- Leave generous white space

**Don't:**
- Cram slides with text
- Use bright neon colors
- Add decorative graphics
- Mix multiple font families
- Use fancy transitions

## Troubleshooting

### Issue: document-skills not found

**Solution:**
```bash
/plugin install document-skills@anthropic-agent-skills
```

Restart Claude Code after installation.

### Issue: Template not applied

**Verify templates exist:**
```bash
ls templates/pptx/
```

**Check template reference:**
Ensure you're using the correct template name (e.g., "executive-summary", not "exec-summary").

### Issue: Formatting doesn't match

**Check theme:**
Verify template .json references correct theme:
```json
{
  "theme": "executive-theme"
}
```

**Verify theme exists:**
```bash
cat templates/themes/executive-theme.json
```

### Issue: Skills not available

**Check Claude subscription:**
Agent Skills require Claude Pro/Max/Team/Enterprise.

**Verify Claude Code version:**
```bash
claude --version  # Should be v2.1.10 or later
```

## Advanced Features

### Multi-Format Export

Export to multiple formats:
```bash
"Export this strategy to both PowerPoint and Word format"

# Claude will:
# 1. Generate PPTX using templates
# 2. Generate DOCX with detailed documentation
# 3. Save both to ~/.claude-octopus/exports/
```

### Persona-Driven Content

Leverage the exec-communicator persona:
```bash
"Create a board presentation about our AI strategy in exec-communicator style"

# Uses:
# - Pyramid principle structure
# - Executive-appropriate language
# - Data-driven approach
# - Clear calls to action
```

### Batch Processing

Process multiple outputs:
```bash
"Create status update presentations for all projects in my results folder"

# Claude will:
# 1. Read all markdown files
# 2. Identify project status content
# 3. Generate one PPTX per project
# 4. Apply status-update template to each
```

## Integration with Other Tools

### With Knowledge Mode

```bash
# Full workflow
/co:km on
"Research and analyze cloud migration strategies"

# After research completes
"Create a board presentation summarizing the analysis"

# Result: Professional board deck with research findings
```

### With AI Debate

```bash
"Run a debate about React vs Vue, then create an executive summary of the conclusions"

# Claude will:
# 1. Run AI Debate Hub (3-way debate)
# 2. Synthesize conclusions
# 3. Generate executive-summary PPTX
```

### With TDD/Debug Skills

```bash
"Debug this authentication issue, then create a status update for stakeholders"

# Claude will:
# 1. Debug systematically
# 2. Document findings
# 3. Generate status-update PPTX with:
#    - Issue description
#    - Root cause
#    - Fix implemented
#    - Validation results
```

## Examples

### Example 1: Quarterly Business Review

```bash
/co:km on
"Analyze Q4 performance: Revenue $15M (+25% YoY), Customer count 5,000 (+40%), Churn 2.1%"

"Export this to a board presentation"
```

**Output:**
- 10-slide board presentation
- Executive summary with BLUF
- Performance metrics with charts
- YoY comparisons
- Strategic implications
- Next quarter priorities

### Example 2: Investment Proposal

```bash
/co:km on
"Create business case for expanding to European market:
- Market size: €500M TAM
- Investment needed: $2M
- Expected ROI: 3x over 3 years
- Key risks: Regulatory, competition"

"Export as a business case presentation"
```

**Output:**
- 9-slide business case
- Financial model
- Market opportunity
- Implementation plan
- Risk assessment
- Clear recommendation

### Example 3: Weekly Status

```bash
"Create a status update presentation:
Progress: Launched beta, 100 users onboarded
Metrics: NPS 45, DAU/MAU 35%
Blockers: API rate limits, need infra support
Next: Scale to 500 users by EOW"
```

**Output:**
- 6-slide status update
- RAG status indicators
- Key metrics dashboard
- Blocker callouts
- Clear asks

## Getting Help

**Documentation:**
- `templates/README.md` - Template documentation
- `.claude/skills/skill-doc-delivery.md` - Skill documentation
- `agents/personas/exec-communicator.md` - Persona documentation

**Ask Claude:**
- "How do I use the board-presentation template?"
- "What's the difference between executive-summary and status-update?"
- "Show me best practices for executive presentations"
- "How can I customize the executive theme?"

**Support:**
- GitHub Issues: https://github.com/nyldn/claude-octopus/issues
- Documentation: Full docs in repo

## Next Steps

1. ✅ Verify document-skills installed
2. ✅ Test PPTX creation with simple example
3. ✅ Review template documentation
4. ✅ Run a knowledge mode workflow and export
5. ✅ Customize templates for your needs
6. ✅ Share feedback or contribute improvements

---

**Setup complete!** You're ready to create professional executive presentations with claude-octopus. 🐙

*PPTX Setup Guide for claude-octopus v7.7.0+*
