/**
 * Token Merger
 * Handles merging tokens from multiple sources with conflict detection and resolution
 */

import {
  Token,
  TokenConflict,
  ExtractionOptions,
  SourcePriority,
  TokenSource,
  MergeStrategy,
} from './types';
import { validateToken } from './utils';

export class TokenMerger {
  private options: ExtractionOptions;
  private conflicts: TokenConflict[] = [];

  constructor(options: ExtractionOptions = {}) {
    this.options = {
      conflictResolution: 'priority',
      ...options,
    };
  }

  /**
   * Merge tokens from multiple sources
   */
  merge(tokenLists: Token[][]): { tokens: Token[]; conflicts: TokenConflict[] } {
    this.conflicts = [];
    const allTokens = tokenLists.flat();

    // Group tokens by their path
    const tokensByPath = this.groupTokensByPath(allTokens);

    // Resolve conflicts and merge
    const mergedTokens: Token[] = [];

    for (const [pathKey, tokens] of Object.entries(tokensByPath)) {
      if (tokens.length === 1) {
        // No conflict, use the token as-is
        mergedTokens.push(tokens[0]);
      } else {
        // Conflict detected, resolve it
        const resolved = this.resolveConflict(tokens);
        mergedTokens.push(resolved.token);

        if (resolved.conflict) {
          this.conflicts.push(resolved.conflict);
        }
      }
    }

    return {
      tokens: mergedTokens,
      conflicts: this.conflicts,
    };
  }

  /**
   * Group tokens by their path for conflict detection
   */
  private groupTokensByPath(tokens: Token[]): Record<string, Token[]> {
    const grouped: Record<string, Token[]> = {};

    for (const token of tokens) {
      const key = token.path.join('.');

      if (!grouped[key]) {
        grouped[key] = [];
      }

      grouped[key].push(token);
    }

    return grouped;
  }

  /**
   * Resolve conflict between multiple tokens with the same path
   */
  private resolveConflict(tokens: Token[]): {
    token: Token;
    conflict?: TokenConflict;
  } {
    // Sort tokens by priority (higher priority first)
    const sortedTokens = [...tokens].sort((a, b) => b.priority - a.priority);

    const conflict: TokenConflict = {
      path: tokens[0].path,
      tokens: sortedTokens,
      resolution: 'auto',
    };

    let resolvedToken: Token;

    switch (this.options.conflictResolution) {
      case 'priority':
        // Use token with highest priority
        resolvedToken = this.resolveByPriority(sortedTokens);
        conflict.reason = `Resolved by priority: ${resolvedToken.source} (priority ${resolvedToken.priority})`;
        conflict.resolvedToken = resolvedToken;
        break;

      case 'merge':
        // Attempt to merge values if possible
        resolvedToken = this.resolveByMerge(sortedTokens);
        conflict.reason = 'Merged values from multiple sources';
        conflict.resolvedToken = resolvedToken;
        break;

      case 'manual':
        // Mark for manual resolution, use highest priority as default
        resolvedToken = sortedTokens[0];
        conflict.resolution = 'manual';
        conflict.reason = 'Requires manual resolution';
        break;

      default:
        resolvedToken = sortedTokens[0];
        conflict.reason = 'Default resolution';
    }

    return {
      token: resolvedToken,
      conflict,
    };
  }

  /**
   * Resolve by priority
   */
  private resolveByPriority(tokens: Token[]): Token {
    return tokens[0]; // Already sorted by priority
  }

  /**
   * Resolve by merging compatible values
   */
  private resolveByMerge(tokens: Token[]): Token {
    const baseToken = tokens[0];

    // Check if all tokens have the same value
    const allSameValue = tokens.every(t =>
      JSON.stringify(t.value) === JSON.stringify(baseToken.value)
    );

    if (allSameValue) {
      // Values are identical, just use the highest priority token
      return baseToken;
    }

    // Check if values are compatible for merging
    const allNumbers = tokens.every(t => typeof t.value === 'number');
    const allStrings = tokens.every(t => typeof t.value === 'string');

    if (allNumbers) {
      // For numbers, use the highest priority value but note the conflict
      return {
        ...baseToken,
        metadata: {
          ...baseToken.metadata,
          conflictingSources: tokens.map(t => ({
            source: t.source,
            value: t.value,
          })),
        },
      };
    }

    if (allStrings) {
      // For strings, use the highest priority value
      return {
        ...baseToken,
        metadata: {
          ...baseToken.metadata,
          conflictingSources: tokens.map(t => ({
            source: t.source,
            value: t.value,
          })),
        },
      };
    }

    // Cannot merge, use highest priority
    return baseToken;
  }

