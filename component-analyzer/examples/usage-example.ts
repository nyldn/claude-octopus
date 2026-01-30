/**
 * Component Analyzer - Usage Examples
 * Demonstrates various ways to use the component analysis engine
 */

import { ComponentAnalysisEngine, InventoryGenerator, ComponentFramework } from '../src';
import * as path from 'path';

// ============================================================================
// Example 1: Basic Analysis
// ============================================================================

async function basicAnalysis() {
  console.log('Example 1: Basic Analysis\n');

  const engine = new ComponentAnalysisEngine({
    rootDir: path.join(__dirname, 'sample-components'),
    include: ['**/*.tsx', '**/*.ts'],
    exclude: ['**/*.test.*', '**/node_modules/**'],
    frameworks: [ComponentFramework.REACT],
    detectVariants: true,
    trackUsages: true,
    extractDocs: true,
    maxFileSize: 1024 * 1024,
    parallelism: 4
  });

  const result = await engine.analyze();

  console.log(`Total Components: ${result.summary.totalComponents}`);
  console.log(`Total Props: ${result.summary.totalProps}`);
  console.log(`Total Variants: ${result.summary.totalVariants}`);
  console.log(`Analysis Time: ${result.summary.analysisTimeMs}ms\n`);

  // Display component names
  result.components.forEach(component => {
    console.log(`- ${component.name} (${component.pattern})`);
  });

  console.log('\n---\n');
}

// ============================================================================
// Example 2: Generate Multiple Formats
// ============================================================================

async function generateMultipleFormats() {
  console.log('Example 2: Generate Multiple Formats\n');

  const engine = new ComponentAnalysisEngine({
    rootDir: path.join(__dirname),
    include: ['**/*.tsx'],
    exclude: ['**/node_modules/**'],
    frameworks: [ComponentFramework.REACT],
    detectVariants: true,
    trackUsages: true,
    extractDocs: true,
    maxFileSize: 1024 * 1024,
    parallelism: 4
  });

  const result = await engine.analyze();
  const generator = new InventoryGenerator();

  // Generate JSON
  generator.generateInventory(result, {
    format: 'json',
    outputPath: path.join(__dirname, 'output', 'components.json'),
    includeUsages: true,
    includeVariants: true,
    prettify: true
  });
  console.log('✓ Generated components.json');

  // Generate CSV
  generator.generateInventory(result, {
    format: 'csv',
    outputPath: path.join(__dirname, 'output', 'components.csv'),
    includeUsages: true,
    includeVariants: true,
    prettify: true
  });
  console.log('✓ Generated components.csv');

  // Generate Markdown
  generator.generateInventory(result, {
    format: 'markdown',
    outputPath: path.join(__dirname, 'output', 'COMPONENTS.md'),
    includeUsages: true,
    includeVariants: true,
    prettify: true
  });
  console.log('✓ Generated COMPONENTS.md');

  // Generate Statistics
  const stats = generator.generateStatistics(result);
  require('fs').writeFileSync(
    path.join(__dirname, 'output', 'STATISTICS.md'),
    stats,
    'utf-8'
  );
  console.log('✓ Generated STATISTICS.md\n');

  console.log('---\n');
}

// ============================================================================
// Example 3: Analyze Specific Component
// ============================================================================

async function analyzeSpecificComponent() {
  console.log('Example 3: Analyze Specific Component\n');

  const engine = new ComponentAnalysisEngine({
    rootDir: path.join(__dirname),
    include: ['sample-components.tsx'],
    exclude: [],
    frameworks: [ComponentFramework.REACT],
    detectVariants: true,
    trackUsages: false,
    extractDocs: true,
    maxFileSize: 1024 * 1024,
    parallelism: 1
  });

  const result = await engine.analyze();

  // Find Button component
  const button = engine.findComponent(result.components, 'Button');

  if (button) {
    console.log(`Component: ${button.name}`);
    console.log(`Pattern: ${button.pattern}`);
    console.log(`Props: ${button.props.length}\n`);

    console.log('Props Details:');
    button.props.forEach(prop => {
      console.log(`  - ${prop.name}: ${prop.type}${prop.required ? ' (required)' : ''}`);
      if (prop.description) {
        console.log(`    ${prop.description}`);
      }
    });

    console.log(`\nVariants: ${button.variants.length}`);
    button.variants.forEach(variant => {
      console.log(`  - ${variant.name}: ${variant.description}`);
    });

    console.log(`\nComplexity: ${button.complexity.cyclomaticComplexity}`);
    console.log(`Lines of Code: ${button.complexity.linesOfCode}`);
  }

  console.log('\n---\n');
}

// ============================================================================
// Example 4: Most Used Components
// ============================================================================

async function findMostUsedComponents() {
  console.log('Example 4: Most Used Components\n');

  const engine = new ComponentAnalysisEngine({
    rootDir: path.join(__dirname, '../src'),
    include: ['**/*.tsx', '**/*.ts'],
    exclude: ['**/*.test.*', '**/node_modules/**'],
    frameworks: [ComponentFramework.REACT],
    detectVariants: false,
    trackUsages: true,
    extractDocs: false,
    maxFileSize: 1024 * 1024,
    parallelism: 4
  });

  const result = await engine.analyze();

  // Get most used components
  const mostUsed = engine.getMostUsed(result.components, 5);

  console.log('Top 5 Most Used Components:\n');
  mostUsed.forEach((component, index) => {
    console.log(`${index + 1}. ${component.name}`);
    console.log(`   Usages: ${component.usages.length}`);
    console.log(`   Files: ${new Set(component.usages.map(u => u.filePath)).size}\n`);
  });

  console.log('---\n');
}

