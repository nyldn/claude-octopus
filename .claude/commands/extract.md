---
command: extract
description: "Design System & Product Reverse-Engineering - Extract tokens, components, architecture, and PRDs from codebases or live products"
aliases:
  - reverse-engineer
  - analyze-codebase
---

# /octo:extract - Design System & Product Reverse-Engineering

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:extract <target>` or `/octo:extract <target>`):

### Step 1: Validate Input & Check Dependencies

**Parse the command arguments:**
```bash
# Expected format:
# /octo:extract <target> [options]
# target: URL or local directory path
# options: --mode, --scope, --depth, --output, --storybook, --ignore
```

**Check Claude Octopus availability:**
```javascript
// Check if multi-AI providers are available
const codexAvailable = await checkCommandAvailable('codex');
const geminiAvailable = await checkCommandAvailable('gemini');

if (!codexAvailable && !geminiAvailable) {
  console.log("⚠️ Multi-AI providers not detected. Running in single-provider mode.");
  console.log("For best results, run `/octo:setup` to configure Codex and Gemini.");
}
```

### Step 2: Intent Capture (Interactive Questions)

**CRITICAL: Use AskUserQuestion to gather extraction intent:**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What do you want to extract from this codebase/URL?",
      header: "Extract Mode",
      multiSelect: false,
      options: [
        {label: "Design system only", description: "Tokens, components, Storybook scaffold"},
        {label: "Product architecture only", description: "Architecture, features, PRDs"},
        {label: "Both (Recommended)", description: "Complete design + product documentation"},
        {label: "Auto-detect", description: "Let Claude decide based on what's found"}
      ]
    },
    {
      question: "Who will use these extraction outputs?",
      header: "Audience",
      multiSelect: true,
      options: [
        {label: "Designers", description: "Need design tokens and component inventory"},
        {label: "Frontend Engineers", description: "Need Storybook and component docs"},
        {label: "Product/Leadership", description: "Need architecture maps and PRDs"},
        {label: "AI Agents", description: "Need structured, implementation-ready outputs"}
      ]
    },
    {
      question: "What should be the source of truth?",
      header: "Source Priority",
      multiSelect: false,
      options: [
        {label: "Code files (Recommended)", description: "Extract from codebase directly"},
        {label: "Live UI rendering", description: "Analyze computed styles from browser"},
        {label: "Both - prefer code", description: "Use code when available, infer from UI otherwise"}
      ]
    },
    {
      question: "What extraction depth do you need?",
      header: "Depth",
      multiSelect: false,
      options: [
        {label: "Quick (< 2 min)", description: "Basic token/component scan"},
        {label: "Standard (2-5 min)", description: "Comprehensive analysis with quality gates"},
        {label: "Deep (5-15 min)", description: "Multi-AI consensus, full Storybook, detailed PRDs"}
      ]
    }
  ]
})
```

**Store answers:**
```json
{
  "mode": "both" | "design" | "product" | "auto",
  "audience": ["designers", "engineers", "product", "agents"],
  "sourceOfTruth": "code" | "ui" | "both",
  "depth": "quick" | "standard" | "deep"
}
```

### Step 3: Auto-Detection Phase

**Analyze the target to understand what's present:**

