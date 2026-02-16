# Manual Benchmark Test Guide

This guide walks you through manually testing the Claude Octopus plugin value proposition by comparing security analysis **with** and **without** the plugin.

---

## Quick Start

```bash
# 1. Run test with plugin enabled
./tests/benchmark/manual-test.sh with-plugin

# 2. Disable the plugin (follow the prompt)

# 3. Run test without plugin
./tests/benchmark/manual-test.sh without-plugin

# 4. Re-enable the plugin (follow the prompt)

# 5. Compare results
./tests/benchmark/manual-test.sh compare
```

---

## What This Tests

**Test Case**: SQL Injection Login Vulnerability Analysis
- **Code**: 107 lines of Python Flask authentication
- **Known Issues**: 12 security vulnerabilities
- **Complexity**: CRITICAL (3), HIGH (4), MEDIUM (4), LOW (1)

**Goal**: Determine if the multi-agent plugin provides measurable improvement over baseline Claude analysis.

---

## Step-by-Step Instructions

### Step 1: Test WITH Plugin Enabled

```bash
./tests/benchmark/manual-test.sh with-plugin
```

**What this does**:
- Shows you the vulnerable code
- Provides the analysis prompt
- Waits for you to paste Claude's response
- Saves to: `.dev/benchmarks/manual/with-plugin-response.md`

**What you should do**:
1. Read the vulnerable code displayed
2. Copy the prompt shown
3. Paste it into Claude Code (in this session or a new one)
4. Wait for Claude's full security analysis
5. Copy Claude's entire response
6. Paste it when the script prompts you
7. Press Ctrl+D (or Cmd+D on Mac) when done

---

### Step 2: Disable the Plugin

**Option A: Temporary Disable (Recommended)**
```bash
# Move the plugin directory temporarily
mv ~/.claude/plugins/claude-octopus ~/.claude/plugins/claude-octopus.disabled
```

**Option B: Use Claude Settings**
- Go to Claude Code settings
- Disable the `claude-octopus` plugin
- Restart Claude Code if needed

**Verify it's disabled**:
```bash
# This should NOT show claude-octopus
claude plugins list
# or check manually
ls ~/.claude/plugins/
```

---

### Step 3: Test WITHOUT Plugin

```bash
./tests/benchmark/manual-test.sh without-plugin
```

**What this does**:
- Shows the SAME vulnerable code
- Provides the SAME analysis prompt
- Waits for you to paste Claude's response
- Saves to: `.dev/benchmarks/manual/without-plugin-response.md`

**What you should do**:
1. Copy the prompt (same as before)
2. Paste it into Claude Code (plugin now disabled)
3. Wait for Claude's security analysis
4. Copy Claude's entire response
5. Paste it when the script prompts you
6. Press Ctrl+D (or Cmd+D) when done

---

### Step 4: Re-enable the Plugin

**If you used Option A (temporary disable)**:
```bash
# Move it back
mv ~/.claude/plugins/claude-octopus.disabled ~/.claude/plugins/claude-octopus
```

**If you used Option B (Claude settings)**:
- Go to Claude Code settings
- Re-enable the `claude-octopus` plugin
- Restart Claude Code if needed

**Verify it's enabled**:
```bash
# This SHOULD show claude-octopus
claude plugins list
# or check manually
ls ~/.claude/plugins/claude-octopus
```

---

### Step 5: Compare Results

```bash
./tests/benchmark/manual-test.sh compare
```

**What this does**:
- Analyzes both responses
- Extracts vulnerability findings from each
- Compares to ground truth (12 known issues)
- Calculates metrics:
  - True Positives (correctly found issues)
  - False Positives (incorrectly flagged issues)
  - False Negatives (missed issues)
  - Detection Rate, Precision, F1 Score
- Generates comprehensive comparison report
- Saves to: `.dev/benchmarks/manual/COMPARISON-REPORT.md`

**What you should do**:
- Review the comparison report
- Check which approach found more issues
- Evaluate quality of analysis
- Consider trade-offs (time, cost, comprehensiveness)

---

## Expected Results

### Baseline (Without Plugin)
Claude Code is highly capable at security analysis. Expected:
- **Detection Rate**: 80-100% of known issues
- **False Positives**: Low (0-2 issues)
- **Analysis Quality**: Comprehensive, actionable

### With Plugin (Multi-Agent Orchestration)
Plugin adds multiple perspectives. Expected:
- **Detection Rate**: Similar or higher (85-100%)
- **False Positives**: Potentially higher (more aggressive scanning)
- **Analysis Quality**: Multiple viewpoints, consensus validation
- **Additional Value**:
  - Attack chain analysis
  - Architectural recommendations
  - Compliance mapping
  - Cross-validation between agents

### Key Questions to Answer
1. **Quality**: Did plugin find more vulnerabilities?
2. **Accuracy**: Did plugin have more false positives?
3. **Depth**: Did plugin provide deeper analysis (attack chains, remediation)?
4. **Cost**: Was the additional API usage worth the improvement?

---

## Troubleshooting

### "I can't disable the plugin"
- Use the temporary move method: `mv ~/.claude/plugins/claude-octopus{,.disabled}`
- Verify with `ls ~/.claude/plugins/`

### "Claude's response is too long to paste"
- Save Claude's response to a file first
- Then cat the file when prompted: `cat response.md`

### "I want to run this multiple times"
- Each run creates a timestamped directory in `.dev/benchmarks/manual/`
- You can run as many trials as you want
- Use `./tests/benchmark/manual-test.sh clean` to remove all results

### "How do I know if the plugin is actually running?"
- With plugin enabled, you should see references to "multi-agent", "perspectives", or "probe" workflow
- Without plugin, responses will be direct analysis from a single Claude instance

---

## File Locations

All results saved to: `.dev/benchmarks/manual/`

```
.dev/benchmarks/manual/
├── vulnerable-code.py           # The test case (for reference)
├── analysis-prompt.txt          # The exact prompt used
├── with-plugin-response.md      # Your response WITH plugin
├── without-plugin-response.md   # Your response WITHOUT plugin
└── COMPARISON-REPORT.md         # Automated comparison results
```

These files are gitignored (won't be committed to repository).

---

## What Happens Next

After you run the comparison:
1. Review the COMPARISON-REPORT.md
2. Share it with Claude for discussion
3. Claude can provide insights on:
   - Whether the plugin added measurable value
   - What scenarios the plugin excels at
   - Whether to expand testing to harder cases
   - Recommendations for plugin usage

---

## Advanced: Custom Test Cases

Want to test with your own code?

1. Create a new test case:
```bash
mkdir -p tests/benchmark/test-cases/vulnerable/your-test-name/
```

2. Add your code:
```bash
# Your vulnerable code file
tests/benchmark/test-cases/vulnerable/your-test-name/code.{py,js,java,etc}
```

3. Create ground truth (optional):
```json
{
  "test_case": "your-test-name",
  "expected_issues": [
    {
      "severity": "CRITICAL",
      "cwe": "CWE-89",
      "location": "code.py:42",
      "description": "SQL injection vulnerability"
    }
  ]
}
```

4. Run with your test:
```bash
TEST_CASE=your-test-name ./tests/benchmark/manual-test.sh with-plugin
```

---

## Questions?

If you encounter issues or have questions:
1. Check the troubleshooting section above
2. Review `.dev/benchmarks/manual/` for saved responses
3. Ask Claude for help (paste the error or unexpected behavior)

---

**Ready to test? Start with Step 1!** 🚀

```bash
./tests/benchmark/manual-test.sh with-plugin
```
