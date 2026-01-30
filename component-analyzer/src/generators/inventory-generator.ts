/**
 * Component Inventory Generator
 * Generates comprehensive component inventories in CSV, JSON, and Markdown formats
 */

import { writeFileSync } from 'fs';
import { Parser } from 'json2csv';
import {
  ComponentMetadata,
  ExportOptions,
  ComponentInventoryRow,
  AnalysisResult
} from '../types';

export class InventoryGenerator {
  /**
   * Generate inventory in specified format
   */
  generateInventory(
    result: AnalysisResult,
    options: ExportOptions
  ): void {
    switch (options.format) {
      case 'json':
        this.generateJSON(result, options);
        break;
      case 'csv':
        this.generateCSV(result, options);
        break;
      case 'markdown':
        this.generateMarkdown(result, options);
        break;
      default:
        throw new Error(`Unsupported format: ${options.format}`);
    }
  }

  /**
   * Generate JSON inventory
   */
  private generateJSON(result: AnalysisResult, options: ExportOptions): void {
    const data = this.prepareJSONData(result, options);
    const json = options.prettify
      ? JSON.stringify(data, null, 2)
      : JSON.stringify(data);

    writeFileSync(options.outputPath, json, 'utf-8');
  }

  /**
   * Prepare JSON data
   */
  private prepareJSONData(
    result: AnalysisResult,
    options: ExportOptions
  ): any {
    return {
      summary: result.summary,
      components: result.components.map(component => ({
        name: component.name,
        framework: component.framework,
        pattern: component.pattern,
        filePath: component.filePath,
        props: component.props,
        variants: options.includeVariants ? component.variants : undefined,
        usages: options.includeUsages ? component.usages : undefined,
        exports: component.exports,
        dependencies: component.dependencies,
        complexity: component.complexity,
        sourceLocation: component.sourceLocation,
        documentation: component.documentation
      })),
      errors: result.errors,
      warnings: result.warnings
    };
  }

  /**
   * Generate CSV inventory
   */
  private generateCSV(result: AnalysisResult, options: ExportOptions): void {
    const rows = this.prepareCSVData(result, options);

    const fields = [
      { label: 'Name', value: 'name' },
      { label: 'Framework', value: 'framework' },
      { label: 'Pattern', value: 'pattern' },
      { label: 'File Path', value: 'filePath' },
      { label: 'Props Count', value: 'propsCount' },
      { label: 'Variants Count', value: 'variantsCount' },
      { label: 'Usages Count', value: 'usagesCount' },
      { label: 'Complexity', value: 'complexity' },
      { label: 'Is Exported', value: 'isExported' },
      { label: 'Has Documentation', value: 'hasDocumentation' }
    ];

    const parser = new Parser({ fields });
    const csv = parser.parse(rows);

    writeFileSync(options.outputPath, csv, 'utf-8');
  }

  /**
   * Prepare CSV data
   */
  private prepareCSVData(
    result: AnalysisResult,
    options: ExportOptions
  ): ComponentInventoryRow[] {
    return result.components.map(component => ({
      name: component.name,
      framework: component.framework,
      pattern: component.pattern,
      filePath: component.filePath,
      propsCount: component.props.length,
      variantsCount: component.variants.length,
      usagesCount: component.usages.length,
      complexity: component.complexity.cyclomaticComplexity,
      isExported: component.exports.isDefault || component.exports.isNamed,
      hasDocumentation: !!component.documentation?.summary
    }));
  }

  /**
   * Generate Markdown inventory
   */
  private generateMarkdown(result: AnalysisResult, options: ExportOptions): void {
    const markdown = this.buildMarkdown(result, options);
    writeFileSync(options.outputPath, markdown, 'utf-8');
  }

