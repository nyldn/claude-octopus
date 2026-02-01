/**
 * Style Dictionary Output Generator
 * Generates Style Dictionary configuration and source tokens
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { Token, TokenType } from '../types';

interface StyleDictionaryOutputOptions {
  outputPath: string;
  platforms?: ('web' | 'ios' | 'android' | 'scss' | 'css')[];
  includeComments?: boolean;
}

/**
 * Map token type to Style Dictionary type
 */
function mapToStyleDictionaryType(type?: TokenType): string {
  if (!type) return 'string';

  const typeMap: Record<TokenType, string> = {
    color: 'color',
    dimension: 'size',
    fontFamily: 'fontFamily',
    fontWeight: 'fontWeight',
    duration: 'time',
    cubicBezier: 'cubicBezier',
    number: 'number',
    string: 'string',
    shadow: 'shadow',
    gradient: 'gradient',
    typography: 'typography',
    border: 'border',
    transition: 'transition',
  };

  return typeMap[type] || 'string';
}

/**
 * Build Style Dictionary token structure
 */
function buildStyleDictionaryTokens(tokens: Token[]): any {
  const root: any = {};

  for (const token of tokens) {
    let current = root;

    for (let i = 0; i < token.path.length - 1; i++) {
      const segment = token.path[i];
      if (!current[segment]) {
        current[segment] = {};
      }
      current = current[segment];
    }

    const leafKey = token.path[token.path.length - 1];
    current[leafKey] = {
      value: token.value,
      type: mapToStyleDictionaryType(token.type),
      ...(token.description && { comment: token.description }),
      ...(token.metadata && {
        metadata: {
          source: token.source,
          ...token.metadata,
        },
      }),
    };
  }

  return root;
}

/**
 * Generate Style Dictionary config
 */
function generateConfig(platforms: string[], sourcePath: string): string {
  const config: any = {
    source: [sourcePath],
    platforms: {},
  };

  if (platforms.includes('web') || platforms.includes('css')) {
    config.platforms.css = {
      transformGroup: 'css',
      buildPath: 'build/css/',
      files: [
        {
          destination: 'variables.css',
          format: 'css/variables',
        },
      ],
    };
  }

  if (platforms.includes('scss')) {
    config.platforms.scss = {
      transformGroup: 'scss',
      buildPath: 'build/scss/',
      files: [
        {
          destination: '_variables.scss',
          format: 'scss/variables',
        },
      ],
    };
  }

  if (platforms.includes('ios')) {
    config.platforms.ios = {
      transformGroup: 'ios',
      buildPath: 'build/ios/',
      files: [
        {
          destination: 'StyleDictionaryColor.h',
          format: 'ios/colors.h',
          className: 'StyleDictionaryColor',
          type: 'StyleDictionaryColorName',
          filter: {
            attributes: {
              category: 'color',
            },
          },
        },
        {
          destination: 'StyleDictionaryColor.m',
          format: 'ios/colors.m',
          className: 'StyleDictionaryColor',
          type: 'StyleDictionaryColorName',
          filter: {
            attributes: {
              category: 'color',
            },
          },
        },
        {
          destination: 'StyleDictionarySize.h',
          format: 'ios/static.h',
          className: 'StyleDictionarySize',
          type: 'float',
          filter: {
            attributes: {
              category: 'size',
            },
          },
        },
        {
          destination: 'StyleDictionarySize.m',
          format: 'ios/static.m',
          className: 'StyleDictionarySize',
          type: 'float',
          filter: {
            attributes: {
              category: 'size',
            },
          },
        },
      ],
    };
  }

  if (platforms.includes('android')) {
    config.platforms.android = {
      transformGroup: 'android',
      buildPath: 'build/android/',
      files: [
        {
          destination: 'colors.xml',
          format: 'android/colors',
        },
        {
          destination: 'dimens.xml',
          format: 'android/dimens',
        },
        {
          destination: 'font_dimens.xml',
          format: 'android/fontDimens',
        },
      ],
    };
  }

  return JSON.stringify(config, null, 2);
}

/**
 * Generate Style Dictionary configuration and source files
 */
export async function generateStyleDictionaryOutput(
  tokens: Token[],
  options: StyleDictionaryOutputOptions
): Promise<void> {
  const {
    outputPath,
    platforms = ['web', 'ios', 'android', 'scss'],
    includeComments = true,
  } = options;

  const outputDir = path.dirname(outputPath);
  await fs.mkdir(outputDir, { recursive: true });

  // Build tokens in Style Dictionary format
  const styleDictionaryTokens = buildStyleDictionaryTokens(tokens);

  // Generate tokens source file
  const tokensSourcePath = path.join(outputDir, 'tokens-source.json');
  const tokensSource: any = {
    ...styleDictionaryTokens,
  };

  if (includeComments) {
    tokensSource.__metadata = {
      generated: new Date().toISOString(),
      description: 'Design tokens in Style Dictionary format',
      warning: 'Do not edit manually - this file is auto-generated',
    };
  }

  await fs.writeFile(tokensSourcePath, JSON.stringify(tokensSource, null, 2));

  // Generate config file
  const config = generateConfig(platforms, 'tokens-source.json');
  const configLines: string[] = [];

  if (includeComments) {
    configLines.push('/**');
    configLines.push(' * Style Dictionary Configuration');
    configLines.push(` * Generated: ${new Date().toISOString()}`);
    configLines.push(' * Do not edit manually - this file is auto-generated');
    configLines.push(' *');
    configLines.push(' * To build tokens, run:');
    configLines.push(' * npx style-dictionary build');
    configLines.push(' */');
    configLines.push('');
  }

  configLines.push('module.exports = ' + config + ';');

  await fs.writeFile(outputPath, configLines.join('\n'));

  // Create package.json script helper if needed
  const packageJsonPath = path.join(outputDir, 'package.json.snippet');
  const packageSnippet = {
    scripts: {
      'build:tokens': 'style-dictionary build',
    },
    devDependencies: {
      'style-dictionary': '^3.8.0',
    },
  };

  await fs.writeFile(packageJsonPath, JSON.stringify(packageSnippet, null, 2));
}
