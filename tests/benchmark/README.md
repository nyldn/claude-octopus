# Claude Octopus Benchmark Suite

This directory contains benchmarking tools to validate the claude-octopus plugin's value proposition through **ground truth comparison** against known vulnerable code.

---

## Quick Start

### Manual Testing (Recommended for Users)

**Best for**: Validating plugin value without API costs concerns

```bash
# Step 1: Test WITH plugin
./manual-test.sh with-plugin

# Step 2: Disable plugin, then test WITHOUT
./manual-test.sh without-plugin

# Step 3: Compare results
./manual-test.sh compare
```

📖 **Full guide**: See [MANUAL-TEST-GUIDE.md](./MANUAL-TEST-GUIDE.md) for detailed instructions.

---

### Automated Testing (For Development)

**Best for**: CI/CD, regression testing, large-scale validation

```bash
# Run full benchmark (dry-run mode)
./run-benchmark.sh

# Results saved to: .dev/benchmarks/YYYYMMDD-HHMMSS/
```

⚠️ **Note**: Automated mode requires API credits and calls real LLM endpoints.

---

## What This Tests

### Test Case: SQL Injection Login Vulnerability

**File**: `test-cases/vulnerable/sql-injection-login/code.py`
- **Size**: 107 lines of Python Flask authentication code
- **Vulnerabilities**: 12 known security issues
- **Severity**: 3 CRITICAL, 4 HIGH, 4 MEDIUM, 1 LOW
- **Source**: Adapted from OWASP examples for realism

**Ground Truth**: `test-cases/vulnerable/sql-injection-login/ground-truth.json`
- Expected CWE categories for each vulnerability
- Severity levels, locations, attack vectors
- Target metrics: 90% TP rate, 10% FP rate, 0.85 F1 score

---

## Methodology

Follows industry best practices for code analysis tool benchmarking:

### 1. Ground Truth Comparison
- Known vulnerable code with documented security issues
- Each issue has: CWE category, severity, location, description, attack vector
- Quantitative validation (not subjective assessment)

### 2. Baseline vs Plugin Comparison
- **Baseline**: Claude Code without plugin (single-agent analysis)
- **Plugin**: Claude Code with multi-agent orchestration (4 perspectives)
- Measures: detection rate, false positives, analysis depth

### 3. Metrics
- **True Positives (TP)**: Correctly identified vulnerabilities
- **False Positives (FP)**: Incorrectly flagged issues
- **False Negatives (FN)**: Missed vulnerabilities
- **Detection Rate**: TP / (TP + FN)
- **Precision**: TP / (TP + FP)
- **F1 Score**: 2 × (Precision × Recall) / (Precision + Recall)

---

## File Structure

```
tests/benchmark/
├── README.md                     # This file
├── MANUAL-TEST-GUIDE.md          # Step-by-step user guide
├── manual-test.sh                # Interactive test script
├── run-benchmark.sh              # Automated benchmark runner
│
└── test-cases/
    └── vulnerable/
        └── sql-injection-login/
            ├── code.py           # Vulnerable Flask auth code
            └── ground-truth.json # Expected findings
```

**Results** (gitignored):
```
.dev/benchmarks/
├── manual/                       # Manual test results
│   ├── with-plugin-response.md
│   ├── without-plugin-response.md
│   └── COMPARISON-REPORT.md
│
└── YYYYMMDD-HHMMSS/              # Automated run results
    ├── sql-injection-login-baseline-response.md
    ├── sql-injection-login-plugin-output.txt
    └── README.md
```

---

## Manual Testing Workflow

### Why Manual Testing?

1. **No API costs** - You control when API calls happen
2. **Plugin control** - Easy to enable/disable for comparison
3. **Interactive** - You see both responses and can evaluate quality yourself
4. **Educational** - Understand how the plugin actually changes Claude's behavior

### Quick Steps

```bash
# 1. WITH plugin enabled
./manual-test.sh with-plugin
# → Paste Claude's response when prompted

# 2. Disable plugin
mv ~/.claude/plugins/claude-octopus{,.disabled}

# 3. WITHOUT plugin (baseline)
./manual-test.sh without-plugin
# → Paste Claude's response when prompted

# 4. Re-enable plugin
mv ~/.claude/plugins/claude-octopus{.disabled,}

# 5. Compare
./manual-test.sh compare
# → Review COMPARISON-REPORT.md
```

### What You'll Learn

- **Quality**: Does plugin find more vulnerabilities?
- **Accuracy**: Does plugin have more false positives?
- **Depth**: Does plugin provide deeper analysis (attack chains, remediation)?
- **Cost vs Benefit**: Is 4× API usage worth the improvement?

---

## Automated Testing Workflow

### When to Use Automated Mode

- Running in CI/CD pipelines
- Large-scale testing across multiple test cases
- Regression testing after plugin updates
- Performance benchmarking (time, cost)

### Running Automated Tests

```bash
# Full benchmark with ground truth validation
./run-benchmark.sh

# Results include:
# - Baseline analysis (manual step required)
# - Plugin multi-agent orchestration output
# - Comparison to ground truth
# - TP/FP/FN calculations
```

### Automated Mode Limitations

1. **Baseline analysis is manual** - Script prompts you to run Claude without plugin yourself
2. **Requires API credits** - Plugin orchestration makes real API calls
3. **Less interactive** - Results are files, not real-time feedback

---

## Understanding Results

### Baseline Performance

Claude Code (without plugin) is **highly capable** at security analysis:
- Expected: 80-100% detection rate
- Low false positive rate
- Comprehensive, actionable findings

**Example from dry-run**: Baseline found all 12/12 vulnerabilities (100% detection)

### Plugin Value Proposition

