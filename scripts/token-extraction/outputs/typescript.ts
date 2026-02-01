/**
 * TypeScript Output Generator
 * Generates TypeScript type definitions and typed exports from design tokens
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { Token } from '../types';

interface TypeScriptOutputOptions {
  outputPath: string;
  generateTypes?: boolean;
  generateConstants?: boolean;
  exportType?: 'named' | 'default' | 'both';
  indent?: number;
}

/**
 * Convert token value to TypeScript type
 */
function getTypeScriptType(token: Token): string {
  if (token.type === 'color') return 'string';
  if (token.type === 'dimension') return 'string';
  if (token.type === 'fontFamily') return 'string';
  if (token.type === 'fontWeight') return 'number | string';
  if (token.type === 'duration') return 'string';
  if (token.type === 'number') return 'number';
  if (token.type === 'string') return 'string';

  return 'string | number';
}

/**
 * Build nested object structure from token paths
 */
function buildNestedStructure(tokens: Token[]): any {
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
    current[leafKey] = token.value;
  }

  return root;
}

/**
 * Generate TypeScript interface definition
 */
function generateInterface(
  name: string,
  obj: any,
  indent: number = 0,
  tokens: Token[]
): string {
  const indentStr = '  '.repeat(indent);
  const lines: string[] = [];

  if (indent === 0) {
    lines.push(`export interface ${name} {`);
  }

  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === 'object' && !Array.isArray(value) && value !== null) {
      // Nested object
      lines.push(`${indentStr}  ${key}: {`);
      const nestedLines = generateInterface('', value, indent + 1, tokens);
      lines.push(nestedLines);
      lines.push(`${indentStr}  };`);
    } else {
      // Leaf value - find token to get type
      const tokenPath = getPathToValue(obj, key, []);
      const token = tokens.find(t => t.path.join('.') === tokenPath.join('.'));
      const type = token ? getTypeScriptType(token) : 'string | number';

      lines.push(`${indentStr}  ${key}: ${type};`);
    }
  }

  if (indent === 0) {
    lines.push('}');
  }

  return lines.join('\n');
}

/**
 * Get path to value in nested object
 */
function getPathToValue(obj: any, targetKey: string, currentPath: string[]): string[] {
  for (const [key, value] of Object.entries(obj)) {
    if (key === targetKey) {
      return [...currentPath, key];
    }

    if (typeof value === 'object' && !Array.isArray(value) && value !== null) {
      const result = getPathToValue(value, targetKey, [...currentPath, key]);
      if (result.length > 0) return result;
    }
  }

  return currentPath;
}

/**
 * Generate TypeScript constants
 */
function generateConstants(obj: any, indent: number = 0, isRoot: boolean = true): string {
  const indentStr = '  '.repeat(indent);
  const lines: string[] = [];

  if (isRoot) {
    lines.push('export const tokens = {');
  }

  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === 'object' && !Array.isArray(value) && value !== null) {
      // Nested object
      lines.push(`${indentStr}  ${key}: {`);
      const nestedLines = generateConstants(value, indent + 1, false);
      lines.push(nestedLines);
      lines.push(`${indentStr}  },`);
    } else {
      // Leaf value
      const valueStr = typeof value === 'string' ? `'${value}'` : value;
      lines.push(`${indentStr}  ${key}: ${valueStr},`);
    }
  }

  if (isRoot) {
    lines.push('} as const;');
    lines.push('');
    lines.push('export type Tokens = typeof tokens;');
  }

  return lines.join('\n');
}

/**
 * Generate category-specific interfaces
 */
function generateCategoryInterfaces(tokens: Token[]): string {
  const categories = new Map<string, Token[]>();

  for (const token of tokens) {
    const category = token.category || 'general';
    if (!categories.has(category)) {
      categories.set(category, []);
    }
    categories.get(category)!.push(token);
  }

  const lines: string[] = [];

  for (const [category, categoryTokens] of categories) {
    const capitalized = category.charAt(0).toUpperCase() + category.slice(1);
    const structure = buildNestedStructure(categoryTokens);

    lines.push(`export interface ${capitalized}Tokens {`);

    for (const [key, value] of Object.entries(structure)) {
      if (typeof value === 'object' && !Array.isArray(value)) {
        lines.push(`  ${key}: {`);
        const nested = generateInterface('', value, 1, categoryTokens);
        lines.push(nested);
        lines.push('  };');
      } else {
        const token = categoryTokens.find(t => t.path[t.path.length - 1] === key);
        const type = token ? getTypeScriptType(token) : 'string';
        lines.push(`  ${key}: ${type};`);
      }
    }

    lines.push('}');
    lines.push('');
  }

  return lines.join('\n');
}

/**
 * Generate TypeScript output files
 */
export async function generateTypeScriptOutput(
  tokens: Token[],
  options: TypeScriptOutputOptions
): Promise<void> {
  const {
    outputPath,
    generateTypes = true,
    generateConstants = true,
    exportType = 'both',
    indent = 2,
  } = options;

  const outputDir = path.dirname(outputPath);
  await fs.mkdir(outputDir, { recursive: true });

  const structure = buildNestedStructure(tokens);

  // Generate type definitions file (.d.ts)
  if (generateTypes) {
    const typeDefPath = outputPath.replace(/\.ts$/, '.d.ts');
    const typeDefLines: string[] = [];

    typeDefLines.push('/**');
    typeDefLines.push(' * Design Token Type Definitions');
    typeDefLines.push(` * Generated: ${new Date().toISOString()}`);
    typeDefLines.push(' * Do not edit manually - this file is auto-generated');
    typeDefLines.push(' */');
    typeDefLines.push('');

    // Main DesignTokens interface
    typeDefLines.push(generateInterface('DesignTokens', structure, 0, tokens));
    typeDefLines.push('');

    // Category-specific interfaces
    typeDefLines.push(generateCategoryInterfaces(tokens));

    // Export statement
    if (exportType === 'named' || exportType === 'both') {
      typeDefLines.push('export declare const tokens: DesignTokens;');
    }

    if (exportType === 'default' || exportType === 'both') {
      typeDefLines.push('declare const _default: DesignTokens;');
      typeDefLines.push('export default _default;');
    }

    await fs.writeFile(typeDefPath, typeDefLines.join('\n'));
  }

  // Generate constants file (.ts)
  if (generateConstants) {
    const constantsLines: string[] = [];

    constantsLines.push('/**');
    constantsLines.push(' * Design Token Constants');
    constantsLines.push(` * Generated: ${new Date().toISOString()}`);
    constantsLines.push(' * Do not edit manually - this file is auto-generated');
    constantsLines.push(' */');
    constantsLines.push('');

    constantsLines.push(generateConstants(structure, 0, true));
    constantsLines.push('');

    if (exportType === 'default' || exportType === 'both') {
      constantsLines.push('export default tokens;');
    }

    await fs.writeFile(outputPath, constantsLines.join('\n'));
  }
}
