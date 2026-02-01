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
  FeatureScope,
  Feature,
  FeatureDetectionResult,
  FeatureExtractionResult,
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
import { BrowserExtractor } from './extractors/browser-extractor';
import { InteractionStatesExtractor } from './extractors/interaction-states';
import {
  runDebateOnTokens,
  applyDebateImprovements,
  generateAuditTrail,
} from './debate-integration';
import { DebateResult } from './types';
import { FeatureDetector } from './extractors/feature-detector';
import { FeatureScopedExtractor } from './extractors/feature-scoped-extractor';
import { generateFeatureIndex, generateFeatureExtractionScript } from './outputs/feature-index';

export class TokenExtractionPipeline {
  private options: ExtractionOptions;
  private projectRoot: string;
  private errors: ExtractionError[] = [];
  private accessibilityReport?: AccessibilityReport;
  private debateResult?: DebateResult;
  private debateAuditTrailPath?: string;
  private featureDetectionResult?: FeatureDetectionResult;
  private currentFeature?: Feature;
  private currentScope?: FeatureScope;

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
  async execute(): Promise<FeatureExtractionResult> {
    this.errors = [];

    console.log('Starting token extraction pipeline...');
    console.log(`Project root: ${this.projectRoot}`);
    console.log(`Output directory: ${this.options.outputDir}`);
    console.log('');

    // Step 0: Feature detection and scoping (if enabled)
    if (this.options.feature) {
      await this.handleFeatureOptions();
    }

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

    // Step 3.25: Apply feature scoping (if enabled)
    let scopedTokens = tokens;
    let scopedErrors = this.errors;
    if (this.currentScope) {
      const scoper = new FeatureScopedExtractor(this.currentScope);
      scopedTokens = scoper.filterTokens(tokens);
      scopedErrors = scoper.filterErrors(this.errors);
      this.errors = scopedErrors;

      // Create feature from scoped results
      this.currentFeature = {
        name: this.currentScope.name,
        fileCount: new Set(scopedTokens.map(t => t.metadata?.filePath).filter(Boolean)).size,
        tokenCount: scopedTokens.length,
        paths: this.currentScope.includePaths,
        scope: this.currentScope,
      };

      console.log(`After feature scoping (${this.currentScope.name}): ${scopedTokens.length} tokens`);
      console.log('');
    }

    // Step 3.5: Run debate if enabled
    let tokensAfterDebate = scopedTokens;
    if (this.options.debate?.enabled) {
      tokensAfterDebate = await this.runDebate(tokens);
    }

    // Step 4: Validate tokens
    const { valid: validTokens, invalid: invalidTokens} = await this.validateTokens(tokensAfterDebate);

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
    const result: FeatureExtractionResult = {
      tokens: tokensWithAccessibility,
      conflicts,
      errors: this.errors,
      sources: this.buildSourcesSummary(extractionResults),
      debate: this.debateResult,
      feature: this.currentFeature,
      featuresIndex: this.featureDetectionResult?.features,
    };

    this.printSummary(result, outputFiles);

    return result;
  }

