/**
 * Advanced Usage Examples
 * Demonstrates advanced features and custom integrations
 */

import {
  TailwindExtractor,
  CSSVariablesExtractor,
  TokenMerger,
  generateJSONOutput,
  generateCSSOutput,
  MergeStrategy,
  Token,
} from '../index';

/**
 * Example 1: Individual extractor usage
 */
async function individualExtractors() {
  console.log('Example 1: Individual Extractors\n');

  // Extract only from Tailwind
  const tailwindExtractor = new TailwindExtractor({
    includeCore: false,
    includeExtend: true,
  });

  const tailwindResult = await tailwindExtractor.extract('./my-project');
  console.log(`Tailwind tokens: ${tailwindResult.tokens.length}`);

  // Extract only CSS variables
  const cssExtractor = new CSSVariablesExtractor({
    selectors: [':root', '[data-theme="dark"]'],
  });

  const cssResult = await cssExtractor.extract('./my-project');
  console.log(`CSS variable tokens: ${cssResult.tokens.length}`);
}

/**
 * Example 2: Custom merge strategy
 */
async function customMergeStrategy() {
  console.log('\nExample 2: Custom Merge Strategy\n');

  // Extract from multiple sources
  const tailwindExtractor = new TailwindExtractor();
  const cssExtractor = new CSSVariablesExtractor();

  const tailwindResult = await tailwindExtractor.extract('./my-project');
  const cssResult = await cssExtractor.extract('./my-project');

  // Custom merge strategy: prefer CSS variables for colors, Tailwind for everything else
  const customStrategy: MergeStrategy = {
    shouldMerge: (existing, incoming) => {
      // Always merge if types match
      return existing.type === incoming.type;
    },
    onConflict: (existing, incoming) => {
      // For colors, prefer CSS variables
      if (existing.type === 'color' && incoming.source === 'css-variables') {
        return incoming;
      }

      // For everything else, prefer higher priority
      return existing.priority >= incoming.priority ? existing : incoming;
    },
  };

  const merger = new TokenMerger();
  const allTokens = [...tailwindResult.tokens, ...cssResult.tokens];
  const mergedTokens = merger.applyCustomStrategy(allTokens, customStrategy);

  console.log(`Merged tokens with custom strategy: ${mergedTokens.length}`);
}

/**
 * Example 3: Token filtering and transformation
 */
async function tokenFiltering() {
  console.log('\nExample 3: Token Filtering and Transformation\n');

  const extractor = new TailwindExtractor();
  const result = await extractor.extract('./my-project');

  // Filter tokens by type
  const colorTokens = result.tokens.filter(t => t.type === 'color');
  const dimensionTokens = result.tokens.filter(t => t.type === 'dimension');

  console.log(`Color tokens: ${colorTokens.length}`);
  console.log(`Dimension tokens: ${dimensionTokens.length}`);

  // Transform tokens to different format
  const themeObject = colorTokens.reduce((acc, token) => {
    const path = token.path.join('.');
    acc[path] = token.value;
    return acc;
  }, {} as Record<string, any>);

  console.log('Transformed to theme object:', Object.keys(themeObject).length, 'entries');
}

/**
 * Example 4: Multi-theme support
 */
async function multiThemeSupport() {
  console.log('\nExample 4: Multi-theme Support\n');

  // Extract light theme tokens
  const lightExtractor = new CSSVariablesExtractor({
    selectors: [':root', '[data-theme="light"]'],
  });

  const lightResult = await lightExtractor.extract('./my-project');

  // Extract dark theme tokens
  const darkExtractor = new CSSVariablesExtractor({
    selectors: ['[data-theme="dark"]'],
  });

  const darkResult = await darkExtractor.extract('./my-project');

  console.log(`Light theme tokens: ${lightResult.tokens.length}`);
  console.log(`Dark theme tokens: ${darkResult.tokens.length}`);

  // Generate separate CSS files for each theme
  await generateCSSOutput(lightResult.tokens, {
    outputPath: './tokens/light-theme.css',
    selector: '[data-theme="light"]',
  });

  await generateCSSOutput(darkResult.tokens, {
    outputPath: './tokens/dark-theme.css',
    selector: '[data-theme="dark"]',
  });

  console.log('Generated theme-specific CSS files');
}

/**
 * Example 5: Token categorization
 */
async function tokenCategorization() {
  console.log('\nExample 5: Token Categorization\n');

  const extractor = new TailwindExtractor();
  const result = await extractor.extract('./my-project');

  // Group tokens by category
  const byCategory = result.tokens.reduce((acc, token) => {
    const category = token.category || 'other';
    if (!acc[category]) {
      acc[category] = [];
    }
    acc[category].push(token);
    return acc;
  }, {} as Record<string, Token[]>);

  console.log('Tokens by category:');
  for (const [category, tokens] of Object.entries(byCategory)) {
    console.log(`  ${category}: ${tokens.length}`);
  }

  // Generate category-specific output files
  for (const [category, tokens] of Object.entries(byCategory)) {
    await generateJSONOutput(tokens, {
      outputPath: `./tokens/${category}.json`,
    });
  }

  console.log('Generated category-specific JSON files');
}

/**
 * Example 6: Token validation and reporting
 */