// ============================================================================
// Example 5: Component Complexity Analysis
// ============================================================================

async function analyzeComplexity() {
  console.log('Example 5: Component Complexity Analysis\n');

  const engine = new ComponentAnalysisEngine({
    rootDir: path.join(__dirname),
    include: ['**/*.tsx'],
    exclude: ['**/node_modules/**'],
    frameworks: [ComponentFramework.REACT],
    detectVariants: false,
    trackUsages: false,
    extractDocs: false,
    maxFileSize: 1024 * 1024,
    parallelism: 4
  });

  const result = await engine.analyze();

  // Get most complex components
  const mostComplex = engine.getMostComplex(result.components, 5);

  console.log('Top 5 Most Complex Components:\n');
  mostComplex.forEach((component, index) => {
    console.log(`${index + 1}. ${component.name}`);
    console.log(`   Cyclomatic Complexity: ${component.complexity.cyclomaticComplexity}`);
    console.log(`   Cognitive Complexity: ${component.complexity.cognitiveComplexity}`);
    console.log(`   Lines of Code: ${component.complexity.linesOfCode}\n`);
  });

  // Calculate averages
  const avgCyclomatic =
    result.components.reduce((sum, c) => sum + c.complexity.cyclomaticComplexity, 0) /
    result.components.length;

  const avgLOC =
    result.components.reduce((sum, c) => sum + c.complexity.linesOfCode, 0) /
    result.components.length;

  console.log('Averages:');
  console.log(`  Cyclomatic Complexity: ${avgCyclomatic.toFixed(2)}`);
  console.log(`  Lines of Code: ${avgLOC.toFixed(2)}\n`);

  console.log('---\n');
}

// ============================================================================
// Example 6: Framework Distribution
// ============================================================================

async function analyzeFrameworkDistribution() {
  console.log('Example 6: Framework Distribution\n');

  const engine = new ComponentAnalysisEngine({
    rootDir: path.join(__dirname, '../src'),
    include: ['**/*.tsx', '**/*.ts', '**/*.vue', '**/*.svelte'],
    exclude: ['**/node_modules/**'],
    frameworks: [ComponentFramework.REACT, ComponentFramework.VUE, ComponentFramework.SVELTE],
    detectVariants: false,
    trackUsages: false,
    extractDocs: false,
    maxFileSize: 1024 * 1024,
    parallelism: 4
  });

  const result = await engine.analyze();

  console.log('Framework Distribution:\n');
  Object.entries(result.summary.byFramework).forEach(([framework, count]) => {
    if (count > 0) {
      const percentage = ((count / result.summary.totalComponents) * 100).toFixed(1);
      console.log(`${framework}: ${count} (${percentage}%)`);
    }
  });

  console.log('\nPattern Distribution:\n');
  Object.entries(result.summary.byPattern).forEach(([pattern, count]) => {
    if (count > 0) {
      const percentage = ((count / result.summary.totalComponents) * 100).toFixed(1);
      console.log(`${pattern}: ${count} (${percentage}%)`);
    }
  });

  console.log('\n---\n');
}

// ============================================================================
// Example 7: Variant Detection Analysis
// ============================================================================

async function analyzeVariants() {
  console.log('Example 7: Variant Detection Analysis\n');

  const engine = new ComponentAnalysisEngine({
    rootDir: path.join(__dirname),
    include: ['sample-components.tsx'],
    exclude: [],
    frameworks: [ComponentFramework.REACT],
    detectVariants: true,
    trackUsages: false,
    extractDocs: false,
    maxFileSize: 1024 * 1024,
    parallelism: 1
  });

  const result = await engine.analyze();

  console.log('Components with Variants:\n');
  result.components
    .filter(c => c.variants.length > 0)
    .forEach(component => {
      console.log(`${component.name}:`);
      console.log(`  Total Variants: ${component.variants.length}`);

      // Group by discriminator
      const byDiscriminator = component.variants.reduce((acc, v) => {
        if (!acc[v.discriminator]) acc[v.discriminator] = [];
        acc[v.discriminator].push(v);
        return acc;
      }, {} as Record<string, any[]>);

      Object.entries(byDiscriminator).forEach(([discriminator, variants]) => {
        console.log(`  ${discriminator}:`);
        variants.forEach(v => {
          console.log(`    - ${v.discriminatorValue}`);
        });
      });
      console.log('');
    });

  console.log('---\n');
}

// ============================================================================
// Run All Examples
// ============================================================================

async function main() {
  console.log('='.repeat(80));
  console.log('Component Analysis Engine - Usage Examples');
  console.log('='.repeat(80));
  console.log('\n');

  try {
    await basicAnalysis();
    await analyzeSpecificComponent();
    await analyzeComplexity();
    await analyzeVariants();
    await generateMultipleFormats();

    // These examples require actual projects
    // await findMostUsedComponents();
    // await analyzeFrameworkDistribution();

  } catch (error) {
    console.error('Error:', error);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

export {
  basicAnalysis,
  generateMultipleFormats,
  analyzeSpecificComponent,
  findMostUsedComponents,
  analyzeComplexity,
  analyzeFrameworkDistribution,
  analyzeVariants
};
