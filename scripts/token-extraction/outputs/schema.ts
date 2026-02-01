/**
 * JSON Schema Output Generator
 * Generates JSON Schema (Draft 2020-12) for design tokens
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { Token, TokenType } from '../types';

interface SchemaOutputOptions {
  outputPath: string;
  schemaId?: string;
  title?: string;
  description?: string;
}

/**
 * Map token type to JSON Schema type
 */
function mapToJsonSchemaType(type?: TokenType): any {
  if (!type) return { type: ['string', 'number'] };

  const typeMap: Record<TokenType, any> = {
    color: { type: 'string', pattern: '^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$|^rgb\\(|^hsl\\(' },
    dimension: { type: 'string', pattern: '^-?\\d+(\\.\\d+)?(px|rem|em|%|vh|vw)$' },
    fontFamily: { type: 'string' },
    fontWeight: { type: ['number', 'string'] },
    duration: { type: 'string', pattern: '^\\d+(\\.\\d+)?(ms|s)$' },
    cubicBezier: { type: 'string', pattern: '^cubic-bezier\\(' },
    number: { type: 'number' },
    string: { type: 'string' },
    shadow: { type: 'string' },
    gradient: { type: 'string' },
    typography: { type: 'object' },
    border: { type: 'string' },
    transition: { type: 'string' },
  };

  return typeMap[type] || { type: 'string' };
}

/**
 * Build JSON Schema properties from tokens
 */
function buildSchemaProperties(tokens: Token[]): any {
  const properties: any = {};
  const required: string[] = [];

  // Group tokens by their top-level category
  const categories = new Map<string, Token[]>();

  for (const token of tokens) {
    const topLevel = token.path[0] || 'general';
    if (!categories.has(topLevel)) {
      categories.set(topLevel, []);
    }
    categories.get(topLevel)!.push(token);
  }

  // Build nested schema for each category
  for (const [category, categoryTokens] of categories) {
    properties[category] = buildNestedSchema(categoryTokens, 1);
    required.push(category);
  }

  return { properties, required };
}

/**
 * Build nested schema structure
 */
function buildNestedSchema(tokens: Token[], pathIndex: number): any {
  const groups = new Map<string, Token[]>();
  const leaves: Token[] = [];

  for (const token of tokens) {
    if (token.path.length === pathIndex + 1) {
      // This is a leaf node
      leaves.push(token);
    } else {
      // This has more nesting
      const nextSegment = token.path[pathIndex];
      if (!groups.has(nextSegment)) {
        groups.set(nextSegment, []);
      }
      groups.get(nextSegment)!.push(token);
    }
  }

  if (leaves.length > 0 && groups.size === 0) {
    // All leaves - create object with properties
    const properties: any = {};
    const required: string[] = [];

    for (const token of leaves) {
      const key = token.path[pathIndex];
      properties[key] = {
        ...mapToJsonSchemaType(token.type),
        description: token.description || `${token.name} token`,
      };
      required.push(key);
    }

    return {
      type: 'object',
      properties,
      required,
    };
  }

  if (groups.size > 0) {
    // Has nested groups
    const properties: any = {};
    const required: string[] = [];

    for (const [key, groupTokens] of groups) {
      properties[key] = buildNestedSchema(groupTokens, pathIndex + 1);
      required.push(key);
    }

    // Add any leaves at this level
    for (const token of leaves) {
      const key = token.path[pathIndex];
      properties[key] = {
        ...mapToJsonSchemaType(token.type),
        description: token.description || `${token.name} token`,
      };
      required.push(key);
    }

    return {
      type: 'object',
      properties,
      required,
    };
  }

  return { type: 'object' };
}

/**
 * Generate JSON Schema for design tokens
 */
export async function generateSchemaOutput(
  tokens: Token[],
  options: SchemaOutputOptions
): Promise<void> {
  const {
    outputPath,
    schemaId = 'https://example.com/design-tokens.schema.json',
    title = 'Design Tokens Schema',
    description = 'JSON Schema for design tokens',
  } = options;

  const outputDir = path.dirname(outputPath);
  await fs.mkdir(outputDir, { recursive: true });

  const { properties, required } = buildSchemaProperties(tokens);

  const schema = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: schemaId,
    title,
    description,
    type: 'object',
    properties,
    required,
    additionalProperties: false,
  };

  await fs.writeFile(outputPath, JSON.stringify(schema, null, 2));
}