```javascript
// Phase 3.1: Determine target type
const targetType = await detectTargetType(target);
// Returns: { type: 'directory' | 'url', exists: boolean, accessible: boolean }

// Phase 3.2: Framework & stack detection
const stackDetection = await runStackDetection(target);
/*
Returns:
{
  framework: 'react' | 'vue' | 'svelte' | 'angular' | 'vanilla',
  styling: 'tailwindcss' | 'css-modules' | 'styled-components' | 'emotion' | 'scss',
  buildTool: 'vite' | 'webpack' | 'parcel' | 'esbuild',
  tokenFiles: ['src/theme.ts', 'tailwind.config.js'],
  componentDirs: ['src/components', 'src/features'],
  routingPattern: 'react-router' | 'next-pages' | 'next-app' | 'vue-router',
  stateManagement: 'redux' | 'zustand' | 'context' | 'pinia' | 'vuex',
  hasStorybook: boolean,
  confidence: { framework: 0.95, styling: 0.90, ... }
}
*/

// Phase 3.3: Design system signals
const designSignals = await detectDesignSystemSignals(target);
/*
Returns:
{
  tokenCount: number,
  componentCount: number,
  hasDesignSystem: boolean,
  storybookPresent: boolean,
  designSystemFolder: string | null
}
*/

// Phase 3.4: Product architecture signals
const architectureSignals = await detectArchitectureSignals(target);
/*
Returns:
{
  serviceCount: number,
  isMonorepo: boolean,
  hasAPI: boolean,
  apiType: 'rest' | 'graphql' | 'trpc' | 'grpc' | null,
  dataLayer: 'prisma' | 'typeorm' | 'sequelize' | null,
  featureCount: number
}
*/

// Phase 3.5: Generate detection report
await writeFile(`${outputDir}/00_intent/detection-report.md`, `
# Detection Report

**Target:** ${target}
**Type:** ${targetType.type}
**Timestamp:** ${new Date().toISOString()}

## Stack Detection

- **Framework:** ${stackDetection.framework} (${(stackDetection.confidence.framework * 100).toFixed(0)}% confidence)
- **Styling:** ${stackDetection.styling}
- **Build Tool:** ${stackDetection.buildTool}
- **State Management:** ${stackDetection.stateManagement}

## Design System Signals

- **Tokens Found:** ${designSignals.tokenCount} files
- **Components Found:** ${designSignals.componentCount} components
- **Storybook Present:** ${designSignals.storybookPresent ? 'Yes' : 'No'}
- **Design System Folder:** ${designSignals.designSystemFolder || 'Not detected'}

## Architecture Signals

- **Services/Modules:** ${architectureSignals.serviceCount}
- **Monorepo:** ${architectureSignals.isMonorepo ? 'Yes' : 'No'}
- **API Type:** ${architectureSignals.apiType || 'None detected'}
- **Data Layer:** ${architectureSignals.dataLayer || 'None detected'}
- **Features:** ${architectureSignals.featureCount} detected

## Recommended Extraction Strategy

Based on detection, we recommend:
- **Mode:** ${designSignals.hasDesignSystem ? 'Both (Design + Product)' : 'Product-focused'}
- **Token Extraction:** ${designSignals.tokenCount > 0 ? 'Code-defined (high confidence)' : 'CSS inference (medium confidence)'}
- **Component Analysis:** ${designSignals.componentCount > 50 ? 'Full inventory with variants' : 'Basic inventory'}
- **Architecture Mapping:** ${architectureSignals.serviceCount > 1 ? 'Multi-service C4 diagram' : 'Single-service component diagram'}
`);
```

### Step 4: Execution Strategy Selection

**Based on user intent + auto-detection, choose pipeline:**

```javascript
const executionPlan = buildExecutionPlan({
  userIntent: intentAnswers,
  detectionResults: { stackDetection, designSignals, architectureSignals },
  multiAIAvailable: codexAvailable && geminiAvailable
});

/*
Example execution plan:
{
  phases: [
    {
      name: 'Design Token Extraction',
      enabled: true,
      method: 'code-defined',
      multiAI: true,
      estimatedTime: '30s'
    },
    {
      name: 'Component Analysis',
      enabled: true,
      method: 'ast-parsing',
      multiAI: true,
      estimatedTime: '90s'
    },
    {
      name: 'Storybook Generation',
      enabled: false, // user didn't select engineers as audience
      reason: 'Not requested by user'
    },
    {
      name: 'Architecture Extraction',
      enabled: true,
      method: 'dependency-analysis',
      multiAI: true,
      estimatedTime: '60s'
    },
    {
      name: 'PRD Generation',
      enabled: true,
      method: 'feature-detection',
      multiAI: false, // only Claude for synthesis
      estimatedTime: '45s'
    }
  ],
  totalEstimatedTime: '225s',
  consensusThreshold: 0.67,
  outputFormats: ['json', 'csv', 'markdown', 'mermaid']
}
*/

// Display plan to user
console.log(`
📋 **Extraction Plan**