  /**
   * Apply custom merge strategy
   */
  applyCustomStrategy(tokens: Token[], strategy: MergeStrategy): Token[] {
    const tokensByPath = this.groupTokensByPath(tokens);
    const result: Token[] = [];

    for (const [pathKey, pathTokens] of Object.entries(tokensByPath)) {
      if (pathTokens.length === 1) {
        result.push(pathTokens[0]);
        continue;
      }

      // Check if tokens should be merged
      let current = pathTokens[0];

      for (let i = 1; i < pathTokens.length; i++) {
        const incoming = pathTokens[i];

        if (strategy.shouldMerge(current, incoming)) {
          current = strategy.onConflict(current, incoming);
        }
      }

      result.push(current);
    }

    return result;
  }

  /**
   * Filter tokens by source inclusion/exclusion
   */
  filterBySources(tokens: Token[]): Token[] {
    let filtered = tokens;

    if (this.options.includeSources && this.options.includeSources.length > 0) {
      filtered = filtered.filter(token =>
        this.options.includeSources!.includes(token.source)
      );
    }

    if (this.options.excludeSources && this.options.excludeSources.length > 0) {
      filtered = filtered.filter(token =>
        !this.options.excludeSources!.includes(token.source)
      );
    }

    return filtered;
  }

  /**
   * Validate all tokens
   */
  validateTokens(tokens: Token[]): { valid: Token[]; invalid: Token[] } {
    if (!this.options.validateTokens) {
      return { valid: tokens, invalid: [] };
    }

    const valid: Token[] = [];
    const invalid: Token[] = [];

    for (const token of tokens) {
      const validation = validateToken(token);

      if (validation.valid) {
        valid.push(token);
      } else {
        invalid.push({
          ...token,
          metadata: {
            ...token.metadata,
            validationError: validation.error,
          },
        });
      }
    }

    return { valid, invalid };
  }

  /**
   * Get detected conflicts
   */
  getConflicts(): TokenConflict[] {
    return this.conflicts;
  }

  /**
   * Get conflicts that require manual resolution
   */
  getManualConflicts(): TokenConflict[] {
    return this.conflicts.filter(c => c.resolution === 'manual');
  }

  /**
   * Analyze conflict statistics
   */
  getConflictStats(): {
    total: number;
    auto: number;
    manual: number;
    bySource: Record<string, number>;
  } {
    const stats = {
      total: this.conflicts.length,
      auto: this.conflicts.filter(c => c.resolution === 'auto').length,
      manual: this.conflicts.filter(c => c.resolution === 'manual').length,
      bySource: {} as Record<string, number>,
    };

    for (const conflict of this.conflicts) {
      for (const token of conflict.tokens) {
        const source = token.source;
        stats.bySource[source] = (stats.bySource[source] || 0) + 1;
      }
    }

    return stats;
  }
}

/**
 * Default source priorities
 */
export const DEFAULT_SOURCE_PRIORITIES: SourcePriority[] = [
  { source: TokenSource.TAILWIND_CONFIG, priority: 8 },
  { source: TokenSource.STYLED_COMPONENTS, priority: 7 },
  { source: TokenSource.EMOTION_THEME, priority: 7 },
  { source: TokenSource.THEME_FILE, priority: 7 },
  { source: TokenSource.CSS_VARIABLES, priority: 6 },
];

/**
 * Apply priorities to tokens
 */
export function applyPriorities(
  tokens: Token[],
  priorities: SourcePriority[] = DEFAULT_SOURCE_PRIORITIES
): Token[] {
  return tokens.map(token => {
    const priorityConfig = priorities.find(p => p.source === token.source);

    return {
      ...token,
      priority: priorityConfig?.priority ?? token.priority,
    };
  });
}
