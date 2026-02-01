/**
 * Token Extraction Pipeline
 * Main orchestrator for extracting, merging, and outputting design tokens
 */

import * as path from 'path';
import {
  Token,
  ExtractionResult,
  ExtractionOptions,
  ExtractionError,
  TokenConflict,
  TokenSource,
  OutputFiles,
} from './types';
import { TailwindExtractor } from './extractors/tailwind';
import { CSSVariablesExtractor } from './extractors/css-variables';
import { ThemeFileExtractor } from './extractors/theme-file';
import { StyledComponentsExtractor } from './extractors/styled-components';
import { TokenMerger, applyPriorities, DEFAULT_SOURCE_PRIORITIES } from './merger';
import { generateJSONOutput } from './outputs/json';
import { generateCSSOutput } from './outputs/css';
import { generateMarkdownOutput } from './outputs/markdown';
import { generateTypeScriptOutput } from './outputs/typescript';
import { generateTailwindConfigOutput } from './outputs/tailwind-config';
import { generateStyledComponentsOutput } from './outputs/styled-components';
import { generateStyleDictionaryOutput } from './outputs/style-dictionary';
import { generateSchemaOutput } from './outputs/schema';
import { AccessibilityAuditor } from './accessibility/accessibility-audit';
import { AccessibilityReport } from './accessibility/types';

export class TokenExtractionPipeline {
  private options: ExtractionOptions;
  private projectRoot: string;
  private errors: ExtractionError[] = [];
  private accessibilityReport?: AccessibilityReport;

  constructor(projectRoot: string, options: ExtractionOptions = {}) {
    this.projectRoot = projectRoot;
    this.options = {
      conflictResolution: 'priority',
      outputFormats: ['json', 'css', 'markdown'],
      outputDir: path.join(projectRoot, 'design-tokens'),
      preserveOriginalKeys: true,
      validateTokens: true,
      sourcePriorities: DEFAULT_SOURCE_PRIORITIES,
      ...options,
    };
  }

  /**
   * Execute the full extraction pipeline
   */
  async execute(): Promise<ExtractionResult> {
    this.errors = [];

    console.log('Starting token extraction pipeline...');
    console.log(`Project root: ${this.projectRoot}`);
    console.log(`Output directory: ${this.options.outputDir}`);
    console.log('');

    // Step 1: Extract tokens from all sources
    const extractionResults = await this.extractFromAllSources();

    // Step 2: Apply priorities
    const tokenLists = extractionResults.map(result =>
      applyPriorities(result.tokens, this.options.sourcePriorities)
    );

    // Step 3: Merge tokens and resolve conflicts
    const { tokens, conflicts } = await this.mergeTokens(tokenLists);

    console.log(`Total tokens after merge: ${tokens.length}`);
    console.log(`Conflicts detected: ${conflicts.length}`);
    console.log('');

    // Step 4: Validate tokens
    const { valid: validTokens, invalid: invalidTokens } = await this.validateTokens(tokens);

    if (invalidTokens.length > 0) {
      console.warn(`Warning: ${invalidTokens.length} invalid tokens found`);
      for (const token of invalidTokens) {
        this.errors.push({
          source: token.source,
          message: `Invalid token: ${token.name} - ${token.metadata?.validationError}`,
        });
      }
    }

    // Step 4.5: Run accessibility audit (if enabled)
    if (this.options.accessibility?.enabled) {
      this.accessibilityReport = await this.runAccessibilityAudit(validTokens);
    }

    // Step 4.6: Generate accessibility tokens (if enabled and audit ran)
    let tokensWithAccessibility = validTokens;
    if (this.accessibilityReport && this.options.accessibility?.enabled) {
      tokensWithAccessibility = await this.generateAccessibilityTokens(validTokens, this.accessibilityReport);
    }

    // Step 5: Generate outputs
    const outputFiles = await this.generateOutputs(tokensWithAccessibility, conflicts);

    console.log('Pipeline execution completed!');
    console.log('');

    // Build extraction result
    const result: ExtractionResult = {
      tokens: tokensWithAccessibility,
      conflicts,
      errors: this.errors,
      sources: this.buildSourcesSummary(extractionResults),
    };

    this.printSummary(result, outputFiles);

    return result;
  }

