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

### Step 2.5: Feature Selection (For Large Codebases)

**CRITICAL: For codebases with 500+ files, automatically run feature detection and let user choose scope:**

```javascript
// Detect codebase size
const fileCount = await getFileCount(target);

if (fileCount > 500 || userSpecified('--detect-features')) {
  console.log(`🔍 Detected large codebase (${fileCount} files). Running feature detection...`);

  // Run feature detection
  const detectionResult = await runFeatureDetection(target);
  /*
  Returns:
  {
    features: [
      { name: "Authentication", fileCount: 45, confidence: 0.9, paths: [...] },
      { name: "Payment", fileCount: 32, confidence: 0.85, paths: [...] },
      { name: "User Profile", fileCount: 28, confidence: 0.8, paths: [...] },
      ...
    ],
    unassignedFiles: 127,
    totalFiles: 1543
  }
  */

  console.log(`✓ Detected ${detectionResult.features.length} features`);
  console.log(`  Assigned: ${detectionResult.totalFiles - detectionResult.unassignedFiles} files`);
  console.log(`  Unassigned: ${detectionResult.unassignedFiles} files`);
  console.log('');

  // Present features to user for selection
  AskUserQuestion({
    questions: [
      {
        question: "This codebase is large. Which features do you want to extract?",
        header: "Feature Scope",
        multiSelect: false,
        options: [
          {
            label: "All features (Recommended)",
            description: `Extract all ${detectionResult.features.length} features into separate outputs`
          },
          {
            label: "Specific feature only",
            description: "Choose one feature to extract (faster, focused)"
          },
          {
            label: "Full codebase",
            description: "Extract everything as one monolithic output (slower, may be overwhelming)"
          }
        ]
      }
    ]
  });

  // If user selected "Specific feature only"
  if (answer === "Specific feature only") {
    // Build dynamic options from detected features
    const featureOptions = detectionResult.features.map(feature => ({
      label: feature.name,
      description: `${feature.fileCount} files, ${feature.confidence * 100}% confidence`
    }));

    AskUserQuestion({
      questions: [
        {
          question: "Which feature do you want to extract?",
          header: "Select Feature",
          multiSelect: false,
          options: featureOptions
        },
        {
          question: "Do you want to refine the scope?",
          header: "Scope Refinement",
          multiSelect: true,
          options: [
            {label: "Exclude test files", description: "Skip **/*.test.ts, **/*.spec.ts"},
            {label: "Exclude documentation", description: "Skip **/*.md, **/docs/**"},
            {label: "Include shared utilities", description: "Add src/utils/**, src/lib/**"},
            {label: "Custom exclude patterns", description: "Manually specify patterns to exclude"}
          ]
        }
      ]
    });

    // If user selected "Custom exclude patterns"
    if (refinementAnswers.includes("Custom exclude patterns")) {
      const customPatterns = await askForInput("Enter glob patterns to exclude (comma-separated):");
      // Parse and apply custom exclude patterns
    }

    // Store selected feature scope
    selectedScope = {
      name: selectedFeature.name,
      includePaths: selectedFeature.scope.includePaths,
      excludePaths: buildExcludePatterns(refinementAnswers),
      keywords: selectedFeature.scope.keywords
    };
  }

  // If user selected "All features"
  if (answer === "All features") {
    console.log('📦 Will extract all features into separate outputs');
    console.log('   Estimated time: ~2-3 minutes per feature');
    console.log('');

    // Optionally ask about processing order
    AskUserQuestion({
      questions: [
        {
          question: "How should features be processed?",
          header: "Processing",
          multiSelect: false,
          options: [
            {label: "Sequential", description: "One at a time (safer, easier to debug)"},
            {label: "Parallel", description: "All at once (faster, more resource intensive)"}
          ]
        }
      ]
    });
  }
}
```

**Store feature selection:**
```json
{
  "featureMode": "all" | "specific" | "none",
  "selectedFeature": {
    "name": "Authentication",
    "scope": {
      "includePaths": ["src/auth/**", "src/features/auth/**"],
      "excludePaths": ["**/*.test.ts", "**/*.spec.ts"],
      "keywords": ["auth", "login", "session"]
    }
  },
  "processingMode": "sequential" | "parallel"
}
```

