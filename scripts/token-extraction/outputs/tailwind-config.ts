/**
 * Tailwind Config Output Generator
 * Generates Tailwind CSS configuration from design tokens
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { Token } from '../types';

interface TailwindOutputOptions {
  outputPath: string;
  mode?: 'extend' | 'replace';
  includeComments?: boolean;
}

/**
 * Map token category to Tailwind theme key
 */
function mapCategoryToTailwindKey(category: string, tokenPath: string[]): string | null {
  const categoryLower = category.toLowerCase();
  const firstPath = tokenPath[0]?.toLowerCase() || '';

  // Color mappings
  if (categoryLower.includes('color') || firstPath === 'colors') {
    return 'colors';
  }

  // Spacing mappings
  if (
    categoryLower.includes('spacing') ||
    firstPath === 'spacing' ||
    firstPath === 'space'
  ) {
    return 'spacing';
  }

  // Font family
  if (categoryLower.includes('font') && firstPath === 'family') {
    return 'fontFamily';
  }

  // Font size
  if (categoryLower.includes('font') && (firstPath === 'size' || firstPath === 'sizes')) {
    return 'fontSize';
  }

  // Font weight
  if (categoryLower.includes('font') && (firstPath === 'weight' || firstPath === 'weights')) {
    return 'fontWeight';
  }

  // Line height
  if (
    categoryLower.includes('line') ||
    firstPath === 'lineheight' ||
    firstPath === 'lineheights'
  ) {
    return 'lineHeight';
  }

  // Border radius
  if (categoryLower.includes('radius') || firstPath === 'radius' || firstPath === 'radii') {
    return 'borderRadius';
  }

  // Shadows
  if (categoryLower.includes('shadow') || firstPath === 'shadow' || firstPath === 'shadows') {
    return 'boxShadow';
  }

  // Breakpoints
  if (
    categoryLower.includes('breakpoint') ||
    firstPath === 'breakpoint' ||
    firstPath === 'breakpoints' ||
    firstPath === 'screens'
  ) {
    return 'screens';
  }

  // Z-index
  if (categoryLower.includes('z') || firstPath === 'zindex') {
    return 'zIndex';
  }

  // Transitions
  if (categoryLower.includes('transition') || firstPath === 'transition') {
    return 'transitionDuration';
  }

  return null;
}

/**
 * Build Tailwind theme structure from tokens
 */
function buildTailwindTheme(tokens: Token[]): any {
  const theme: any = {
    colors: {},
    spacing: {},
    fontFamily: {},
    fontSize: {},
    fontWeight: {},
    lineHeight: {},
    borderRadius: {},
    boxShadow: {},
    screens: {},
    zIndex: {},
  };

  for (const token of tokens) {
    const themeKey = mapCategoryToTailwindKey(
      token.category || '',
      token.path
    );

    if (!themeKey) continue;

    // Build nested structure
    let current = theme[themeKey];
    const pathWithoutFirst = token.path.slice(1); // Remove category from path

    if (pathWithoutFirst.length === 0) {
      // Direct value
      theme[themeKey] = token.value;
      continue;
    }

    for (let i = 0; i < pathWithoutFirst.length - 1; i++) {
      const segment = pathWithoutFirst[i];
      if (!current[segment]) {
        current[segment] = {};
      }
      current = current[segment];
    }

    const leafKey = pathWithoutFirst[pathWithoutFirst.length - 1];
    current[leafKey] = token.value;
  }

  // Remove empty categories
  for (const key of Object.keys(theme)) {
    if (Object.keys(theme[key]).length === 0) {
      delete theme[key];
    }
  }

  return theme;
}

/**
 * Generate Tailwind config JavaScript code
 */
function generateTailwindConfig(
  theme: any,
  mode: 'extend' | 'replace',
  includeComments: boolean
): string {
  const lines: string[] = [];

  if (includeComments) {
    lines.push('/**');
    lines.push(' * Tailwind CSS Configuration - Design Tokens');
    lines.push(` * Generated: ${new Date().toISOString()}`);
    lines.push(' * Do not edit manually - this file is auto-generated');
    lines.push(' */');
    lines.push('');
  }

  lines.push('/** @type {import(\'tailwindcss\').Config} */');
  lines.push('module.exports = {');

  if (mode === 'extend') {
    lines.push('  theme: {');
    lines.push('    extend: {');
    lines.push(generateThemeObject(theme, 3));
    lines.push('    },');
    lines.push('  },');
  } else {
    lines.push('  theme: {');
    lines.push(generateThemeObject(theme, 2));
    lines.push('  },');
  }

  lines.push('};');

  return lines.join('\n');
}

/**
 * Generate theme object with proper indentation
 */
function generateThemeObject(obj: any, indentLevel: number): string {
  const lines: string[] = [];
  const indent = '  '.repeat(indentLevel);

  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === 'object' && !Array.isArray(value) && value !== null) {
      lines.push(`${indent}${key}: {`);
      lines.push(generateThemeObject(value, indentLevel + 1));
      lines.push(`${indent}},`);
    } else if (Array.isArray(value)) {
      const arrayStr = JSON.stringify(value);
      lines.push(`${indent}${key}: ${arrayStr},`);
    } else if (typeof value === 'string') {
      lines.push(`${indent}${key}: '${value}',`);
    } else {
      lines.push(`${indent}${key}: ${value},`);
    }
  }

  return lines.join('\n');
}

/**
 * Generate Tailwind configuration file
 */
export async function generateTailwindConfigOutput(
  tokens: Token[],
  options: TailwindOutputOptions
): Promise<void> {
  const {
    outputPath,
    mode = 'extend',
    includeComments = true,
  } = options;

  const outputDir = path.dirname(outputPath);
  await fs.mkdir(outputDir, { recursive: true });

  const theme = buildTailwindTheme(tokens);
  const config = generateTailwindConfig(theme, mode, includeComments);

  await fs.writeFile(outputPath, config);
}