Enabled Phases:
${executionPlan.phases.filter(p => p.enabled).map(p =>
  `✓ ${p.name} (${p.estimatedTime}, ${p.multiAI ? 'Multi-AI' : 'Single-AI'})`
).join('\n')}

⏱️ **Estimated Total Time:** ${Math.ceil(executionPlan.totalEstimatedTime / 60)} minutes

🚀 Starting extraction...
`);
```

### Step 5: Execute Extraction Pipelines

**Phase 5.1: Design Token Extraction** (if enabled)

```javascript
async function extractDesignTokens(target, config) {
  const results = {
    tokens: {},
    sources: [],
    confidence: {}
  };

  // Step 1: Code-defined token extraction
  const codeTokens = await extractCodeDefinedTokens(target);
  // Searches for: tailwind.config.js, theme.ts, tokens.json, CSS variables

  // Step 2: Multi-AI consensus (if enabled)
  if (config.multiAI) {
    const [claudeTokens, codexTokens, geminiTokens] = await Promise.all([
      extractTokensWithClaude(target),
      extractTokensWithCodex(target),
      extractTokensWithGemini(target)
    ]);

    results.tokens = buildConsensusTokens(
      [claudeTokens, codexTokens, geminiTokens],
      { threshold: 0.67 }
    );

    // Log disagreements
    const disagreements = findDisagreements([claudeTokens, codexTokens, geminiTokens]);
    if (disagreements.length > 0) {
      await writeFile(
        `${config.outputDir}/90_evidence/token-disagreements.md`,
        formatDisagreements(disagreements)
      );
    }
  } else {
    results.tokens = codeTokens;
  }

  // Step 3: Assign confidence scores
  for (const [tokenName, tokenData] of Object.entries(results.tokens)) {
    if (tokenData.source.includes('theme.ts') || tokenData.source.includes('tokens.json')) {
      results.confidence[tokenName] = 'code-defined'; // 95%
    } else if (tokenData.source.includes(':root')) {
      results.confidence[tokenName] = 'css-variable'; // 90%
    } else {
      results.confidence[tokenName] = 'inferred'; // 60%
    }
  }

  // Step 4: Generate outputs
  await generateTokenOutputs(results, config.outputDir);
  /*
  Generates:
  - 10_design/tokens.json (W3C format)
  - 10_design/tokens.css (CSS custom properties)
  - 10_design/tokens.md (Human-readable docs)
  - 90_evidence/token-sources.json (Provenance)
  */

  return results;
}
```

**Phase 5.2: Component Analysis** (if enabled)

```javascript
async function analyzeComponents(target, config) {
  const results = {
    components: [],
    inventory: []
  };

  // Step 1: AST-based component detection
  const componentFiles = await findComponentFiles(target, {
    frameworks: [config.framework],
    ignorePatterns: ['node_modules', 'dist', '.next']
  });

  // Step 2: Extract props, variants, usage
  for (const compFile of componentFiles) {
    const analysis = await analyzeComponent(compFile, {
      extractProps: true,
      detectVariants: true,
      trackUsage: true
    });

    results.components.push(analysis);
  }

  // Step 3: Multi-AI validation (if enabled)
  if (config.multiAI) {
    const validatedComponents = await validateWithMultiAI(results.components);
    results.components = validatedComponents;
  }

  // Step 4: Generate inventory
  results.inventory = components ToInventory(results.components);

  // Step 5: Generate outputs
  await writeFile(
    `${config.outputDir}/10_design/components.csv`,
    generateComponentCSV(results.inventory)
  );

  await writeFile(
    `${config.outputDir}/10_design/components.json`,
    JSON.stringify(results.components, null, 2)
  );

  await writeFile(
    `${config.outputDir}/10_design/patterns.md`,
    generatePatternDocumentation(results.components)
  );

  return results;
}
```

