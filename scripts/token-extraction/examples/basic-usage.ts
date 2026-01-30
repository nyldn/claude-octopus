/**
 * Basic Usage Examples
 * Demonstrates common use cases for the token extraction pipeline
 */

import { runTokenExtraction, TokenExtractionPipeline } from '../index';

/**
 * Example 1: Basic extraction with default settings
 */
async function basicExtraction() {
  console.log('Example 1: Basic Extraction\n');

  const result = await runTokenExtraction('./my-project');

  console.log(`Extracted ${result.tokens.length} tokens`);
  console.log(`Conflicts: ${result.conflicts.length}`);
  console.log(`Errors: ${result.errors.length}`);
}

/**
 * Example 2: Extract only from specific sources
 */
async function extractFromSpecificSources() {
  console.log('\nExample 2: Extract from Specific Sources\n');

  const result = await runTokenExtraction('./my-project', {
    includeSources: ['tailwind.config', 'css-variables'],
  });

  console.log(`Extracted ${result.tokens.length} tokens`);

  // Show which sources were used
  for (const [source, info] of Object.entries(result.sources)) {
    if (info.found) {
      console.log(`  ${source}: ${info.tokensExtracted} tokens`);
    }
  }
}

/**
 * Example 3: Generate only specific output formats
 */
async function customOutputFormats() {
  console.log('\nExample 3: Custom Output Formats\n');

  const result = await runTokenExtraction('./my-project', {
    outputFormats: ['json'], // Only generate JSON
    outputDir: './tokens',
  });

  console.log('Generated files:');
  console.log('  - tokens/tokens.json');
}

/**
 * Example 4: Handle conflicts manually
 */
async function manualConflictResolution() {
  console.log('\nExample 4: Manual Conflict Resolution\n');

  const result = await runTokenExtraction('./my-project', {
    conflictResolution: 'manual',
  });

  // Review conflicts that need manual resolution
  const manualConflicts = result.conflicts.filter(c => c.resolution === 'manual');

  console.log(`Found ${manualConflicts.length} conflicts requiring manual resolution:`);

  for (const conflict of manualConflicts) {
    console.log(`\n  Token: ${conflict.path.join('.')}`);
    console.log('  Options:');

    for (const token of conflict.tokens) {
      console.log(`    - ${token.source}: ${token.value} (priority: ${token.priority})`);
    }
  }
}

/**
 * Example 5: Custom priority configuration
 */
async function customPriorities() {
  console.log('\nExample 5: Custom Priorities\n');

  const result = await runTokenExtraction('./my-project', {
    sourcePriorities: [
      { source: 'css-variables', priority: 10 }, // Give CSS vars highest priority
      { source: 'tailwind.config', priority: 8 },
      { source: 'theme-file', priority: 6 },
    ],
  });

  console.log('Tokens merged with custom priorities');
  console.log(`Total tokens: ${result.tokens.length}`);
}

/**
 * Example 6: Using the pipeline class directly
 */
async function directPipelineUsage() {
  console.log('\nExample 6: Direct Pipeline Usage\n');

  const pipeline = new TokenExtractionPipeline('./my-project', {
    outputFormats: ['json', 'css', 'markdown'],
    validateTokens: true,
  });

  const result = await pipeline.execute();

  console.log('Pipeline execution complete');
  console.log(`Valid tokens: ${result.tokens.length}`);
}

/**
 * Example 7: Error handling
 */
async function errorHandling() {
  console.log('\nExample 7: Error Handling\n');

  try {
    const result = await runTokenExtraction('./my-project');

    if (result.errors.length > 0) {
      console.error('Extraction completed with errors:');

      for (const error of result.errors) {
        console.error(`  [${error.source}] ${error.message}`);
        if (error.filePath) {
          console.error(`    File: ${error.filePath}`);
        }
      }
    } else {
      console.log('Extraction completed successfully!');
    }
  } catch (error) {
    console.error('Fatal error during extraction:', error);
  }
}

/**
 * Example 8: Extract and transform
 */
async function extractAndTransform() {
  console.log('\nExample 8: Extract and Transform\n');

  const result = await runTokenExtraction('./my-project');

  // Transform tokens for specific use case
  const colorTokens = result.tokens.filter(t => t.type === 'color');
  const spacingTokens = result.tokens.filter(t => t.category === 'spacing');

  console.log(`Color tokens: ${colorTokens.length}`);
  console.log(`Spacing tokens: ${spacingTokens.length}`);

  // Create custom mapping
  const cssVarMap: Record<string, string> = {};
  for (const token of result.tokens) {
    const varName = '--' + token.path.join('-');
    cssVarMap[varName] = String(token.value);
  }

  console.log(`Generated ${Object.keys(cssVarMap).length} CSS variables`);
}

/**
 * Example 9: Exclude specific sources
 */
async function excludeSources() {
  console.log('\nExample 9: Exclude Sources\n');

  const result = await runTokenExtraction('./my-project', {
    excludeSources: ['styled-components', 'emotion-theme'],
  });

  console.log('Extracted tokens excluding styled-components and emotion');
  console.log(`Total tokens: ${result.tokens.length}`);
}

/**
 * Example 10: No validation mode
 */
async function noValidation() {
  console.log('\nExample 10: Skip Validation\n');

  const result = await runTokenExtraction('./my-project', {
    validateTokens: false, // Skip validation for faster extraction
  });

  console.log('Extraction completed without validation');
  console.log(`Total tokens: ${result.tokens.length}`);
}

/**
 * Run all examples
 */
async function runAllExamples() {
  console.log('='.repeat(60));
  console.log('Token Extraction Pipeline - Usage Examples');
  console.log('='.repeat(60));

  try {
    await basicExtraction();
    await extractFromSpecificSources();
    await customOutputFormats();
    await manualConflictResolution();
    await customPriorities();
    await directPipelineUsage();
    await errorHandling();
    await extractAndTransform();
    await excludeSources();
    await noValidation();

    console.log('\n' + '='.repeat(60));
    console.log('All examples completed!');
    console.log('='.repeat(60));
  } catch (error) {
    console.error('Error running examples:', error);
    process.exit(1);
  }
}

// Run examples if executed directly
if (require.main === module) {
  runAllExamples();
}

export {
  basicExtraction,
  extractFromSpecificSources,
  customOutputFormats,
  manualConflictResolution,
  customPriorities,
  directPipelineUsage,
  errorHandling,
  extractAndTransform,
  excludeSources,
  noValidation,
};