  /**
   * Extract tokens from all configured sources
   */
  private async extractFromAllSources(): Promise<
    Array<{ source: TokenSource; tokens: Token[]; errors: ExtractionError[] }>
  > {
    const results: Array<{
      source: TokenSource;
      tokens: Token[];
      errors: ExtractionError[];
    }> = [];

    // Check which sources to include/exclude
    const shouldExtract = (source: TokenSource): boolean => {
      if (this.options.excludeSources?.includes(source)) {
        return false;
      }
      if (
        this.options.includeSources &&
        this.options.includeSources.length > 0 &&
        !this.options.includeSources.includes(source)
      ) {
        return false;
      }
      return true;
    };

    // Extract from Tailwind config
    if (shouldExtract(TokenSource.TAILWIND_CONFIG)) {
      console.log('Extracting from Tailwind config...');
      const extractor = new TailwindExtractor();
      const result = await extractor.extract(this.projectRoot);
      results.push({
        source: TokenSource.TAILWIND_CONFIG,
        tokens: result.tokens,
        errors: result.errors,
      });
      console.log(`  Found ${result.tokens.length} tokens`);
      if (result.errors.length > 0) {
        this.errors.push(...result.errors);
      }
    }

    // Extract from CSS variables
    if (shouldExtract(TokenSource.CSS_VARIABLES)) {
      console.log('Extracting from CSS variables...');
      const extractor = new CSSVariablesExtractor();
      const result = await extractor.extract(this.projectRoot);
      results.push({
        source: TokenSource.CSS_VARIABLES,
        tokens: result.tokens,
        errors: result.errors,
      });
      console.log(`  Found ${result.tokens.length} tokens`);
      if (result.errors.length > 0) {
        this.errors.push(...result.errors);
      }
    }

    // Extract from theme files
    if (shouldExtract(TokenSource.THEME_FILE)) {
      console.log('Extracting from theme files...');
      const extractor = new ThemeFileExtractor();
      const result = await extractor.extract(this.projectRoot);
      results.push({
        source: TokenSource.THEME_FILE,
        tokens: result.tokens,
        errors: result.errors,
      });
      console.log(`  Found ${result.tokens.length} tokens`);
      if (result.errors.length > 0) {
        this.errors.push(...result.errors);
      }
    }

    // Extract from styled-components/emotion
    if (
      shouldExtract(TokenSource.STYLED_COMPONENTS) ||
      shouldExtract(TokenSource.EMOTION_THEME)
    ) {
      console.log('Extracting from styled-components/emotion...');
      const extractor = new StyledComponentsExtractor();
      const result = await extractor.extract(this.projectRoot);
      results.push({
        source: TokenSource.STYLED_COMPONENTS,
        tokens: result.tokens,
        errors: result.errors,
      });
      console.log(`  Found ${result.tokens.length} tokens`);
      if (result.errors.length > 0) {
        this.errors.push(...result.errors);
      }
    }

    console.log('');
    return results;
  }

  /**
   * Merge tokens from multiple sources
   */
  private async mergeTokens(
    tokenLists: Token[][]
  ): Promise<{ tokens: Token[]; conflicts: TokenConflict[] }> {
    console.log('Merging tokens from all sources...');

    const merger = new TokenMerger(this.options);
    const result = merger.merge(tokenLists);

    console.log(`Merge complete. ${result.conflicts.length} conflicts detected.`);

    if (result.conflicts.length > 0) {
      const stats = merger.getConflictStats();
      console.log(`  Auto-resolved: ${stats.auto}`);
      console.log(`  Manual resolution needed: ${stats.manual}`);
    }

    console.log('');
    return result;
  }

  /**
   * Validate tokens
   */
  private async validateTokens(
    tokens: Token[]
  ): Promise<{ valid: Token[]; invalid: Token[] }> {
    if (!this.options.validateTokens) {
      return { valid: tokens, invalid: [] };
    }

    console.log('Validating tokens...');

    const merger = new TokenMerger(this.options);
    const result = merger.validateTokens(tokens);

    console.log(`  Valid: ${result.valid.length}`);
    console.log(`  Invalid: ${result.invalid.length}`);
    console.log('');

    return result;
  }

