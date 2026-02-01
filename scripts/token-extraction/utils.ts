/**
 * Utility functions for token extraction and processing
 */

import { Token, TokenType, W3CDesignToken } from './types';

/**
 * Infer token type from value and key
 */
export function inferTokenType(value: any, key: string): TokenType | undefined {
  const keyLower = key.toLowerCase();

  // Color detection
  if (
    typeof value === 'string' &&
    (/^#[0-9a-f]{3,8}$/i.test(value) ||
     /^rgb\(/.test(value) ||
     /^rgba\(/.test(value) ||
     /^hsl\(/.test(value) ||
     /^hsla\(/.test(value) ||
     /^var\(--.*color.*\)/.test(value) ||
     keyLower.includes('color') ||
     keyLower.includes('bg') ||
     keyLower.includes('background') ||
     keyLower.includes('border') && !keyLower.includes('width'))
  ) {
    return 'color';
  }

  // Dimension detection (px, rem, em, etc.)
  if (
    typeof value === 'string' &&
    (/^\d+(\.\d+)?(px|rem|em|%|vh|vw|vmin|vmax)$/.test(value) ||
     keyLower.includes('width') ||
     keyLower.includes('height') ||
     keyLower.includes('size') ||
     keyLower.includes('spacing') ||
     keyLower.includes('gap') ||
     keyLower.includes('margin') ||
     keyLower.includes('padding'))
  ) {
    return 'dimension';
  }

  // Font family detection
  if (
    (typeof value === 'string' || Array.isArray(value)) &&
    (keyLower.includes('font') && keyLower.includes('family'))
  ) {
    return 'fontFamily';
  }

  // Font weight detection
  if (
    (typeof value === 'number' || typeof value === 'string') &&
    keyLower.includes('weight')
  ) {
    return 'fontWeight';
  }

  // Duration detection (for animations)
  if (
    typeof value === 'string' &&
    /^\d+(\.\d+)?(ms|s)$/.test(value)
  ) {
    return 'duration';
  }

  // Cubic bezier detection
  if (
    typeof value === 'string' &&
    /^cubic-bezier\(/.test(value)
  ) {
    return 'cubicBezier';
  }

  // Shadow detection
  if (
    typeof value === 'string' &&
    (keyLower.includes('shadow') || /^\d+px\s+\d+px/.test(value))
  ) {
    return 'shadow';
  }

  // Number detection
  if (typeof value === 'number') {
    return 'number';
  }

  // Default to string for unknown types
  if (typeof value === 'string') {
    return 'string';
  }

  return undefined;
}

/**
 * Normalize token name to kebab-case
 */
export function normalizeTokenName(name: string): string {
  return name
    .replace(/([a-z])([A-Z])/g, '$1-$2') // camelCase to kebab-case
    .replace(/[\s_]+/g, '-') // spaces and underscores to hyphens
    .replace(/^-+|-+$/g, '') // trim hyphens
    .toLowerCase();
}

/**
 * Create hierarchical path from keys
 */
export function createTokenPath(keys: string[]): string[] {
  return keys.map(normalizeTokenName);
}

/**
 * Check if value is a token reference (e.g., {colors.primary})
 */
export function isTokenReference(value: any): boolean {
  return typeof value === 'string' && /^\{[^}]+\}$/.test(value);
}

/**
 * Resolve token reference to path
 */
export function resolveTokenReference(value: string): string[] {
  const match = value.match(/^\{([^}]+)\}$/);
  if (!match) return [];
  return match[1].split('.');
}

/**
 * Convert token to W3C Design Token format
 */
export function toW3CToken(token: Token): W3CDesignToken {
  const w3cToken: W3CDesignToken = {
    $value: token.value,
  };

  if (token.type) {
    w3cToken.$type = token.type;
  }

  if (token.description) {
    w3cToken.$description = token.description;
  }

  // Add extensions for metadata
  if (token.metadata || token.source || token.originalKey) {
    w3cToken.$extensions = {
      'com.claude-octopus': {
        source: token.source,
        originalKey: token.originalKey,
        ...token.metadata,
      },
    };
  }

  return w3cToken;
}

/**
 * Flatten nested object into token paths
 */
export function flattenObject(
  obj: Record<string, any>,
  prefix: string[] = []
): Array<{ path: string[]; value: any }> {
  const result: Array<{ path: string[]; value: any }> = [];

  for (const [key, value] of Object.entries(obj)) {
    const currentPath = [...prefix, key];

    if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
      // Check if this is a W3C token (has $value)
      if ('$value' in value) {
        result.push({ path: currentPath, value: value.$value });
      } else {
        // Recursively flatten nested objects
        result.push(...flattenObject(value, currentPath));
      }
    } else {
      // Primitive value or array
      result.push({ path: currentPath, value });
    }
  }

  return result;
}

/**
 * Create nested object from flat token path
 */
export function unflattenTokens(tokens: Token[]): Record<string, any> {
  const result: Record<string, any> = {};

  for (const token of tokens) {
    let current = result;
    const path = token.path;

    // Navigate/create nested structure
    for (let i = 0; i < path.length - 1; i++) {
      const key = path[i];
      if (!(key in current)) {
        current[key] = {};
      }
      current = current[key];
    }

    // Set the final value as W3C token
    const finalKey = path[path.length - 1];
    current[finalKey] = toW3CToken(token);
  }

  return result;
}

/**
 * Validate token value based on type
 */
export function validateToken(token: Token): { valid: boolean; error?: string } {
  if (!token.type) {
    return { valid: true }; // No type specified, skip validation
  }

  switch (token.type) {
    case 'color':
      if (typeof token.value !== 'string') {
        return { valid: false, error: 'Color must be a string' };
      }
      if (
        !/^#[0-9a-f]{3,8}$/i.test(token.value) &&
        !/^rgb\(/.test(token.value) &&
        !/^rgba\(/.test(token.value) &&
        !/^hsl\(/.test(token.value) &&
        !/^hsla\(/.test(token.value) &&
        !isTokenReference(token.value)
      ) {
        return { valid: false, error: 'Invalid color format' };
      }
      break;

    case 'dimension':
      if (typeof token.value !== 'string') {
        return { valid: false, error: 'Dimension must be a string' };
      }
      if (!/^\d+(\.\d+)?(px|rem|em|%|vh|vw|vmin|vmax)$/.test(token.value)) {
        return { valid: false, error: 'Invalid dimension format' };
      }
      break;

    case 'fontWeight':
      if (
        typeof token.value !== 'number' &&
        typeof token.value !== 'string'
      ) {
        return { valid: false, error: 'Font weight must be number or string' };
      }
      if (typeof token.value === 'number') {
        if (token.value < 100 || token.value > 900 || token.value % 100 !== 0) {
          return { valid: false, error: 'Font weight must be 100-900 in increments of 100' };
        }
      }
      break;

    case 'duration':
      if (typeof token.value !== 'string') {
        return { valid: false, error: 'Duration must be a string' };
      }
      if (!/^\d+(\.\d+)?(ms|s)$/.test(token.value)) {
        return { valid: false, error: 'Invalid duration format (use ms or s)' };
      }
      break;

    case 'number':
      if (typeof token.value !== 'number') {
        return { valid: false, error: 'Expected number type' };
      }
      break;
  }

  return { valid: true };
}

/**
 * Deep merge objects
 */
export function deepMerge<T extends Record<string, any>>(
  target: T,
  source: Record<string, any>
): T {
  const result = { ...target };

  for (const key in source) {
    if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
      if (result[key] && typeof result[key] === 'object' && !Array.isArray(result[key])) {
        result[key] = deepMerge(result[key], source[key]);
      } else {
        result[key] = source[key];
      }
    } else {
      result[key] = source[key];
    }
  }

  return result;
}

/**
 * Get CSS variable name from token path
 */
export function toCSSVariableName(path: string[]): string {
  return '--' + path.join('-');
}

/**
 * Parse CSS variable name to path
 */
export function parseCSSVariableName(name: string): string[] {
  return name.replace(/^--/, '').split('-');
}

/**
 * Format token value for CSS output
 */
export function formatCSSValue(value: any): string {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number') {
    return String(value);
  }
  if (Array.isArray(value)) {
    return value.join(', ');
  }
  if (typeof value === 'object') {
    return JSON.stringify(value);
  }
  return String(value);
}

/**
 * Sanitize filename
 */
export function sanitizeFilename(filename: string): string {
  return filename.replace(/[^a-z0-9._-]/gi, '_');
}