**Example Flow:**

```
🔍 Detected large codebase (1543 files). Running feature detection...
✓ Detected 8 features
  Assigned: 1416 files
  Unassigned: 127 files

┌─────────────────────────────────────────────────────────┐
│ This codebase is large. Which features do you want to  │
│ extract?                                                │
│                                                          │
│ ○ All features (Recommended)                           │
│   Extract all 8 features into separate outputs         │
│                                                          │
│ ● Specific feature only                                │
│   Choose one feature to extract (faster, focused)      │
│                                                          │
│ ○ Full codebase                                        │
│   Extract everything as one monolithic output          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Which feature do you want to extract?                   │
│                                                          │
│ ● Authentication                                        │
│   45 files, 90% confidence                             │
│                                                          │
│ ○ Payment                                               │
│   32 files, 85% confidence                             │
│                                                          │
│ ○ User Profile                                          │
│   28 files, 80% confidence                             │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Do you want to refine the scope?                        │
│                                                          │
│ ☑ Exclude test files                                   │
│   Skip **/*.test.ts, **/*.spec.ts                      │
│                                                          │
│ ☐ Exclude documentation                                │
│   Skip **/*.md, **/docs/**                             │
│                                                          │
│ ☐ Include shared utilities                             │
│   Add src/utils/**, src/lib/**                         │
└─────────────────────────────────────────────────────────┘

📦 Extracting Authentication feature...
   Scope: 45 files, excluding tests
   Keywords: auth, login, session
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

# With multi-AI debate for token validation
/octo:extract ./my-app --with-debate --debate-rounds 2

# Deep extraction with debate
/octo:extract ./my-app --depth deep --with-debate

# Feature detection for large codebases
/octo:extract ./my-app --detect-features

# Extract specific feature
/octo:extract ./my-app --feature authentication

# Feature extraction with debate
/octo:extract ./my-app --feature payment --with-debate
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
| `--with-debate` | flag | `false` | Enable multi-AI debate for token validation |
| `--debate-rounds` | number | `2` | Number of debate rounds (requires `--with-debate`) |
| `--feature` | string | - | Extract tokens for specific feature only |
| `--detect-features` | flag | `false` | Auto-detect features and generate index |
| `--feature-scope` | JSON string | - | Custom feature scope definition |

---

## Multi-AI Debate for Token Validation

The `--with-debate` flag enables a multi-AI debate system that validates and improves extracted design tokens through structured deliberation.

### How It Works

1. **Proposer Phase**: First AI analyzes extracted tokens for issues (naming, values, hierarchy, completeness, type safety)
2. **Critic Phase**: Second AI challenges the proposer's suggestions, identifies edge cases
3. **Synthesis Phase**: Third AI synthesizes consensus, resolves conflicts, produces final recommendations

### When to Use Debate

- **High-confidence validation**: Need certainty before committing tokens to production
- **Complex design systems**: Large token sets with intricate relationships
- **Team alignment**: Want AI-validated tokens that follow best practices
- **Quality gates**: Ensuring WCAG compliance, semantic naming, consistency

### Debate Output

Debate generates:
- **debate-audit-trail.md**: Full debate transcript with proposer, critic, and synthesis
- **Consensus items**: High-agreement recommendations (≥67% consensus threshold)
- **Improvements**: Auto-applicable changes with confidence scores
- **Conflict resolutions**: How disagreements were resolved

### Example Usage

```bash
# Standard debate (2 rounds)
/octo:extract ./my-app --with-debate

# Extended debate for complex systems (3 rounds)
/octo:extract ./my-app --with-debate --debate-rounds 3