  /**
   * Run accessibility audit on tokens
   */
  private async runAccessibilityAudit(tokens: Token[]): Promise<AccessibilityReport> {
    console.log('Running accessibility audit...');

    const auditor = new AccessibilityAuditor({
      targetLevel: this.options.accessibility?.targetLevel || 'AA',
      generateFocusStates: this.options.accessibility?.generateFocusStates ?? true,
      generateTouchTargets: this.options.accessibility?.generateTouchTargets ?? true,
      generateHighContrastAlternatives: this.options.accessibility?.generateHighContrastAlternatives ?? false,
    });

    const report = auditor.auditTokens(tokens);

    console.log(`  Tested ${report.totalColorPairs} color pairs`);
    console.log(`  WCAG AA: ${report.summary.passAA}/${report.totalColorPairs} (${report.summary.percentCompliant.toFixed(1)}%)`);
    console.log(`  Violations: ${report.summary.fail}`);
    console.log('');

    return report;
  }

  /**
   * Generate accessibility tokens
   */
  private async generateAccessibilityTokens(
    tokens: Token[],
    report: AccessibilityReport
  ): Promise<Token[]> {
    console.log('Generating accessibility tokens...');

    const auditor = new AccessibilityAuditor({
      targetLevel: this.options.accessibility?.targetLevel || 'AA',
      generateFocusStates: this.options.accessibility?.generateFocusStates ?? true,
      generateTouchTargets: this.options.accessibility?.generateTouchTargets ?? true,
      generateHighContrastAlternatives: this.options.accessibility?.generateHighContrastAlternatives ?? false,
    });

    const accessibilityTokens: Token[] = [];

    if (this.options.accessibility?.generateFocusStates) {
      accessibilityTokens.push(...auditor.generateFocusStates(tokens));
    }

    if (this.options.accessibility?.generateTouchTargets) {
      accessibilityTokens.push(...auditor.generateTouchTargets());
    }

    console.log(`  Generated ${accessibilityTokens.length} accessibility tokens`);
    console.log('');

    return [...tokens, ...accessibilityTokens];
  }

  /**
   * Generate output files
   */
  private async generateOutputs(
    tokens: Token[],
    conflicts: TokenConflict[]
  ): Promise<OutputFiles> {
    console.log('Generating output files...');

    const outputFiles: OutputFiles = {};
    const outputFormats = this.options.outputFormats || [];

    // Generate JSON output
    if (outputFormats.includes('json')) {
      const outputPath = path.join(this.options.outputDir!, 'tokens.json');
      await generateJSONOutput(tokens, {
        outputPath,
        prettify: true,
        indent: 2,
      });
      outputFiles.json = outputPath;
      console.log(`  Generated: ${outputPath}`);
    }

    // Generate CSS output
    if (outputFormats.includes('css')) {
      const outputPath = path.join(this.options.outputDir!, 'tokens.css');
      await generateCSSOutput(tokens, {
        outputPath,
        selector: ':root',
        includeComments: true,
        groupByCategory: true,
      });
      outputFiles.css = outputPath;
      console.log(`  Generated: ${outputPath}`);
    }

    // Generate Markdown output
    if (outputFormats.includes('markdown')) {
      const outputPath = path.join(this.options.outputDir!, 'tokens.md');
      await generateMarkdownOutput(
        tokens,
        {
          outputPath,
          includeConflicts: true,
          includeMetadata: true,
          groupByCategory: true,
          includeStats: true,
          accessibilityReport: this.accessibilityReport,
        },
        conflicts
      );
      outputFiles.markdown = outputPath;
      console.log(`  Generated: ${outputPath}`);
    }

    // Generate TypeScript output
    if (outputFormats.includes('typescript')) {
      const outputPath = path.join(this.options.outputDir!, 'tokens.ts');
      await generateTypeScriptOutput(tokens, {
        outputPath,
        generateTypes: true,
        generateConstants: true,
        exportType: 'both',
      });
      outputFiles.typescript = outputPath;
      console.log(`  Generated: ${outputPath}`);
      console.log(`  Generated: ${outputPath.replace(/\.ts$/, '.d.ts')}`);
    }

    // Generate Tailwind config output
    if (outputFormats.includes('tailwind')) {
      const outputPath = path.join(this.options.outputDir!, 'tailwind.tokens.js');
      await generateTailwindConfigOutput(tokens, {
        outputPath,
        mode: 'extend',
        includeComments: true,
      });
      outputFiles.tailwind = outputPath;
      console.log(`  Generated: ${outputPath}`);
    }

    // Generate Styled Components output
    if (outputFormats.includes('styled-components')) {
      const outputPath = path.join(this.options.outputDir!, 'tokens.styled.ts');
      await generateStyledComponentsOutput(tokens, {
        outputPath,
        includeTypes: true,
        includeComments: true,
      });
      outputFiles.styledComponents = outputPath;
      console.log(`  Generated: ${outputPath}`);
    }

    // Generate Style Dictionary output
    if (outputFormats.includes('style-dictionary')) {
      const outputPath = path.join(this.options.outputDir!, 'style-dictionary.config.js');
      await generateStyleDictionaryOutput(tokens, {
        outputPath,
        platforms: ['web', 'ios', 'android', 'scss'],
        includeComments: true,
      });
      outputFiles.styleDictionary = outputPath;
      console.log(`  Generated: ${outputPath}`);
      console.log(`  Generated: ${path.join(path.dirname(outputPath), 'tokens-source.json')}`);
    }

    // Generate JSON Schema output
    if (outputFormats.includes('schema')) {
      const outputPath = path.join(this.options.outputDir!, 'tokens.schema.json');
      await generateSchemaOutput(tokens, {
        outputPath,
        title: 'Design Tokens Schema',
        description: 'JSON Schema for design tokens validation',
      });
      outputFiles.schema = outputPath;
      console.log(`  Generated: ${outputPath}`);
    }

    console.log('');
    return outputFiles;
  }