**Phase 5.3: Storybook Scaffold Generation** (if enabled)

```javascript
async function generateStorybookScaffold(components, config) {
  const storybookDir = `${config.outputDir}/10_design/storybook`;

  // Create Storybook config
  await writeFile(`${storybookDir}/.storybook/main.js`, `
module.exports = {
  stories: ['../stories/**/*.stories.@(ts|tsx|js|jsx|mdx)'],
  addons: [
    '@storybook/addon-links',
    '@storybook/addon-essentials',
    '@storybook/addon-interactions',
    '@storybook/addon-a11y'
  ],
  framework: {
    name: '@storybook/react-vite',
    options: {}
  }
};
  `);

  // Generate stories for top 10 components
  const topComponents = components
    .sort((a, b) => b.usageCount - a.usageCount)
    .slice(0, 10);

  for (const component of topComponents) {
    const storyContent = generateStoryFile(component);
    await writeFile(
      `${storybookDir}/stories/${component.name}.stories.tsx`,
      storyContent
    );
  }

  // Generate docs pages
  await generateStorybookDocs(storybookDir, config);
}
```

**Phase 5.4: Architecture Extraction** (if enabled)

```javascript
async function extractArchitecture(target, config) {
  const results = {
    services: [],
    boundaries: [],
    dataStores: [],
    apiEndpoints: []
  };

  // Step 1: Service boundary detection
  results.services = await detectServiceBoundaries(target);

  // Step 2: API endpoint extraction
  results.apiEndpoints = await extractAPIEndpoints(target, {
    types: ['rest', 'graphql', 'trpc', 'grpc']
  });

  // Step 3: Data model extraction
  results.dataStores = await extractDataModels(target);

  // Step 4: Build dependency graph
  const dependencyGraph = await buildDependencyGraph(results);

  // Step 5: Multi-AI consensus on architecture
  if (config.multiAI) {
    const [claudeArch, codexArch, geminiArch] = await Promise.all([
      analyzeArchitectureWithClaude(dependencyGraph),
      analyzeArchitectureWithCodex(dependencyGraph),
      analyzeArchitectureWithGemini(dependencyGraph)
    ]);

    results.architecture = buildConsensusArchitecture(
      [claudeArch, codexArch, geminiArch]
    );
  }

  // Step 6: Generate C4 diagrams
  await generateC4Diagrams(results, config.outputDir);

  // Step 7: Generate architecture docs
  await writeFile(
    `${config.outputDir}/20_product/architecture.md`,
    generateArchitectureDoc(results)
  );

  return results;
}
```

**Phase 5.5: Feature Detection & PRD Generation** (if enabled)

```javascript
async function generateProductPack(target, architecture, config) {
  // Step 1: Feature detection
  const features = await detectFeatures(target, {
    fromRoutes: true,
    fromComponents: true,
    fromDomains: true
  });

  // Step 2: Generate feature inventory
  await writeFile(
    `${config.outputDir}/20_product/feature-inventory.md`,
    generateFeatureInventory(features)
  );

  // Step 3: Generate PRD
  const prd = await generatePRD({
    features,
    architecture,
    audience: config.audience
  });

  await writeFile(
    `${config.outputDir}/20_product/PRD.md`,
    prd
  );

  // Step 4: Generate user stories
  await writeFile(
    `${config.outputDir}/20_product/user-stories.md`,
    generateUserStories(features)
  );

  // Step 5: Generate API contracts (if detected)
  if (architecture.apiEndpoints.length > 0) {
    await writeFile(
      `${config.outputDir}/20_product/api-contracts.md`,
      generateAPIContracts(architecture.apiEndpoints)
    );
  }

  // Step 6: Generate implementation plan
  await writeFile(
    `${config.outputDir}/20_product/implementation-plan.md`,
    generateImplementationPlan(features, architecture)
  );
}
```

### Step 6: Quality Gates & Validation

