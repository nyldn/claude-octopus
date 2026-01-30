#!/usr/bin/env node
/**
 * Component Analysis CLI
 * Command-line interface for component analysis
 */

import { ComponentAnalysisEngine } from './engine';
import { InventoryGenerator } from './generators/inventory-generator';
import { AnalysisConfig, ComponentFramework, ExportOptions } from './types';
import { DEFAULT_CONFIG } from './index';
import * as path from 'path';

interface CLIOptions {
  rootDir?: string;
  include?: string[];
  exclude?: string[];
  frameworks?: string[];
  output?: string;
  format?: 'json' | 'csv' | 'markdown';
  trackUsages?: boolean;
  detectVariants?: boolean;
  tsconfig?: string;
  verbose?: boolean;
}

class CLI {
  /**
   * Parse command line arguments
   */
  parseArgs(args: string[]): CLIOptions {
    const options: CLIOptions = {};

    for (let i = 0; i < args.length; i++) {
      const arg = args[i];

      switch (arg) {
        case '--root':
        case '-r':
          options.rootDir = args[++i];
          break;

        case '--include':
        case '-i':
          options.include = args[++i].split(',');
          break;

        case '--exclude':
        case '-e':
          options.exclude = args[++i].split(',');
          break;

        case '--frameworks':
        case '-f':
          options.frameworks = args[++i].split(',');
          break;

        case '--output':
        case '-o':
          options.output = args[++i];
          break;

        case '--format':
          options.format = args[++i] as 'json' | 'csv' | 'markdown';
          break;

        case '--no-usages':
          options.trackUsages = false;
          break;

        case '--no-variants':
          options.detectVariants = false;
          break;

        case '--tsconfig':
          options.tsconfig = args[++i];
          break;

        case '--verbose':
        case '-v':
          options.verbose = true;
          break;

        case '--help':
        case '-h':
          this.printHelp();
          process.exit(0);
          break;
      }
    }

    return options;
  }

  /**
   * Build analysis configuration
   */
  buildConfig(options: CLIOptions): AnalysisConfig {
    const frameworks = (options.frameworks || DEFAULT_CONFIG.frameworks).map(f => {
      switch (f.toLowerCase()) {
        case 'react': return ComponentFramework.REACT;
        case 'vue': return ComponentFramework.VUE;
        case 'svelte': return ComponentFramework.SVELTE;
        default: return ComponentFramework.UNKNOWN;
      }
    });

    return {
      rootDir: options.rootDir || DEFAULT_CONFIG.rootDir,
      include: options.include || DEFAULT_CONFIG.include,
      exclude: options.exclude || DEFAULT_CONFIG.exclude,
      frameworks,
      detectVariants: options.detectVariants !== false,
      trackUsages: options.trackUsages !== false,
      extractDocs: true,
      maxFileSize: DEFAULT_CONFIG.maxFileSize,
      parallelism: DEFAULT_CONFIG.parallelism,
      tsConfigPath: options.tsconfig
    };
  }

  /**
   * Build export options
   */
  buildExportOptions(options: CLIOptions): ExportOptions {
    const format = options.format || 'json';
    const outputPath = options.output || path.join(
      process.cwd(),
      `component-inventory.${format}`
    );

    return {
      format,
      outputPath,
      includeUsages: options.trackUsages !== false,
      includeVariants: options.detectVariants !== false,
      prettify: true
    };
  }

  /**
   * Print help message
   */
  printHelp(): void {
    console.log(`
Component Analysis CLI

Usage:
  component-analyzer [options]

Options:
  -r, --root <dir>         Root directory to analyze (default: current directory)
  -i, --include <patterns> Comma-separated glob patterns to include (default: **/*.{tsx,ts,jsx,js,vue,svelte})
  -e, --exclude <patterns> Comma-separated glob patterns to exclude (default: node_modules,dist,build)
  -f, --frameworks <list>  Comma-separated frameworks to analyze (default: react,vue,svelte)
  -o, --output <file>      Output file path (default: component-inventory.<format>)
  --format <type>          Output format: json, csv, markdown (default: json)
  --no-usages              Disable usage tracking
  --no-variants            Disable variant detection
  --tsconfig <path>        Path to tsconfig.json
  -v, --verbose            Verbose output
  -h, --help               Show this help message

Examples:
  # Analyze React components in src directory
  component-analyzer --root src --frameworks react

  # Generate CSV inventory with usage tracking
  component-analyzer --format csv --output components.csv

  # Analyze all frameworks without variant detection
  component-analyzer --no-variants --output inventory.json

  # Custom include/exclude patterns
  component-analyzer --include "src/**/*.tsx,lib/**/*.tsx" --exclude "**/*.test.tsx"
`);
  }

  /**
   * Run analysis
   */
  async run(args: string[]): Promise<void> {
    try {
      const options = this.parseArgs(args);

      if (options.verbose) {
        console.log('Configuration:', JSON.stringify(options, null, 2));
      }

      const config = this.buildConfig(options);
      const exportOptions = this.buildExportOptions(options);

      console.log('Starting component analysis...');
      console.log(`Root directory: ${config.rootDir}`);
      console.log(`Frameworks: ${config.frameworks.join(', ')}`);

      const engine = new ComponentAnalysisEngine(config);
      const result = await engine.analyze();

      console.log('\nAnalysis complete!');
      console.log(`Found ${result.summary.totalComponents} components`);
      console.log(`Total props: ${result.summary.totalProps}`);
      console.log(`Total variants: ${result.summary.totalVariants}`);
      console.log(`Total usages: ${result.summary.totalUsages}`);
      console.log(`Analysis time: ${result.summary.analysisTimeMs}ms`);

      if (result.errors.length > 0) {
        console.warn(`\nErrors: ${result.errors.length}`);
        if (options.verbose) {
          result.errors.forEach(error => {
            console.error(`  ${error.filePath}: ${error.message}`);
          });
        }
      }

      if (result.warnings.length > 0) {
        console.warn(`\nWarnings: ${result.warnings.length}`);
        if (options.verbose) {
          result.warnings.forEach(warning => {
            console.warn(`  ${warning.filePath}: ${warning.message}`);
          });
        }
      }

      console.log(`\nGenerating ${exportOptions.format.toUpperCase()} inventory...`);
      const generator = new InventoryGenerator();
      generator.generateInventory(result, exportOptions);
      console.log(`Inventory saved to: ${exportOptions.outputPath}`);

      // Generate statistics in verbose mode
      if (options.verbose) {
        const statsPath = path.join(
          path.dirname(exportOptions.outputPath),
          'component-statistics.md'
        );
        const stats = generator.generateStatistics(result);
        require('fs').writeFileSync(statsPath, stats, 'utf-8');
        console.log(`Statistics saved to: ${statsPath}`);
      }

    } catch (error) {
      console.error('Analysis failed:', error instanceof Error ? error.message : String(error));
      if (error instanceof Error && error.stack) {
        console.error(error.stack);
      }
      process.exit(1);
    }
  }
}

// Run CLI if executed directly
if (require.main === module) {
  const cli = new CLI();
  cli.run(process.argv.slice(2));
}

export { CLI };