  /**
   * Build sources summary
   */
  private buildSourcesSummary(
    extractionResults: Array<{
      source: TokenSource;
      tokens: Token[];
      errors: ExtractionError[];
    }>
  ): ExtractionResult['sources'] {
    const sources: ExtractionResult['sources'] = {};

    for (const result of extractionResults) {
      sources[result.source] = {
        found: result.tokens.length > 0 || result.errors.length > 0,
        tokensExtracted: result.tokens.length,
      };
    }

    return sources;
  }

  /**
   * Print execution summary
   */
  private printSummary(result: ExtractionResult, outputFiles: OutputFiles): void {
    console.log('='.repeat(60));
    console.log('EXTRACTION SUMMARY');
    console.log('='.repeat(60));
    console.log('');

    // Sources summary
    console.log('Sources:');
    for (const [source, info] of Object.entries(result.sources)) {
      const status = info.found ? '✓' : '✗';
      console.log(`  ${status} ${source}: ${info.tokensExtracted} tokens`);
    }
    console.log('');

    // Totals
    console.log(`Total Tokens: ${result.tokens.length}`);
    console.log(`Conflicts: ${result.conflicts.length}`);
    console.log(`Errors: ${result.errors.length}`);
    console.log('');

    // Output files
    console.log('Output Files:');
    if (outputFiles.json) {
      console.log(`  - ${outputFiles.json}`);
    }
    if (outputFiles.css) {
      console.log(`  - ${outputFiles.css}`);
    }
    if (outputFiles.markdown) {
      console.log(`  - ${outputFiles.markdown}`);
    }
    console.log('');

    // Errors
    if (result.errors.length > 0) {
      console.log('Errors:');
      for (const error of result.errors) {
        console.log(`  - [${error.source}] ${error.message}`);
      }
      console.log('');
    }

    // Manual conflicts
    const manualConflicts = result.conflicts.filter(c => c.resolution === 'manual');
    if (manualConflicts.length > 0) {
      console.log('⚠️  Manual Resolution Required:');
      for (const conflict of manualConflicts) {
        console.log(`  - ${conflict.path.join('.')}`);
        console.log(`    Conflicting sources: ${conflict.tokens.map(t => t.source).join(', ')}`);
      }
      console.log('');
    }

    console.log('='.repeat(60));
  }
}

/**
 * Convenience function to run the pipeline
 */
export async function runTokenExtraction(
  projectRoot: string,
  options?: ExtractionOptions
): Promise<ExtractionResult> {
  const pipeline = new TokenExtractionPipeline(projectRoot, options);
  return pipeline.execute();
}