  /**
   * Handle feature detection and scoping options
   */
  private async handleFeatureOptions(): Promise<void> {
    const detector = new FeatureDetector(this.projectRoot);

    // Option 1: Auto-detect all features
    if (this.options.feature?.detectFeatures) {
      console.log('Auto-detecting features in codebase...');
      this.featureDetectionResult = await detector.detectFeatures();

      console.log(`Detected ${this.featureDetectionResult.features.length} features:`);
      for (const feature of this.featureDetectionResult.features) {
        console.log(`  - ${feature.name}: ${feature.fileCount} files`);
      }
      console.log('');
    }

    // Option 2: Extract specific feature
    if (this.options.feature?.name) {
      console.log(`Extracting tokens for feature: ${this.options.feature.name}`);

      // Create scope for the feature
      const scope = await detector.createScope(this.options.feature.name);
      this.currentScope = scope;

      console.log(`Scope includes ${scope.includePaths.length} paths`);
      console.log('');
    }

    // Option 3: Use custom scope
    if (this.options.feature?.scope) {
      console.log(`Using custom feature scope: ${this.options.feature.scope.name}`);
      this.currentScope = this.options.feature.scope;

      console.log(`Scope includes ${this.currentScope.includePaths.length} paths`);
      console.log('');
    }
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

    // Extract from browser (if enabled)
    if (this.options.browserExtraction?.enabled && this.options.browserExtraction?.url) {
      console.log('Extracting from browser...');

      // Note: In real implementation, this would use MCP tools
      // For now, we'll use mock mode which doesn't require actual browser connection
      const browserExtractor = new BrowserExtractor({
        url: this.options.browserExtraction.url,
        tabId: 0, // Would come from MCP in real implementation
        selectors: this.options.browserExtraction.selectors,
        captureAll: !this.options.browserExtraction.selectors || this.options.browserExtraction.selectors.length === 0,
      });

      const browserResult = await browserExtractor.extract();
      results.push({
        source: TokenSource.BROWSER_EXTRACTION,
        tokens: browserResult.tokens,
        errors: browserResult.errors,
      });
      console.log(`  Found ${browserResult.tokens.length} tokens from browser`);
      if (browserResult.errors.length > 0) {
        this.errors.push(...browserResult.errors);
      }

      // Extract interaction states if enabled
      if (this.options.browserExtraction.includeInteractionStates) {
        console.log('Extracting interaction states...');
        const statesExtractor = new InteractionStatesExtractor({
          url: this.options.browserExtraction.url,
          tabId: 0, // Would come from MCP in real implementation
          selectors: this.options.browserExtraction.selectors,
        });

        const statesResult = await statesExtractor.extract();
        results.push({
          source: TokenSource.INTERACTION_STATES,
          tokens: statesResult.tokens,
          errors: statesResult.errors,
        });
        console.log(`  Found ${statesResult.tokens.length} interaction state tokens`);
        console.log(`  Captured ${statesResult.metadata.interactionStatesFound} states`);
        if (statesResult.errors.length > 0) {
          this.errors.push(...statesResult.errors);
        }
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
   * Run multi-AI debate on tokens
   */
  private async runDebate(tokens: Token[]): Promise<Token[]> {
    console.log('Running multi-AI debate on tokens...');

    const debateOptions = {
      rounds: this.options.debate?.rounds || 2,
      consensusThreshold: this.options.debate?.consensusThreshold || 0.67,
      providers: this.options.debate?.providers || ['claude', 'codex', 'gemini'],
      autoApply: this.options.debate?.autoApply ?? false,
      minConfidence: this.options.debate?.minConfidence || 0.75,
    };

    console.log(`  Rounds: ${debateOptions.rounds}`);
    console.log(`  Consensus threshold: ${debateOptions.consensusThreshold}`);
    console.log(`  Min confidence for auto-apply: ${debateOptions.minConfidence}`);
    console.log('');

    // Run debate
    const debateResult = await runDebateOnTokens(tokens, debateOptions);
    this.debateResult = debateResult;

    // Apply improvements if confidence threshold is met
    let improvedTokens = tokens;
    if (debateOptions.autoApply) {
      console.log('Applying high-confidence improvements...');
      improvedTokens = applyDebateImprovements(tokens, debateResult);
      console.log('');
    } else {
      console.log('Auto-apply disabled - improvements available in audit trail');
      console.log('');
    }

    // Generate and save audit trail
    const auditTrail = generateAuditTrail(tokens, improvedTokens, debateResult);
    const auditPath = path.join(this.options.outputDir!, 'debate-audit-trail.md');

    // Ensure output directory exists
    const fs = await import('fs/promises');
    await fs.mkdir(this.options.outputDir!, { recursive: true });
    await fs.writeFile(auditPath, auditTrail, 'utf-8');

    this.debateAuditTrailPath = auditPath;

    console.log(`Debate audit trail saved to: ${auditPath}`);
    console.log('');

    return improvedTokens;
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

    // Add debate audit trail if debate was run
    if (this.debateAuditTrailPath) {
      outputFiles.debateAuditTrail = this.debateAuditTrailPath;
    }

    // Generate feature index if features were detected
    if (this.featureDetectionResult) {
      const featureIndexPath = path.join(this.options.outputDir!, 'features-index.json');
      await generateFeatureIndex(this.featureDetectionResult, {
        outputPath: featureIndexPath,
        format: 'json',
        includeTokenCounts: true,
        includeFilePaths: true,
        prettify: true,
      });
      console.log(`  Generated: ${featureIndexPath}`);

      // Also generate markdown version
      const featureIndexMdPath = path.join(this.options.outputDir!, 'features-index.md');
      await generateFeatureIndex(this.featureDetectionResult, {
        outputPath: featureIndexMdPath,
        format: 'markdown',
        includeTokenCounts: true,
        includeFilePaths: true,
      });
      console.log(`  Generated: ${featureIndexMdPath}`);

      // Generate extraction script
      const scriptPath = path.join(this.options.outputDir!, 'extract-all-features.sh');
      await generateFeatureExtractionScript(this.featureDetectionResult.features, scriptPath);
      console.log(`  Generated: ${scriptPath}`);
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
  private printSummary(result: FeatureExtractionResult, outputFiles: OutputFiles): void {
    console.log('='.repeat(60));
    console.log('EXTRACTION SUMMARY');
    console.log('='.repeat(60));
    console.log('');

    // Feature information (if applicable)
    if (result.feature) {
      console.log('Feature:');
      console.log(`  Name: ${result.feature.name}`);
      console.log(`  Files: ${result.feature.fileCount}`);
      console.log(`  Tokens: ${result.feature.tokenCount}`);
      console.log('');
    }

    if (result.featuresIndex && result.featuresIndex.length > 0) {
      console.log('Detected Features:');
      for (const feature of result.featuresIndex) {
        console.log(`  - ${feature.name}: ${feature.fileCount} files, ${feature.tokenCount || 0} tokens`);
      }
      console.log('');
    }

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
): Promise<FeatureExtractionResult> {
  const pipeline = new TokenExtractionPipeline(projectRoot, options);
  return pipeline.execute();
}