# Combine with deep extraction
/octo:extract ./my-app --depth deep --with-debate
```

### Performance

- **Time**: +30-60 seconds per debate round (depends on token count)
- **Providers**: Requires Codex and/or Gemini CLI (graceful degradation if unavailable)
- **Token count**: Works best with 50-500 tokens; very large sets may take longer

---

## Feature Detection & Scoping

**For large codebases (500+ files), Claude will automatically detect features and guide you through an interactive selection process.** No need to know JSON or glob patterns upfront!

### How It Works

1. **Automatic Detection** (triggered for 500+ file codebases):
   - **Directory-based**: Detects features from `features/`, `modules/`, `services/` directories
   - **Keyword-based**: Identifies common patterns (auth, payment, user, product, etc.)
   - **Confidence scoring**: High confidence for directory-based (0.9), medium for keywords (0.7)

2. **Interactive Selection**:
   - Presents detected features with file counts and confidence scores
   - Lets you choose: all features, specific feature, or full codebase
   - Guides you through scope refinement (exclude tests, docs, etc.)
   - No JSON required - everything is handled through questions

3. **Feature Extraction**: Filters tokens and files to your selected scope using glob patterns and keywords

4. **Index Generation**: Creates master feature index with file counts, token counts, and extraction scripts

### When to Use Feature Detection

- **Large codebases** (500K+ LOC): Break down extraction into manageable chunks
- **Modular architecture**: Extract features independently for focused PRDs
- **Team organization**: Align extraction with team boundaries (auth team, payments team, etc.)
- **Iterative extraction**: Extract high-priority features first, others later

### Interactive Feature Selection (Recommended)

For large codebases, simply run:

```bash
# Claude automatically detects features and guides you through selection
/octo:extract ./my-app
```

**What happens:**
1. Detects 500+ files → Triggers automatic feature detection
2. Shows you: "Detected 8 features (Authentication, Payment, User Profile...)"
3. Asks: "Which features do you want to extract?"
   - All features (generates 8 separate outputs)
   - Specific feature (choose from list)
   - Full codebase (one monolithic output)
4. If you choose "Specific feature" → Shows feature list with confidence scores
5. Asks: "Refine scope?" → Options to exclude tests, docs, or add custom patterns
6. Proceeds with extraction using your selections

**No flags or JSON required!** The interactive flow handles everything.

### Manual Feature Extraction (Advanced)

If you already know which feature you want:

```bash
# Force feature detection (even for small codebases)
/octo:extract ./my-app --detect-features

# Skip detection, extract specific feature by name
/octo:extract ./my-app --feature authentication

# Combine with debate for validated extraction
/octo:extract ./my-app --feature payment --with-debate
```

### Custom Scopes (Expert Mode)

For programmatic/CI use or very specific scopes:

```bash
# Manually define scope with JSON
/octo:extract ./my-app --feature-scope '{
  "name":"auth",
  "includePaths":["src/auth/**","lib/auth/**"],
  "excludePaths":["**/*.test.ts"],
  "keywords":["auth","login","session"]
}'
```

**Note:** Most users don't need this - the interactive flow is more user-friendly.

### Output with Feature Detection

When `--detect-features` is enabled, the output includes:

```
octopus-extract/
└── project-name/
    └── timestamp/
        ├── features-index.json       # Master feature index
        ├── features-index.md          # Human-readable feature list
        ├── extract-all-features.sh    # Script to extract each feature
        └── 10_design/
            ├── tokens.json
            └── ...
```

When `--feature <name>` is used, tokens are filtered to only include that feature:

```
octopus-extract/
└── project-name/
    └── timestamp/
        ├── feature-metadata.json      # Feature info (file count, paths, etc.)
        └── 10_design/
            ├── tokens.json            # Tokens tagged with feature name
            └── ...
```

### Built-in Feature Keywords

The detector recognizes these common feature patterns:
- **Authentication**: auth, login, logout, session, signin, signup
- **Payment**: payment, checkout, billing, invoice, stripe, paypal
- **User**: user, profile, account, settings
- **Product**: product, catalog, item, inventory
- **Order**: order, cart, basket, shopping
- **Analytics**: analytics, tracking, metrics, stats
- **Notification**: notification, alert, email, sms
- **Admin**: admin, dashboard, management
- **Search**: search, filter, query
- **API**: api, endpoint, route, controller

### Performance

- **Detection time**: 1-3 seconds for most codebases
- **Accuracy**: 80-90% for well-organized codebases with clear feature boundaries
- **False positives**: Can be refined with custom scopes or exclude patterns

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
        │   ├── tokens.d.ts
        │   ├── tailwind.tokens.js
        │   ├── tokens.styled.ts
        │   ├── style-dictionary.config.js
        │   ├── tokens.schema.json
        │   ├── debate-audit-trail.md (if --with-debate)
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
