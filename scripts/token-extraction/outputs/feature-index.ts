/**
 * Feature Index Output Generator
 * Generates a master index of detected features
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { Feature, FeatureDetectionResult } from '../types';

export interface FeatureIndexOptions {
  outputPath: string;
  format?: 'json' | 'markdown';
  includeTokenCounts?: boolean;
  includeFilePaths?: boolean;
  prettify?: boolean;
}

/**
 * Generate feature index output
 */
export async function generateFeatureIndex(
  result: FeatureDetectionResult,
  options: FeatureIndexOptions
): Promise<void> {
  const format = options.format || 'json';

  if (format === 'json') {
    await generateJSONIndex(result, options);
  } else if (format === 'markdown') {
    await generateMarkdownIndex(result, options);
  } else {
    throw new Error(`Unsupported feature index format: ${format}`);
  }
}

/**
 * Generate JSON feature index
 */
async function generateJSONIndex(
  result: FeatureDetectionResult,
  options: FeatureIndexOptions
): Promise<void> {
  const index = {
    metadata: result.metadata,
    features: result.features.map(feature => ({
      name: feature.name,
      description: feature.description,
      fileCount: feature.fileCount,
      tokenCount: options.includeTokenCounts ? feature.tokenCount : undefined,
      paths: options.includeFilePaths ? feature.paths : undefined,
      scope: feature.scope,
      confidence: feature.confidence,
    })),
    unassignedFiles: result.unassignedFiles,
  };

  const content = options.prettify
    ? JSON.stringify(index, null, 2)
    : JSON.stringify(index);

  await fs.mkdir(path.dirname(options.outputPath), { recursive: true });
  await fs.writeFile(options.outputPath, content, 'utf-8');
}

/**
 * Generate Markdown feature index
 */
async function generateMarkdownIndex(
  result: FeatureDetectionResult,
  options: FeatureIndexOptions
): Promise<void> {
  let markdown = '';

  // Header
  markdown += '# Feature Index\n\n';
  markdown += `Generated: ${result.metadata.timestamp}\n\n`;

  // Metadata
  markdown += '## Overview\n\n';
  markdown += `- **Total Features**: ${result.metadata.totalFeatures}\n`;
  markdown += `- **Total Files**: ${result.metadata.totalFiles}\n`;
  markdown += `- **Detection Method**: ${result.metadata.detectionMethod}\n`;
  markdown += `- **Unassigned Files**: ${result.unassignedFiles.length}\n\n`;

  // Features
  markdown += '## Detected Features\n\n';

  if (result.features.length === 0) {
    markdown += '_No features detected_\n\n';
  } else {
    for (const feature of result.features) {
      markdown += `### ${feature.name}\n\n`;

      if (feature.description) {
        markdown += `${feature.description}\n\n`;
      }

      markdown += '**Statistics:**\n\n';
      markdown += `- Files: ${feature.fileCount}\n`;

      if (options.includeTokenCounts) {
        markdown += `- Tokens: ${feature.tokenCount}\n`;
      }

      if (feature.confidence !== undefined) {
        markdown += `- Confidence: ${(feature.confidence * 100).toFixed(0)}%\n`;
      }

      if (feature.scope) {
        markdown += '\n**Scope:**\n\n';
        markdown += `- Include Paths: ${feature.scope.includePaths.length}\n`;

        if (feature.scope.excludePaths && feature.scope.excludePaths.length > 0) {
          markdown += `- Exclude Paths: ${feature.scope.excludePaths.length}\n`;
        }

        if (feature.scope.keywords && feature.scope.keywords.length > 0) {
          markdown += `- Keywords: ${feature.scope.keywords.join(', ')}\n`;
        }
      }

      if (options.includeFilePaths && feature.paths.length > 0) {
        markdown += '\n**Files:**\n\n';

        // Show first 10 files
        const filesToShow = feature.paths.slice(0, 10);
        for (const filePath of filesToShow) {
          markdown += `- \`${filePath}\`\n`;
        }

        if (feature.paths.length > 10) {
          markdown += `- _...and ${feature.paths.length - 10} more files_\n`;
        }
      }

      markdown += '\n';
    }
  }

  // Unassigned files
  if (result.unassignedFiles.length > 0) {
    markdown += '## Unassigned Files\n\n';
    markdown += `${result.unassignedFiles.length} files could not be assigned to any feature:\n\n`;

    // Show first 20 unassigned files
    const filesToShow = result.unassignedFiles.slice(0, 20);
    for (const filePath of filesToShow) {
      markdown += `- \`${filePath}\`\n`;
    }

    if (result.unassignedFiles.length > 20) {
      markdown += `- _...and ${result.unassignedFiles.length - 20} more files_\n`;
    }

    markdown += '\n';
  }

  // Usage guide
  markdown += '## Usage\n\n';
  markdown += 'To extract tokens for a specific feature:\n\n';
  markdown += '```bash\n';
  markdown += '# Extract tokens for a specific feature\n';
  markdown += 'token-extraction --feature <feature-name>\n\n';
  markdown += '# Example:\n';

  if (result.features.length > 0) {
    const exampleFeature = result.features[0].name.toLowerCase().replace(/\s+/g, '-');
    markdown += `token-extraction --feature ${exampleFeature}\n`;
  }

  markdown += '```\n';

  await fs.mkdir(path.dirname(options.outputPath), { recursive: true });
  await fs.writeFile(options.outputPath, markdown, 'utf-8');
}

/**
 * Generate feature-specific extraction script
 */
export async function generateFeatureExtractionScript(
  features: Feature[],
  outputPath: string
): Promise<void> {
  let script = '#!/bin/bash\n\n';
  script += '# Feature-specific token extraction script\n';
  script += '# Auto-generated from feature detection\n\n';
  script += 'set -e\n\n';

  script += 'echo "Extracting tokens for all detected features..."\n';
  script += 'echo ""\n\n';

  for (const feature of features) {
    const featureName = feature.name.toLowerCase().replace(/\s+/g, '-');
    script += `# Extract ${feature.name}\n`;
    script += `echo "Extracting ${feature.name}..."\n`;
    script += `token-extraction --feature "${featureName}" --output "./design-tokens/${featureName}"\n`;
    script += 'echo ""\n\n';
  }

  script += 'echo "All features extracted!"\n';

  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.writeFile(outputPath, script, 'utf-8');

  // Make script executable
  await fs.chmod(outputPath, 0o755);
}