async function tokenValidation() {
  console.log('\nExample 6: Token Validation\n');

  const extractor = new TailwindExtractor();
  const result = await extractor.extract('./my-project');

  const merger = new TokenMerger({ validateTokens: true });
  const { valid, invalid } = merger.validateTokens(result.tokens);

  console.log(`Valid tokens: ${valid.length}`);
  console.log(`Invalid tokens: ${invalid.length}`);

  if (invalid.length > 0) {
    console.log('\nInvalid tokens:');
    for (const token of invalid.slice(0, 5)) {
      console.log(`  ${token.name}: ${token.metadata?.validationError}`);
    }
  }
}

/**
 * Example 7: Incremental extraction
 */
async function incrementalExtraction() {
  console.log('\nExample 7: Incremental Extraction\n');

  // Load existing tokens
  let existingTokens: Token[] = [];
  try {
    // In real scenario, load from tokens.json
    // existingTokens = JSON.parse(fs.readFileSync('./tokens/tokens.json', 'utf-8'));
  } catch (error) {
    console.log('No existing tokens found, starting fresh');
  }

  // Extract new tokens
  const extractor = new TailwindExtractor();
  const result = await extractor.extract('./my-project');

  // Merge with existing tokens
  const merger = new TokenMerger();
  const { tokens, conflicts } = merger.merge([existingTokens, result.tokens]);

  console.log(`Total tokens after incremental extraction: ${tokens.length}`);
  console.log(`New conflicts: ${conflicts.length}`);
}

/**
 * Example 8: Token aliasing and references
 */
async function tokenAliasing() {
  console.log('\nExample 8: Token Aliasing\n');

  const extractor = new TailwindExtractor();
  const result = await extractor.extract('./my-project');

  // Find tokens that reference other tokens
  const referencedTokens = result.tokens.filter(token =>
    typeof token.value === 'string' && token.value.startsWith('{')
  );

  console.log(`Tokens with references: ${referencedTokens.length}`);

  // Create alias map
  const aliasMap: Record<string, string> = {};
  for (const token of referencedTokens) {
    aliasMap[token.name] = token.value;
  }

  console.log('Alias map created with', Object.keys(aliasMap).length, 'entries');
}

/**
 * Example 9: Export to platform-specific formats
 */
async function platformSpecificExport() {
  console.log('\nExample 9: Platform-specific Export\n');

  const extractor = new TailwindExtractor();
  const result = await extractor.extract('./my-project');

  // Convert to iOS Swift format
  const swiftTokens = result.tokens
    .filter(t => t.type === 'color')
    .map(t => {
      const name = t.path
        .map((p, i) => (i === 0 ? p : p.charAt(0).toUpperCase() + p.slice(1)))
        .join('');
      return `static let ${name} = UIColor(hex: "${t.value}")`;
    });

  console.log('Generated Swift color definitions:', swiftTokens.length);

  // Convert to Android XML format
  const androidColors = result.tokens
    .filter(t => t.type === 'color')
    .map(t => {
      const name = t.path.join('_');
      return `<color name="${name}">${t.value}</color>`;
    });

  console.log('Generated Android color resources:', androidColors.length);
}

/**
 * Example 10: Conflict analysis and reporting
 */
async function conflictAnalysis() {
  console.log('\nExample 10: Conflict Analysis\n');

  const extractor1 = new TailwindExtractor();
  const extractor2 = new CSSVariablesExtractor();

  const result1 = await extractor1.extract('./my-project');
  const result2 = await extractor2.extract('./my-project');

  const merger = new TokenMerger();
  const { tokens, conflicts } = merger.merge([result1.tokens, result2.tokens]);

  // Get conflict statistics
  const stats = merger.getConflictStats();

  console.log('Conflict Statistics:');
  console.log(`  Total conflicts: ${stats.total}`);
  console.log(`  Auto-resolved: ${stats.auto}`);
  console.log(`  Manual resolution needed: ${stats.manual}`);
  console.log('  By source:');

  for (const [source, count] of Object.entries(stats.bySource)) {
    console.log(`    ${source}: ${count}`);
  }

  // Analyze conflict patterns
  const conflictsByType = conflicts.reduce((acc, conflict) => {
    const type = conflict.tokens[0].type || 'unknown';
    acc[type] = (acc[type] || 0) + 1;
    return acc;
  }, {} as Record<string, number>);

  console.log('  By token type:');
  for (const [type, count] of Object.entries(conflictsByType)) {
    console.log(`    ${type}: ${count}`);
  }
}

/**
 * Run all advanced examples
 */
async function runAllAdvancedExamples() {
  console.log('='.repeat(60));
  console.log('Token Extraction Pipeline - Advanced Examples');
  console.log('='.repeat(60));

  try {
    await individualExtractors();
    await customMergeStrategy();
    await tokenFiltering();
    await multiThemeSupport();
    await tokenCategorization();
    await tokenValidation();
    await incrementalExtraction();
    await tokenAliasing();
    await platformSpecificExport();
    await conflictAnalysis();

    console.log('\n' + '='.repeat(60));
    console.log('All advanced examples completed!');
    console.log('='.repeat(60));
  } catch (error) {
    console.error('Error running advanced examples:', error);
    process.exit(1);
  }
}

// Run examples if executed directly
if (require.main === module) {
  runAllAdvancedExamples();
}

export {
  individualExtractors,
  customMergeStrategy,
  tokenFiltering,
  multiThemeSupport,
  tokenCategorization,
  tokenValidation,
  incrementalExtraction,
  tokenAliasing,
  platformSpecificExport,
  conflictAnalysis,
};
