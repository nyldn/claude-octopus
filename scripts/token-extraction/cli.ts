#!/usr/bin/env node

/**
 * Token Extraction CLI
 * Command-line interface for the token extraction pipeline
 */

import * as path from 'path';
import { runTokenExtraction } from './pipeline';
import { ExtractionOptions, TokenSource } from './types';

interface CLIOptions extends ExtractionOptions {
  help?: boolean;
  version?: boolean;
  projectRoot?: string;
}

/**
 * Parse command-line arguments
 */
function parseArgs(args: string[]): CLIOptions {
  const options: CLIOptions = {
    projectRoot: process.cwd(),
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    switch (arg) {
      case '-h':
      case '--help':
        options.help = true;
        break;

      case '-v':
      case '--version':
        options.version = true;
        break;

      case '-p':
      case '--project':
        options.projectRoot = args[++i];
        break;

      case '-o':
      case '--output':
        options.outputDir = args[++i];
        break;

      case '-f':
      case '--formats':
        options.outputFormats = args[++i]
          .split(',')
          .map(f => f.trim()) as ('json' | 'css' | 'markdown')[];
        break;

      case '-c':
      case '--conflict-resolution':
        options.conflictResolution = args[++i] as 'priority' | 'manual' | 'merge';
        break;

      case '--include-sources':
        options.includeSources = args[++i]
          .split(',')
          .map(s => s.trim()) as TokenSource[];
        break;

      case '--exclude-sources':
        options.excludeSources = args[++i]
          .split(',')
          .map(s => s.trim()) as TokenSource[];
        break;

      case '--no-validate':
        options.validateTokens = false;
        break;

      case '--preserve-keys':
        options.preserveOriginalKeys = true;
        break;

      default:
        if (arg.startsWith('-')) {
          console.error(`Unknown option: ${arg}`);
          process.exit(1);
        }
    }
  }

  return options;
}

/**
 * Print help message
 */
function printHelp(): void {
  console.log(`
Token Extraction Pipeline CLI

Usage: token-extraction [options]

Options:
  -h, --help                     Show this help message
  -v, --version                  Show version number
  -p, --project <path>           Project root directory (default: current directory)
  -o, --output <path>            Output directory (default: ./design-tokens)
  -f, --formats <formats>        Output formats: json,css,markdown (default: all)
  -c, --conflict-resolution      Conflict resolution strategy: priority|manual|merge (default: priority)
  --include-sources <sources>    Only extract from specific sources (comma-separated)
  --exclude-sources <sources>    Exclude specific sources (comma-separated)
  --no-validate                  Skip token validation
  --preserve-keys                Preserve original token keys in metadata

Sources:
  - tailwind.config    Tailwind CSS configuration files
  - css-variables      CSS custom properties from :root
  - theme-file         Theme configuration files (theme.js/ts)
  - styled-components  Styled-components theme providers
  - emotion-theme      Emotion theme providers

Examples:
  # Extract all tokens from current project
  token-extraction

  # Extract only Tailwind and CSS variables
  token-extraction --include-sources tailwind.config,css-variables

  # Generate only JSON output
  token-extraction --formats json

  # Custom output directory
  token-extraction --output ./tokens

  # Skip validation
  token-extraction --no-validate

For more information, visit: https://github.com/nyldn/claude-octopus
  `);
}

/**
 * Print version
 */
function printVersion(): void {
  console.log('Token Extraction Pipeline v1.0.0');
}

/**
 * Main CLI function
 */
async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const options = parseArgs(args);

  // Handle help and version flags
  if (options.help) {
    printHelp();
    process.exit(0);
  }

  if (options.version) {
    printVersion();
    process.exit(0);
  }

  try {
    // Resolve project root
    const projectRoot = path.resolve(options.projectRoot!);
    delete options.projectRoot;

    // Run the extraction pipeline
    const result = await runTokenExtraction(projectRoot, options);

    // Exit with error code if there are errors
    if (result.errors.length > 0) {
      console.error(`\nExtraction completed with ${result.errors.length} error(s)`);
      process.exit(1);
    }

    // Exit with warning code if there are manual conflicts
    const manualConflicts = result.conflicts.filter(c => c.resolution === 'manual');
    if (manualConflicts.length > 0) {
      console.warn(`\nExtraction completed with ${manualConflicts.length} manual conflict(s)`);
      process.exit(2);
    }

    // Success
    console.log('\nExtraction completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  }
}

// Run CLI if executed directly
if (require.main === module) {
  main().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

export { main, parseArgs, printHelp, printVersion };
