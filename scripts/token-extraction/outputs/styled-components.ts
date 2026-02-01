/**
 * Styled Components Output Generator
 * Generates styled-components theme from design tokens
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { Token } from '../types';

interface StyledComponentsOutputOptions {
  outputPath: string;
  includeTypes?: boolean;
  includeComments?: boolean;
}

/**
 * Build nested theme structure
 */
function buildThemeStructure(tokens: Token[]): any {
  const theme: any = {};

  for (const token of tokens) {
    let current = theme;

    for (let i = 0; i < token.path.length - 1; i++) {
      const segment = token.path[i];
      if (!current[segment]) {
        current[segment] = {};
      }
      current = current[segment];
    }

    const leafKey = token.path[token.path.length - 1];
    current[leafKey] = token.value;
  }

  return theme;
}

/**
 * Generate theme object code
 */
function generateThemeObject(obj: any, indent: number = 0): string {
  const indentStr = '  '.repeat(indent);
  const lines: string[] = [];

  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === 'object' && !Array.isArray(value) && value !== null) {
      lines.push(`${indentStr}  ${key}: {`);
      lines.push(generateThemeObject(value, indent + 1));
      lines.push(`${indentStr}  },`);
    } else if (Array.isArray(value)) {
      const arrayStr = JSON.stringify(value);
      lines.push(`${indentStr}  ${key}: ${arrayStr},`);
    } else if (typeof value === 'string') {
      lines.push(`${indentStr}  ${key}: '${value}',`);
    } else {
      lines.push(`${indentStr}  ${key}: ${value},`);
    }
  }

  return lines.join('\n');
}

/**
 * Generate TypeScript type for theme
 */
function generateThemeType(obj: any, indent: number = 0): string {
  const indentStr = '  '.repeat(indent);
  const lines: string[] = [];

  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === 'object' && !Array.isArray(value) && value !== null) {
      lines.push(`${indentStr}  ${key}: {`);
      lines.push(generateThemeType(value, indent + 1));
      lines.push(`${indentStr}  };`);
    } else if (Array.isArray(value)) {
      const types = value.map(v => typeof v).filter((v, i, a) => a.indexOf(v) === i);
      const typeStr = types.includes('string') ? 'string[]' : 'any[]';
      lines.push(`${indentStr}  ${key}: ${typeStr};`);
    } else {
      const type = typeof value;
      lines.push(`${indentStr}  ${key}: ${type};`);
    }
  }

  return lines.join('\n');
}

/**
 * Generate styled-components theme file
 */
export async function generateStyledComponentsOutput(
  tokens: Token[],
  options: StyledComponentsOutputOptions
): Promise<void> {
  const {
    outputPath,
    includeTypes = true,
    includeComments = true,
  } = options;

  const outputDir = path.dirname(outputPath);
  await fs.mkdir(outputDir, { recursive: true });

  const theme = buildThemeStructure(tokens);
  const lines: string[] = [];

  if (includeComments) {
    lines.push('/**');
    lines.push(' * Styled Components Theme');
    lines.push(` * Generated: ${new Date().toISOString()}`);
    lines.push(' * Do not edit manually - this file is auto-generated');
    lines.push(' */');
    lines.push('');
  }

  // Export theme object
  lines.push('export const theme = {');
  lines.push(generateThemeObject(theme, 0));
  lines.push('} as const;');
  lines.push('');

  // Export theme type
  if (includeTypes) {
    lines.push('export type Theme = typeof theme;');
    lines.push('');

    // Generate module augmentation for styled-components
    lines.push('// Module augmentation for styled-components');
    lines.push('declare module \'styled-components\' {');
    lines.push('  export interface DefaultTheme extends Theme {}');
    lines.push('}');
    lines.push('');
  }

  // Export default
  lines.push('export default theme;');

  await fs.writeFile(outputPath, lines.join('\n'));
}
