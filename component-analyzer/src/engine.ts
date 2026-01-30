/**
 * Component Analysis Engine
 * Main orchestration layer for component analysis
 */

import { glob } from 'glob';
import { readFileSync } from 'fs';
import * as path from 'path';
import {
  AnalysisConfig,
  AnalysisResult,
  ComponentMetadata,
  ComponentFramework,
  ComponentPattern,
  AnalysisError,
  AnalysisWarning
} from './types';
import { TypeScriptAnalyzer } from './analyzers/typescript-analyzer';
import { PropExtractor } from './analyzers/prop-extractor';
import { VariantDetector } from './analyzers/variant-detector';
import { UsageTracker } from './analyzers/usage-tracker';

export class ComponentAnalysisEngine {
  private tsAnalyzer: TypeScriptAnalyzer;
  private propExtractor: PropExtractor;
  private variantDetector: VariantDetector;
  private usageTracker: UsageTracker;

  constructor(private config: AnalysisConfig) {
    this.tsAnalyzer = new TypeScriptAnalyzer(config.tsConfigPath);
    this.propExtractor = new PropExtractor();
    this.variantDetector = new VariantDetector();
    this.usageTracker = new UsageTracker();
  }

  /**
   * Run complete analysis
   */
  async analyze(): Promise<AnalysisResult> {
    const startTime = Date.now();
    const components: ComponentMetadata[] = [];
    const errors: AnalysisError[] = [];
    const warnings: AnalysisWarning[] = [];

    try {
      // Find all component files
      const files = await this.findComponentFiles();
      console.log(`Found ${files.length} files to analyze`);

      // Update TypeScript program with all files
      this.tsAnalyzer.updateProgram(files);

      // Analyze each file
      for (const filePath of files) {
        try {
          const fileComponents = await this.analyzeFile(filePath);
          components.push(...fileComponents);
        } catch (error) {
          errors.push({
            filePath,
            message: error instanceof Error ? error.message : String(error),
            stack: error instanceof Error ? error.stack : undefined
          });
        }
      }

      // Track usages if enabled
      if (this.config.trackUsages) {
        await this.trackComponentUsages(components, files);
      }

      // Detect variants if enabled
      if (this.config.detectVariants) {
        this.detectComponentVariants(components);
      }

      // Generate summary
      const summary = this.generateSummary(components, Date.now() - startTime);

      return {
        components,
        summary,
        errors,
        warnings
      };
    } catch (error) {
      throw new Error(`Analysis failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * Find all component files
   */
  private async findComponentFiles(): Promise<string[]> {
    const allFiles: string[] = [];

    for (const pattern of this.config.include) {
      const files = await glob(pattern, {
        cwd: this.config.rootDir,
        ignore: this.config.exclude,
        absolute: true,
        nodir: true
      });
      allFiles.push(...files);
    }

    // Filter by file size
    return allFiles.filter(file => {
      try {
        const stats = require('fs').statSync(file);
        return stats.size <= this.config.maxFileSize;
      } catch {
        return false;
      }
    });
  }

  /**
   * Analyze a single file
   */
  private async analyzeFile(filePath: string): Promise<ComponentMetadata[]> {
    const ext = path.extname(filePath);

    // Determine framework from file extension and content
    const framework = this.detectFramework(filePath);

    if (!this.config.frameworks.includes(framework) && framework !== ComponentFramework.UNKNOWN) {
      return [];
    }

    // Use TypeScript analyzer for .ts, .tsx files
    if (ext === '.ts' || ext === '.tsx') {
      const components = this.tsAnalyzer.analyzeFile(filePath);
      return this.enrichComponents(components, filePath);
    }

    // Use Babel parser for .js, .jsx files
    if (ext === '.js' || ext === '.jsx') {
      return this.analyzeBabelFile(filePath);
    }

    // Use Vue analyzer for .vue files
    if (ext === '.vue') {
      return this.analyzeVueFile(filePath);
    }

    // Use Svelte analyzer for .svelte files
    if (ext === '.svelte') {
      return this.analyzeSvelteFile(filePath);
    }

    return [];
  }

  /**
   * Detect framework from file
   */
  private detectFramework(filePath: string): ComponentFramework {
    const ext = path.extname(filePath);

    if (ext === '.vue') return ComponentFramework.VUE;
    if (ext === '.svelte') return ComponentFramework.SVELTE;

    try {
      const content = readFileSync(filePath, 'utf-8');

      if (content.includes('from \'react\'') || content.includes('from "react"')) {
        return ComponentFramework.REACT;
      }
      if (content.includes('from \'vue\'') || content.includes('from "vue"')) {
        return ComponentFramework.VUE;
      }
      if (content.includes('from \'svelte\'')) {
        return ComponentFramework.SVELTE;
      }
    } catch {
      // Ignore read errors
    }

    return ComponentFramework.UNKNOWN;
  }

  /**
   * Enrich components with additional analysis
   */
  private async enrichComponents(
    components: ComponentMetadata[],
    filePath: string
  ): Promise<ComponentMetadata[]> {
    const sourceCode = readFileSync(filePath, 'utf-8');

    return components.map(component => {
      // Extract props using multi-source extraction
      const extractedProps = this.propExtractor.extractProps(
        sourceCode,
        component.framework,
        component.name
      );

      // Merge props (prefer extracted props if available)
      const props = extractedProps.length > 0 ? extractedProps : component.props;

      return {
        ...component,
        props
      };
    });
  }

  /**
   * Analyze file using Babel
   */
  private async analyzeBabelFile(filePath: string): Promise<ComponentMetadata[]> {
    // Simplified Babel analysis - in production, implement full Babel traversal
    const sourceCode = readFileSync(filePath, 'utf-8');
    const framework = this.detectFramework(filePath);

    // For now, use prop extractor to find components
    const components: ComponentMetadata[] = [];

    // This would need a full Babel implementation similar to TypeScript analyzer
    // For brevity, returning empty array - full implementation would mirror TS analyzer

    return components;
  }

  /**
   * Analyze Vue file
   */
  private async analyzeVueFile(filePath: string): Promise<ComponentMetadata[]> {
    const sourceCode = readFileSync(filePath, 'utf-8');

    // Extract script section
    const scriptMatch = sourceCode.match(/<script[^>]*>([\s\S]*?)<\/script>/);
    if (!scriptMatch) return [];

    const scriptContent = scriptMatch[1];

    // Extract props
    const props = this.propExtractor.extractProps(
      scriptContent,
      ComponentFramework.VUE,
      path.basename(filePath, '.vue')
    );

    const component: ComponentMetadata = {
      name: path.basename(filePath, '.vue'),
      filePath,
      framework: ComponentFramework.VUE,
      pattern: scriptContent.includes('setup(')
        ? ComponentPattern.VUE_COMPOSITION
        : ComponentPattern.VUE_OPTIONS,
      props,
      variants: [],
      usages: [],
      exports: { isDefault: true, isNamed: false, aliases: [] },
      dependencies: [],
      complexity: { cyclomaticComplexity: 1, cognitiveComplexity: 0, linesOfCode: scriptContent.split('\n').length },
      sourceLocation: { start: { line: 1, column: 1 }, end: { line: sourceCode.split('\n').length, column: 1 } }
    };

    return [component];
  }

  /**
   * Analyze Svelte file
   */
  private async analyzeSvelteFile(filePath: string): Promise<ComponentMetadata[]> {
    const sourceCode = readFileSync(filePath, 'utf-8');

    // Extract script section
    const scriptMatch = sourceCode.match(/<script[^>]*>([\s\S]*?)<\/script>/);
    const scriptContent = scriptMatch ? scriptMatch[1] : '';

    // Extract props
    const props = this.propExtractor.extractProps(
      scriptContent,
      ComponentFramework.SVELTE,
      path.basename(filePath, '.svelte')
    );

    const component: ComponentMetadata = {
      name: path.basename(filePath, '.svelte'),
      filePath,
      framework: ComponentFramework.SVELTE,
      pattern: ComponentPattern.SVELTE_COMPONENT,
      props,
      variants: [],
      usages: [],
      exports: { isDefault: true, isNamed: false, aliases: [] },
      dependencies: [],
      complexity: { cyclomaticComplexity: 1, cognitiveComplexity: 0, linesOfCode: sourceCode.split('\n').length },
      sourceLocation: { start: { line: 1, column: 1 }, end: { line: sourceCode.split('\n').length, column: 1 } }
    };

    return [component];
  }

  /**
   * Track component usages
   */
  private async trackComponentUsages(
    components: ComponentMetadata[],
    files: string[]
  ): Promise<void> {
    for (const component of components) {
      const usages = this.usageTracker.trackUsages(
        component.name,
        component.filePath,
        files,
        component.framework
      );
      component.usages = usages;
    }
  }

  /**
   * Detect component variants
   */
  private detectComponentVariants(components: ComponentMetadata[]): void {
    for (const component of components) {
      // Detect from props
      const propsVariants = this.variantDetector.detectVariants(component.props);

      // Detect from source (if available)
      try {
        const sourceCode = readFileSync(component.filePath, 'utf-8');
        const propsTypeName = `${component.name}Props`;
        const sourceVariants = this.variantDetector.detectVariantsFromSource(
          sourceCode,
          propsTypeName
        );

        // Merge variants
        component.variants = [...propsVariants, ...sourceVariants];
      } catch {
        component.variants = propsVariants;
      }
    }
  }

  /**
   * Generate analysis summary
   */
  private generateSummary(components: ComponentMetadata[], analysisTimeMs: number): AnalysisResult['summary'] {
    const byFramework: Record<ComponentFramework, number> = {
      [ComponentFramework.REACT]: 0,
      [ComponentFramework.VUE]: 0,
      [ComponentFramework.SVELTE]: 0,
      [ComponentFramework.UNKNOWN]: 0
    };

    const byPattern: Record<ComponentPattern, number> = {
      [ComponentPattern.FUNCTION]: 0,
      [ComponentPattern.CLASS]: 0,
      [ComponentPattern.HOC]: 0,
      [ComponentPattern.RENDER_PROP]: 0,
      [ComponentPattern.COMPOUND]: 0,
      [ComponentPattern.FORWARD_REF]: 0,
      [ComponentPattern.MEMO]: 0,
      [ComponentPattern.LAZY]: 0,
      [ComponentPattern.VUE_OPTIONS]: 0,
      [ComponentPattern.VUE_COMPOSITION]: 0,
      [ComponentPattern.SVELTE_COMPONENT]: 0
    };

    let totalProps = 0;
    let totalVariants = 0;
    let totalUsages = 0;

    components.forEach(component => {
      byFramework[component.framework]++;
      byPattern[component.pattern]++;
      totalProps += component.props.length;
      totalVariants += component.variants.length;
      totalUsages += component.usages.length;
    });

    return {
      totalComponents: components.length,
      byFramework,
      byPattern,
      totalProps,
      totalVariants,
      totalUsages,
      analysisTimeMs
    };
  }

  /**
   * Get component by name
   */
  findComponent(components: ComponentMetadata[], name: string): ComponentMetadata | undefined {
    return components.find(c => c.name === name);
  }

  /**
   * Get components by framework
   */
  filterByFramework(components: ComponentMetadata[], framework: ComponentFramework): ComponentMetadata[] {
    return components.filter(c => c.framework === framework);
  }

  /**
   * Get components by pattern
   */
  filterByPattern(components: ComponentMetadata[], pattern: ComponentPattern): ComponentMetadata[] {
    return components.filter(c => c.pattern === pattern);
  }

  /**
   * Get most used components
   */
  getMostUsed(components: ComponentMetadata[], limit: number = 10): ComponentMetadata[] {
    return [...components]
      .sort((a, b) => b.usages.length - a.usages.length)
      .slice(0, limit);
  }

  /**
   * Get most complex components
   */
  getMostComplex(components: ComponentMetadata[], limit: number = 10): ComponentMetadata[] {
    return [...components]
      .sort((a, b) => b.complexity.cyclomaticComplexity - a.complexity.cyclomaticComplexity)
      .slice(0, limit);
  }
}