  /**
   * Build Markdown content
   */
  private buildMarkdown(result: AnalysisResult, options: ExportOptions): string {
    const lines: string[] = [];

    // Title and summary
    lines.push('# Component Inventory\n');
    lines.push('## Summary\n');
    lines.push(`- **Total Components**: ${result.summary.totalComponents}`);
    lines.push(`- **Total Props**: ${result.summary.totalProps}`);
    lines.push(`- **Total Variants**: ${result.summary.totalVariants}`);
    lines.push(`- **Total Usages**: ${result.summary.totalUsages}`);
    lines.push(`- **Analysis Time**: ${result.summary.analysisTimeMs}ms\n`);

    // By framework
    lines.push('### By Framework\n');
    Object.entries(result.summary.byFramework).forEach(([framework, count]) => {
      if (count > 0) {
        lines.push(`- **${framework}**: ${count}`);
      }
    });
    lines.push('');

    // By pattern
    lines.push('### By Pattern\n');
    Object.entries(result.summary.byPattern).forEach(([pattern, count]) => {
      if (count > 0) {
        lines.push(`- **${pattern}**: ${count}`);
      }
    });
    lines.push('');

    // Component details
    lines.push('## Components\n');

    // Group by framework
    const byFramework = this.groupByFramework(result.components);

    Object.entries(byFramework).forEach(([framework, components]) => {
      if (components.length === 0) return;

      lines.push(`### ${framework}\n`);

      components.forEach(component => {
        lines.push(`#### ${component.name}\n`);
        lines.push(`- **Pattern**: ${component.pattern}`);
        lines.push(`- **File**: \`${component.filePath}\``);
        lines.push(`- **Props**: ${component.props.length}`);

        if (component.props.length > 0) {
          lines.push('\n**Props:**\n');
          lines.push('| Name | Type | Required | Default |');
          lines.push('|------|------|----------|---------|');
          component.props.forEach(prop => {
            const required = prop.required ? 'Yes' : 'No';
            const defaultValue = prop.defaultValue || '-';
            lines.push(`| ${prop.name} | \`${prop.type}\` | ${required} | ${defaultValue} |`);
          });
          lines.push('');
        }

        if (options.includeVariants && component.variants.length > 0) {
          lines.push(`- **Variants**: ${component.variants.length}\n`);
          component.variants.forEach(variant => {
            lines.push(`  - **${variant.name}**: ${variant.description || ''}`);
          });
          lines.push('');
        }

        if (options.includeUsages && component.usages.length > 0) {
          lines.push(`- **Usages**: ${component.usages.length}\n`);
          const usagesByFile = this.groupUsagesByFile(component.usages);
          Object.entries(usagesByFile).forEach(([file, count]) => {
            lines.push(`  - \`${file}\`: ${count} usage(s)`);
          });
          lines.push('');
        }

        lines.push(`- **Complexity**: ${component.complexity.cyclomaticComplexity}`);
        lines.push(`- **Lines of Code**: ${component.complexity.linesOfCode}`);
        lines.push(`- **Exported**: ${component.exports.isDefault ? 'Default' : component.exports.isNamed ? 'Named' : 'No'}\n`);

        if (component.documentation?.summary) {
          lines.push(`**Documentation:**\n`);
          lines.push(component.documentation.summary);
          lines.push('');
        }

        if (component.dependencies.length > 0) {
          lines.push(`**Dependencies**: ${component.dependencies.join(', ')}\n`);
        }

        lines.push('---\n');
      });
    });

    // Errors and warnings
    if (result.errors.length > 0) {
      lines.push('## Errors\n');
      result.errors.forEach(error => {
        lines.push(`- **${error.filePath}**: ${error.message}`);
        if (error.line) {
          lines.push(`  - Line ${error.line}${error.column ? `, Column ${error.column}` : ''}`);
        }
      });
      lines.push('');
    }

    if (result.warnings.length > 0) {
      lines.push('## Warnings\n');
      result.warnings.forEach(warning => {
        lines.push(`- **${warning.filePath}** [${warning.severity}]: ${warning.message}`);
        if (warning.line) {
          lines.push(`  - Line ${warning.line}${warning.column ? `, Column ${warning.column}` : ''}`);
        }
      });
      lines.push('');
    }

    return lines.join('\n');
  }

  /**
   * Group components by framework
   */
  private groupByFramework(
    components: ComponentMetadata[]
  ): Record<string, ComponentMetadata[]> {
    const grouped: Record<string, ComponentMetadata[]> = {};

    components.forEach(component => {
      if (!grouped[component.framework]) {
        grouped[component.framework] = [];
      }
      grouped[component.framework].push(component);
    });

    return grouped;
  }

  /**
   * Group usages by file
   */
  private groupUsagesByFile(usages: any[]): Record<string, number> {
    const grouped: Record<string, number> = {};

    usages.forEach(usage => {
      if (!grouped[usage.filePath]) {
        grouped[usage.filePath] = 0;
      }
      grouped[usage.filePath]++;
    });

    return grouped;
  }

