/**
 * JSON Output Generator
 * Generates W3C Design Tokens JSON format
 */

import * as fs from 'fs';
import * as path from 'path';
import {
  Token,
  W3CTokensFile,
  W3CTokenGroup,
} from '../types';
import { unflattenTokens } from '../utils';

export interface JSONOutputOptions {
  outputPath: string;
  prettify?: boolean;
  indent?: number;
  includeSchema?: boolean;
  includeDescription?: boolean;
}

export class JSONOutputGenerator {
  private options: JSONOutputOptions;

  constructor(options: JSONOutputOptions) {
    this.options = {
      prettify: true,
      indent: 2,
      includeSchema: true,
      includeDescription: true,
      ...options,
    };
  }

  /**
   * Generate JSON output
   */
  async generate(tokens: Token[]): Promise<void> {
    const w3cTokens = this.toW3CFormat(tokens);
    const json = this.stringify(w3cTokens);

    // Ensure output directory exists
    const outputDir = path.dirname(this.options.outputPath);
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    // Write to file
    fs.writeFileSync(this.options.outputPath, json, 'utf-8');
  }

  /**
   * Convert tokens to W3C Design Tokens format
   */
  private toW3CFormat(tokens: Token[]): W3CTokensFile {
    const w3cFile: W3CTokensFile = {};

    // Add schema reference
    if (this.options.includeSchema) {
      w3cFile.$schema = 'https://tr.designtokens.org/format/';
    }

    // Add description
    if (this.options.includeDescription) {
      w3cFile.$description = 'Design tokens extracted from project sources';
    }

    // Convert tokens to nested W3C format
    const nestedTokens = unflattenTokens(tokens);

    // Merge into the W3C file
    Object.assign(w3cFile, nestedTokens);

    return w3cFile;
  }

  /**
   * Stringify W3C tokens
   */
  private stringify(w3cTokens: W3CTokensFile): string {
    if (this.options.prettify) {
      return JSON.stringify(w3cTokens, null, this.options.indent);
    }

    return JSON.stringify(w3cTokens);
  }
}

/**
 * Convenience function to generate JSON output
 */
export async function generateJSONOutput(
  tokens: Token[],
  options: JSONOutputOptions
): Promise<void> {
  const generator = new JSONOutputGenerator(options);
  await generator.generate(tokens);
}
