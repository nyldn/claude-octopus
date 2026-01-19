# PowerPoint Setup Validation Checklist

Run through this checklist to ensure PowerPoint/PPTX capabilities are fully functional.

## Prerequisites Validation

### ✅ 1. document-skills Plugin

**Check:**
```bash
/plugin list | grep document-skills
```

**Expected:** `document-skills@anthropic-agent-skills` appears in list

**If not installed:**
```bash
/plugin install document-skills@anthropic-agent-skills
```

**Status:** ⬜ Not installed | ⬜ Installed | ⬜ Verified

---

### ✅ 2. Template Files

**Check:**
```bash
ls -la templates/pptx/
```

**Expected:**
```
executive-summary.json
board-presentation.json
business-case.json
status-update.json
workshop-readout.json
```

**Status:** ⬜ Missing files | ⬜ All present | ⬜ Verified

---

### ✅ 3. Theme Files

**Check:**
```bash
cat templates/themes/executive-theme.json | jq '.name'
```

**Expected:** `"Executive Theme"`

**Status:** ⬜ Theme missing | ⬜ Theme present | ⬜ Verified

---

### ✅ 4. Documentation

**Check:**
```bash
cat templates/README.md | head -5
```

**Expected:** README header visible

**Status:** ⬜ Docs missing | ⬜ Docs present | ⬜ Verified

---

### ✅ 5. Integration Files

**Check:**
```bash
grep -n "Executive Templates" .claude/skills/skill-doc-delivery.md
```

**Expected:** Line number with "Executive Templates (NEW in v7.7.0)"

**Status:** ⬜ Not integrated | ⬜ Integrated | ⬜ Verified

---

## Functional Testing

### ✅ 6. Simple PPTX Creation Test

**Test:**
Ask Claude:
```
"Create a 3-slide executive summary about AI adoption in healthcare"
```

**Expected Behavior:**
1. Claude uses exec-communicator persona
2. Selects executive-summary template
3. Structures with pyramid principle
4. Creates 3 slides with BLUF approach

**Status:** ⬜ Failed | ⬜ Partial | ⬜ Success

---

### ✅ 7. Template Selection Test

**Test:**
Ask Claude:
```
"What PowerPoint templates are available?"
```

**Expected Response:**
List of 5 templates with descriptions:
- Executive Summary
- Board Presentation
- Business Case
- Status Update
- Workshop Readout

**Status:** ⬜ Failed | ⬜ Partial | ⬜ Success

---

### ✅ 8. Knowledge Mode Integration Test

**Test:**
```bash
/co:km on
"Analyze the market for electric vehicles in Europe"
```

Then:
```
"Export this analysis to a business case presentation"
```

**Expected Behavior:**
1. Claude completes market analysis
2. Suggests business-case template
3. Structures with exec summary, market opportunity, etc.
4. Generates PPTX

**Status:** ⬜ Failed | ⬜ Partial | ⬜ Success

---

### ✅ 9. Theme Application Test

**Test:**
Ask Claude:
```
"Show me the color scheme for the executive theme"
```

**Expected Response:**
- Primary: Navy Blue (#1F4788)
- Secondary: Slate Blue (#5B7A9F)
- Accent: Coral Red (#E8505B)

**Status:** ⬜ Failed | ⬜ Partial | ⬜ Success

---

### ✅ 10. Persona Integration Test

**Test:**
Ask Claude:
```
"Create an executive summary about Q4 performance in exec-communicator style"
```

**Expected Behavior:**
1. Uses pyramid principle
2. Leads with BLUF
3. Quantifies where possible
4. Structures for C-suite audience

**Status:** ⬜ Failed | ⬜ Partial | ⬜ Success

---

## Edge Cases & Error Handling

### ✅ 11. Missing Plugin Handling

**Test:**
Temporarily rename plugin (if installed), then ask:
```
"Create a PowerPoint presentation"
```

**Expected Response:**
Claude should detect missing plugin and suggest:
```
/plugin install document-skills@anthropic-agent-skills
```

**Status:** ⬜ Failed | ⬜ Partial | ⬜ Success

---

### ✅ 12. Template Not Found Handling

**Test:**
Ask Claude:
```
"Use the non-existent-template to create a presentation"
```

**Expected Response:**
Claude should:
1. Recognize template doesn't exist
2. Suggest available templates
3. Ask which one to use instead

**Status:** ⬜ Failed | ⬜ Partial | ⬜ Success

---

### ✅ 13. Multi-Format Export

**Test:**
Ask Claude:
```
"Export this analysis to both PowerPoint and Word"
```

**Expected Behavior:**
1. Generate PPTX with template
2. Generate DOCX with detailed content
3. Provide both file paths

**Status:** ⬜ Failed | ⬜ Partial | ⬜ Success

---

## Documentation Quality

### ✅ 14. Template Documentation

**Check:**
```bash
cat templates/README.md | grep "## Available Templates"
```

**Expected:** Clear descriptions of all 5 templates

**Status:** ⬜ Incomplete | ⬜ Complete | ⬜ Verified

---

### ✅ 15. Setup Guide Completeness

**Check:**
```bash
cat PPTX_SETUP_GUIDE.md | grep "## Quick Start"
```

**Expected:** Step-by-step quick start (5 minutes)

**Status:** ⬜ Incomplete | ⬜ Complete | ⬜ Verified

---

### ✅ 16. Examples & Use Cases

**Check:**
```bash
grep -c "Example" PPTX_SETUP_GUIDE.md
```

**Expected:** At least 3 examples

**Status:** ⬜ Insufficient | ⬜ Adequate | ⬜ Verified

---

## Quality Gates

### Pass Criteria

**Minimum Requirements (MVP):**
- [ ] document-skills plugin installation instructions clear
- [ ] 5 templates present and documented
- [ ] Executive theme defined
- [ ] Basic PPTX creation works
- [ ] Documentation exists

**Full Success (Production Ready):**
- [ ] All prerequisites validated ✓
- [ ] All functional tests pass ✓
- [ ] Edge cases handled ✓
- [ ] Documentation complete ✓
- [ ] Examples work end-to-end ✓

---

## Validation Summary

**Date:** [Fill in after validation]
**Validator:** [Fill in]
**Overall Status:** ⬜ Failed | ⬜ Needs Work | ⬜ Pass | ⬜ Excellent

**Issues Found:**
1. [List any issues]
2. [...]

**Recommendations:**
1. [Improvements needed]
2. [...]

**Sign-off:**
- [ ] Setup validated and production-ready
- [ ] Documentation approved
- [ ] Ready for end-user use

---

*Validation Checklist for claude-octopus v7.7.0 PowerPoint Setup*