  /**
   * Generate detailed component report
   */
  generateDetailedReport(component: ComponentMetadata): string {
    const lines: string[] = [];

    lines.push(`# ${component.name}\n`);
    lines.push(`**Framework**: ${component.framework}`);
    lines.push(`**Pattern**: ${component.pattern}`);
    lines.push(`**File**: \`${component.filePath}\`\n`);

    // Props table
    if (component.props.length > 0) {
      lines.push('## Props\n');
      lines.push('| Name | Type | Required | Default | Description |');
      lines.push('|------|------|----------|---------|-------------|');
      component.props.forEach(prop => {
        const required = prop.required ? 'Yes' : 'No';
        const defaultValue = prop.defaultValue || '-';
        const description = prop.description || '-';
        const deprecated = prop.deprecated ? ' (deprecated)' : '';
        lines.push(
          `| ${prop.name}${deprecated} | \`${prop.type}\` | ${required} | ${defaultValue} | ${description} |`
        );
      });
      lines.push('');
    }

    // Variants
    if (component.variants.length > 0) {
      lines.push('## Variants\n');
      component.variants.forEach(variant => {
        lines.push(`### ${variant.name}\n`);
        lines.push(`**Discriminator**: \`${variant.discriminator} = ${JSON.stringify(variant.discriminatorValue)}\`\n`);
        if (variant.description) {
          lines.push(variant.description);
          lines.push('');
        }
        if (variant.additionalProps.length > 0) {
          lines.push('**Additional Props**:\n');
          variant.additionalProps.forEach(prop => {
            lines.push(`- \`${prop.name}: ${prop.type}\`${prop.required ? ' (required)' : ''}`);
          });
          lines.push('');
        }
      });
    }

    // Usages
    if (component.usages.length > 0) {
      lines.push('## Usages\n');
      lines.push(`Found in ${component.usages.length} location(s):\n`);

      const byFile = this.groupUsagesByFile(component.usages);
      Object.entries(byFile).forEach(([file, count]) => {
        lines.push(`- \`${file}\` (${count})`);
      });
      lines.push('');
    }

    // Metrics
    lines.push('## Metrics\n');
    lines.push(`- **Cyclomatic Complexity**: ${component.complexity.cyclomaticComplexity}`);
    lines.push(`- **Cognitive Complexity**: ${component.complexity.cognitiveComplexity}`);
    lines.push(`- **Lines of Code**: ${component.complexity.linesOfCode}\n`);

    // Dependencies
    if (component.dependencies.length > 0) {
      lines.push('## Dependencies\n');
      component.dependencies.forEach(dep => {
        lines.push(`- ${dep}`);
      });
      lines.push('');
    }

    return lines.join('\n');
  }

  /**
   * Generate summary statistics
   */
  generateStatistics(result: AnalysisResult): string {
    const lines: string[] = [];

    lines.push('# Component Analysis Statistics\n');
    lines.push(`**Analysis Date**: ${new Date().toISOString()}`);
    lines.push(`**Analysis Duration**: ${result.summary.analysisTimeMs}ms\n`);

    lines.push('## Overview\n');
    lines.push(`- Total Components: ${result.summary.totalComponents}`);
    lines.push(`- Total Props: ${result.summary.totalProps}`);
    lines.push(`- Total Variants: ${result.summary.totalVariants}`);
    lines.push(`- Total Usages: ${result.summary.totalUsages}\n`);

    // Framework distribution
    lines.push('## Framework Distribution\n');
    const frameworkTotal = Object.values(result.summary.byFramework).reduce((a, b) => a + b, 0);
    Object.entries(result.summary.byFramework).forEach(([framework, count]) => {
      const percentage = frameworkTotal > 0 ? ((count / frameworkTotal) * 100).toFixed(1) : '0.0';
      lines.push(`- ${framework}: ${count} (${percentage}%)`);
    });
    lines.push('');

    // Pattern distribution
    lines.push('## Pattern Distribution\n');
    const patternTotal = Object.values(result.summary.byPattern).reduce((a, b) => a + b, 0);
    Object.entries(result.summary.byPattern).forEach(([pattern, count]) => {
      const percentage = patternTotal > 0 ? ((count / patternTotal) * 100).toFixed(1) : '0.0';
      lines.push(`- ${pattern}: ${count} (${percentage}%)`);
    });
    lines.push('');

    // Complexity statistics
    const complexities = result.components.map(c => c.complexity.cyclomaticComplexity);
    const avgComplexity = complexities.reduce((a, b) => a + b, 0) / complexities.length;
    const maxComplexity = Math.max(...complexities);
    const minComplexity = Math.min(...complexities);

    lines.push('## Complexity Statistics\n');
    lines.push(`- Average Complexity: ${avgComplexity.toFixed(2)}`);
    lines.push(`- Max Complexity: ${maxComplexity}`);
    lines.push(`- Min Complexity: ${minComplexity}\n`);

    // Most used components
    const byUsage = [...result.components].sort((a, b) => b.usages.length - a.usages.length);
    lines.push('## Most Used Components\n');
    byUsage.slice(0, 10).forEach((component, index) => {
      lines.push(`${index + 1}. **${component.name}**: ${component.usages.length} usages`);
    });
    lines.push('');

    // Most complex components
    const byComplexity = [...result.components].sort(
      (a, b) => b.complexity.cyclomaticComplexity - a.complexity.cyclomaticComplexity
    );
    lines.push('## Most Complex Components\n');
    byComplexity.slice(0, 10).forEach((component, index) => {
      lines.push(
        `${index + 1}. **${component.name}**: ${component.complexity.cyclomaticComplexity} (${component.complexity.linesOfCode} LOC)`
      );
    });
    lines.push('');

    return lines.join('\n');
  }
}