Multi-agent orchestration adds:
- **4 Perspectives**: Attacker, Defender, Architecture, Compliance
- **Cross-Validation**: Issues validated by multiple agents
- **Consensus Building**: Higher confidence in findings
- **Deeper Analysis**: Attack chains, architectural flaws

**When plugin excels**:
- Complex codebases (multi-file, 1000+ lines)
- Subtle vulnerabilities (race conditions, timing attacks)
- Architectural security issues
- Novel attack patterns
- Trade-off decisions (security vs performance)

**When baseline is sufficient**:
- Standard OWASP Top 10 patterns
- Single-file code reviews
- Well-documented vulnerability types
- Simple security audits

---

## Interpreting Metrics

### Detection Rate (Recall)
```
TP / (TP + FN) = Found / Total Expected
```
- **100%** = Found every vulnerability ✅
- **90%+** = Excellent (industry standard)
- **70-90%** = Good (some issues missed)
- **<70%** = Poor (many vulnerabilities missed)

### Precision
```
TP / (TP + FP) = Correct Findings / All Findings
```
- **100%** = Zero false positives ✅
- **90%+** = Excellent (minimal noise)
- **70-90%** = Acceptable (some false alarms)
- **<70%** = Noisy (too many false positives)

### F1 Score
```
2 × (Precision × Recall) / (Precision + Recall)
```
- **1.0** = Perfect ✅
- **0.85+** = Excellent (target for this benchmark)
- **0.70-0.85** = Good
- **<0.70** = Needs improvement

---

## Adding Test Cases

Want to test with your own code?

### 1. Create Test Case Directory
```bash
mkdir -p test-cases/vulnerable/your-test-name/
```

### 2. Add Vulnerable Code
```bash
# Your code file (any language)
test-cases/vulnerable/your-test-name/code.{py,js,java,go,etc}
```

### 3. Define Ground Truth (Optional but Recommended)
```json
{
  "test_case": "your-test-name",
  "language": "python",
  "description": "Brief description of what this tests",
  "expected_issues": [
    {
      "id": 1,
      "severity": "CRITICAL",
      "cwe": "CWE-89",
      "category": "SQL Injection",
      "location": "code.py:42",
      "description": "SQL injection via string concatenation",
      "attack_vector": "username = ' OR '1'='1'-- allows bypass"
    }
  ]
}
```

### 4. Run Tests
```bash
# Manual
TEST_CASE=your-test-name ./manual-test.sh with-plugin

# Automated
./run-benchmark.sh  # Auto-discovers all test cases
```

---

## Best Practices

### For Accurate Results

1. **Use realistic code** - Real vulnerabilities, not synthetic examples
2. **Document ground truth** - Clear expected findings with CWE categories
3. **Run multiple trials** - Account for LLM non-determinism
4. **Control variables** - Same prompt for both tests
5. **Measure qualitatively too** - Not just counts, but depth and actionability

### For Cost-Effective Testing

1. **Start with manual tests** - Free until you're ready to commit API credits
2. **Use dry-run mode** - Validate infrastructure without API calls
3. **Small test cases first** - <200 lines to keep costs low
4. **Expand strategically** - Only add harder cases if baseline struggles

### For Meaningful Insights

1. **Test edge cases** - Where single-agent analysis might struggle
2. **Compare qualitatively** - Read both responses, assess depth
3. **Consider use cases** - Plugin value varies by scenario
4. **Measure trade-offs** - Time, cost, quality improvements

---

## Troubleshooting

### "Plugin not found" during manual test
```bash
# Verify plugin location
ls ~/.claude/plugins/claude-octopus

# Re-enable if disabled
mv ~/.claude/plugins/claude-octopus{.disabled,}
```

### "No results found" in automated mode
This is expected in dry-run mode. The script validates infrastructure without making API calls.

To run with real API:
1. Ensure Codex CLI and Gemini CLI are installed and configured
2. Remove `-n` or `--dry-run` flags from orchestrate.sh calls
3. Expect costs: ~4× normal Claude API usage (4 parallel agents)

### Responses look identical
If baseline and plugin responses are nearly identical:
1. **Verify plugin was actually enabled** - Check for multi-agent output
2. **Test harder cases** - Current test may be too simple
3. **Check orchestration logs** - Ensure 4 agents actually ran
4. **This is valid!** - Plugin may not add value for simple cases

---

## Research & Methodology

This benchmark design is based on:
- **OWASP Benchmark Project** - Standard for measuring security tool effectiveness
- **SonarQube validation studies** - Ground truth comparison methodology
- **CodeQL academic papers** - Metrics for static analysis tools
- **NIST SARD** - Software Assurance Reference Dataset patterns

Key principles:
- Real vulnerabilities (not synthetic edge cases)
- Quantitative metrics (not subjective assessment)
- Industry-standard CWE taxonomy
- Reproducible methodology

---

## Questions?

### About Manual Testing
See: [MANUAL-TEST-GUIDE.md](./MANUAL-TEST-GUIDE.md)

### About Automated Testing
See: `./run-benchmark.sh --help` or read the script comments

### About Results
Ask Claude to analyze your comparison reports. Claude can:
- Calculate TP/FP/FN rates from your responses
- Assess qualitative differences
- Recommend whether plugin adds value for your use cases

---

## Summary

**To validate plugin value**:
1. Run `./manual-test.sh with-plugin` → paste Claude's response
2. Disable plugin → run `./manual-test.sh without-plugin` → paste response
3. Run `./manual-test.sh compare` → review report
4. Ask Claude to analyze the comparison

**Expected outcome**:
- Quantitative metrics (detection rates, precision)
- Qualitative assessment (depth, actionability)
- Clear recommendation on when to use plugin
- Data-driven decision on plugin value for your scenarios

Good luck! 🚀
