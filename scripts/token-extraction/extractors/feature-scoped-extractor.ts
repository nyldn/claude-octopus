/**
 * Feature Scoped Extractor
 * Filters extraction results to specific feature scopes
 */

import * as path from 'path';
import { minimatch } from 'minimatch';
import { Token, FeatureScope, ExtractionError } from '../types';

export class FeatureScopedExtractor {
  private scope: FeatureScope;

  constructor(scope: FeatureScope) {
    this.scope = scope;
  }

  /**
   * Filter tokens to only those within the feature scope
   */
  filterTokens(tokens: Token[]): Token[] {
    const filtered: Token[] = [];

    for (const token of tokens) {
      if (this.isTokenInScope(token)) {
        // Tag token with feature name
        filtered.push({
          ...token,
          feature: this.scope.name,
        });
      }
    }

    console.log(`  Filtered tokens for feature "${this.scope.name}": ${filtered.length}/${tokens.length}`);

    return filtered;
  }

  /**
   * Filter extraction errors to only those relevant to the scope
   */
  filterErrors(errors: ExtractionError[]): ExtractionError[] {
    return errors.filter(error => {
      if (!error.filePath) return true; // Keep errors without file paths
      return this.isFileInScope(error.filePath);
    });
  }

  /**
   * Check if a file path is within the feature scope
   */
  isFileInScope(filePath: string): boolean {
    // Normalize path
    const normalizedPath = path.normalize(filePath);

    // Check exclude patterns first
    if (this.scope.excludePaths) {
      for (const excludePattern of this.scope.excludePaths) {
        if (minimatch(normalizedPath, excludePattern)) {
          return false;
        }
      }
    }

    // Check include patterns
    for (const includePattern of this.scope.includePaths) {
      if (minimatch(normalizedPath, includePattern)) {
        return true;
      }
    }

    // Check keyword matches if keywords are defined
    if (this.scope.keywords && this.scope.keywords.length > 0) {
      const lowerPath = normalizedPath.toLowerCase();
      for (const keyword of this.scope.keywords) {
        if (lowerPath.includes(keyword.toLowerCase())) {
          return true;
        }
      }
    }

    return false;
  }

  /**
   * Check if a token is within the feature scope
   * Tokens are in scope if their source file or metadata indicates they belong to the feature
   */
  private isTokenInScope(token: Token): boolean {
    // Check if token already has feature assignment
    if (token.feature && token.feature !== this.scope.name) {
      return false;
    }

    // Check if token has file path in metadata
    if (token.metadata?.filePath) {
      return this.isFileInScope(token.metadata.filePath);
    }

    // Check if token has source information that can be matched
    if (token.metadata?.source) {
      return this.isFileInScope(token.metadata.source);
    }

    // For tokens without file information, check if name/path includes keywords
    if (this.scope.keywords && this.scope.keywords.length > 0) {
      const tokenStr = `${token.name} ${token.path.join('.')}`.toLowerCase();
      for (const keyword of this.scope.keywords) {
        if (tokenStr.includes(keyword.toLowerCase())) {
          return true;
        }
      }
    }

    // Default: if no file info and no keyword match, exclude
    return false;
  }

  /**
   * Get the scope being used
   */
  getScope(): FeatureScope {
    return this.scope;
  }
}

/**
 * Helper function to create a feature-scoped extractor
 */
export function createFeatureScopedExtractor(scope: FeatureScope): FeatureScopedExtractor {
  return new FeatureScopedExtractor(scope);
}