```javascript
async function runQualityGates(results, config) {
  const qualityReport = {
    coverage: {},
    confidence: {},
    gaps: [],
    warnings: []
  };

  // Gate 1: Token coverage
  if (results.tokens) {
    const tokenCount = Object.keys(results.tokens).length;
    if (tokenCount === 0 && config.mode === 'design') {
      throw new Error('VALIDATION FAILED: No tokens detected in design mode');
    }
    if (tokenCount < 10 && config.sourceOfTruth === 'code') {
      qualityReport.warnings.push('Low token count detected. Verify token files exist.');
    }
    qualityReport.coverage.tokens = `${tokenCount} tokens extracted`;
  }

  // Gate 2: Component coverage
  if (results.components) {
    const componentCount = results.components.length;
    const expectedCount = await estimateComponentCount(config.target);
    const coverage = componentCount / expectedCount;

    if (coverage < 0.5) {
      qualityReport.warnings.push(
        `Component coverage is ${(coverage * 100).toFixed(0)}%. Expected ~${expectedCount}, found ${componentCount}.`
      );
    }
    qualityReport.coverage.components = `${componentCount}/${expectedCount} (${(coverage * 100).toFixed(0)}%)`;
  }

  // Gate 3: Multi-AI consensus
  if (config.multiAI && results.disagreements) {
    const consensusRate = 1 - (results.disagreements.length / results.totalDecisions);
    if (consensusRate < 0.5) {
      throw new Error(
        `VALIDATION FAILED: Low multi-AI consensus (${(consensusRate * 100).toFixed(0)}%). Review disagreements.md.`
      );
    }
    qualityReport.confidence.consensus = `${(consensusRate * 100).toFixed(0)}%`;
  }

  // Gate 4: Architecture completeness
  if (results.architecture) {
    if (results.architecture.services.length === 0 && config.mode === 'product') {
      qualityReport.gaps.push('No services/modules detected. Architecture may be incomplete.');
    }
    if (!results.architecture.dataStores || results.architecture.dataStores.length === 0) {
      qualityReport.gaps.push('No data stores detected. Verify database configuration.');
    }
  }

  // Generate quality report
  await writeFile(
    `${config.outputDir}/90_evidence/quality-report.md`,
    formatQualityReport(qualityReport)
  );

  return qualityReport;
}
```

### Step 7: Generate Final Outputs & Summary

```javascript
// Generate README with navigation
await writeFile(`${config.outputDir}/README.md`, `
# Extraction Results: ${projectName}

**Extracted:** ${new Date().toISOString()}
**Target:** ${config.target}
**Mode:** ${config.mode}
**Depth:** ${config.depth}
**Providers Used:** ${config.multiAI ? 'Claude, Codex, Gemini' : 'Claude only'}

## Summary

${generateSummary(results)}

## Quick Navigation

### Design System
${results.tokens ? `- [Design Tokens (JSON)](./10_design/tokens.json)` : ''}
${results.tokens ? `- [Design Tokens (CSS)](./10_design/tokens.css)` : ''}
${results.components ? `- [Component Inventory](./10_design/components.csv)` : ''}
${results.storybook ? `- [Storybook Scaffold](./10_design/storybook/)` : ''}

### Product Documentation
${results.architecture ? `- [Architecture Overview](./20_product/architecture.md)` : ''}
${results.architecture ? `- [C4 Diagram](./20_product/architecture.mmd)` : ''}
${results.features ? `- [Feature Inventory](./20_product/feature-inventory.md)` : ''}
${results.prd ? `- [PRD](./20_product/PRD.md)` : ''}

### Evidence & Quality
- [Quality Report](./90_evidence/quality-report.md)
- [Detection Report](./00_intent/detection-report.md)
${results.disagreements ? `- [Multi-AI Disagreements](./90_evidence/disagreements.md)` : ''}

## Next Steps

1. **For Designers:** Review design tokens and component patterns
2. **For Engineers:** Explore component inventory and Storybook
3. **For Product:** Review feature inventory and PRD
4. **For AI Agents:** All outputs are structured and implementation-ready
`);

// Print summary to user
console.log(`
✅ **Extraction Complete!**

📊 **Results:**
- Tokens: ${results.tokens ? Object.keys(results.tokens).length : 0}
- Components: ${results.components ? results.components.length : 0}
- Services: ${results.architecture ? results.architecture.services.length : 0}
- Features: ${results.features ? results.features.length : 0}

📁 **Output Location:** ${config.outputDir}

🎯 **Quality Score:** ${qualityReport.overallScore}/100

View full results: ${config.outputDir}/README.md
`);
```

---

## Command Usage Examples

```bash
# Basic usage - extract from local directory
/octo:extract ./my-app

# Extract from URL
/octo:extract https://example.com

# With options
/octo:extract ./my-app --mode design --depth deep --storybook true

# Extract with specific output location
/octo:extract ./my-app --output ./extraction-results

# Quick mode for fast analysis
/octo:extract ./my-app --depth quick
```

---

## Options Reference

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--mode` | `design`, `product`, `both`, `auto` | `auto` | What to extract |
| `--depth` | `quick`, `standard`, `deep` | `standard` | Analysis thoroughness |
| `--storybook` | `true`, `false` | `true` | Generate Storybook scaffold |
| `--output` | path | `./octopus-extract` | Output directory |
| `--ignore` | glob patterns | Common build dirs | Files to exclude |
| `--multi-ai` | `true`, `false`, `force` | `auto` | Multi-provider mode |

---

## Output Structure

```
octopus-extract/
└── project-name/
    └── timestamp/
        ├── README.md
        ├── metadata.json
        ├── 00_intent/
        │   ├── answers.json
        │   ├── intent-contract.md
        │   └── detection-report.md
        ├── 10_design/
        │   ├── tokens.json
        │   ├── tokens.css
        │   ├── tokens.md
        │   ├── components.csv
        │   ├── components.json
        │   ├── patterns.md
        │   └── storybook/
        ├── 20_product/
        │   ├── product-overview.md
        │   ├── feature-inventory.md
        │   ├── architecture.md
        │   ├── architecture.mmd
        │   ├── PRD.md
        │   ├── user-stories.md
        │   ├── api-contracts.md
        │   └── implementation-plan.md
        └── 90_evidence/
            ├── quality-report.md
            ├── disagreements.md
            ├── extraction-log.md
            └── references.json
```

---

## Integration with Claude Octopus

This command leverages Claude Octopus multi-AI orchestration when available:

- **Claude**: Synthesis, conflict resolution, final documentation
- **Codex**: Code-level analysis, type extraction, architecture inference
- **Gemini**: Pattern recognition, alternative interpretations, UX insights

Consensus threshold: 67% (2/3 providers must agree for high confidence)

If providers are not available, the command gracefully degrades to single-provider mode.

---

## Safety & Privacy

- **Never exfiltrates secrets**: Automatically redacts `.env`, API keys, tokens
- **Local-only by default**: Directory analysis stays on your machine
- **URL extraction**: Only fetches public content unless explicitly configured
- **Safe summary mode**: Available for compliance-sensitive codebases

---

## Error Handling

All errors are logged to `90_evidence/extraction-log.md` with timestamps.

Common error codes:
- `ERR-001`: Invalid input path/URL
- `ERR-002`: Network timeout
- `ERR-003`: Permission denied
- `ERR-004`: Out of memory (try `--depth quick`)
- `ERR-005`: Provider failure (falling back to single-AI)
- `VAL-001`: No tokens detected (design mode)
- `VAL-002`: No components detected
- `VAL-004`: Low multi-AI consensus

---

## Related Commands

- `/octo:setup` - Configure multi-AI providers
- `/octo:review` - Review extracted outputs for quality
- `/octo:deliver` - Validate extraction results

---

## Success Metrics

Target metrics (as defined in PRD):
- Time to first artifact: < 5 minutes (standard mode)
- Token extraction accuracy: ≥ 95% (code-defined)
- Component coverage: ≥ 85%
- Architecture accuracy: ≥ 90%

---

*This command implements PRD v2.0 (AI-Executable) for design system extraction*
