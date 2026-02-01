/**
 * Interaction States Extractor
 * Captures :hover, :focus, :active, and other pseudo-state styles from browser
 */

import {
  Token,
  TokenSource,
  ExtractionError,
  InteractionState,
  BrowserExtractionResult,
} from '../types';

export interface InteractionStatesOptions {
  url: string;
  tabId: number;
  selectors?: string[];
  states?: Array<'hover' | 'focus' | 'active' | 'disabled' | 'checked'>;
  captureTransitions?: boolean;
  timeout?: number;
}

/**
 * Interaction States Extractor Class
 */
export class InteractionStatesExtractor {
  private options: Required<InteractionStatesOptions>;
  private errors: ExtractionError[] = [];

  constructor(options: InteractionStatesOptions) {
    this.options = {
      selectors: ['button', 'a', 'input', '[role="button"]'],
      states: ['hover', 'focus', 'active'],
      captureTransitions: true,
      timeout: 30000,
      ...options,
    };
  }

  /**
   * Extract interaction state tokens
   */
  async extract(): Promise<BrowserExtractionResult> {
    this.errors = [];
    const tokens: Token[] = [];
    let interactionStatesFound = 0;

    try {
      // Step 1: For each selector, capture all interaction states
      for (const selector of this.options.selectors) {
        const stateTokens = await this.extractStatesForSelector(selector);
        tokens.push(...stateTokens);
        interactionStatesFound += stateTokens.length;
      }

      return {
        tokens,
        errors: this.errors,
        metadata: {
          url: this.options.url,
          timestamp: new Date().toISOString(),
          elementsCaptured: this.options.selectors.length,
          interactionStatesFound,
        },
      };
    } catch (error) {
      this.errors.push({
        source: TokenSource.INTERACTION_STATES,
        message: `Interaction states extraction failed: ${error instanceof Error ? error.message : String(error)}`,
        error: error instanceof Error ? error : undefined,
      });

      return {
        tokens: [],
        errors: this.errors,
        metadata: {
          url: this.options.url,
          timestamp: new Date().toISOString(),
          elementsCaptured: 0,
          interactionStatesFound: 0,
        },
      };
    }
  }

  /**
   * Extract all states for a given selector
   */
  private async extractStatesForSelector(selector: string): Promise<Token[]> {
    const tokens: Token[] = [];

    // Get base (default) styles first
    const baseStyles = await this.getComputedStyles(selector);

    // Capture each interaction state
    for (const state of this.options.states) {
      try {
        const stateStyles = await this.captureStateStyles(selector, state);
        const stateTokens = this.generateStateTokens(
          selector,
          state,
          baseStyles,
          stateStyles
        );
        tokens.push(...stateTokens);
      } catch (error) {
        this.errors.push({
          source: TokenSource.INTERACTION_STATES,
          message: `Failed to capture ${state} state for "${selector}": ${error instanceof Error ? error.message : String(error)}`,
        });
      }
    }

    // Capture transitions if enabled
    if (this.options.captureTransitions) {
      const transitionTokens = await this.captureTransitions(selector, baseStyles);
      tokens.push(...transitionTokens);
    }

    return tokens;
  }

  /**
   * Get computed styles for element in normal state
   */
  private async getComputedStyles(selector: string): Promise<Record<string, string>> {
    // In real implementation, use mcp__claude-in-chrome__javascript_tool:
    // const el = document.querySelector(selector);
    // return window.getComputedStyle(el);

    // Mock implementation
    return this.getMockBaseStyles(selector);
  }

  /**
   * Capture styles for a specific pseudo-state
   */
  private async captureStateStyles(
    selector: string,
    state: string
  ): Promise<Record<string, string>> {
    try {
      // Real implementation would:
      // 1. Use mcp__claude-in-chrome__computer to trigger the state
      //    - For hover: Move mouse to element coordinates
      //    - For focus: Click element or use keyboard navigation
      //    - For active: Mouse down on element
      // 2. Capture styles using mcp__claude-in-chrome__javascript_tool
      // 3. Restore original state

      // For now, return mock state styles
      return this.getMockStateStyles(selector, state);
    } catch (error) {
      throw new Error(`Failed to capture ${state} state: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * Generate tokens from state styles
   */
  private generateStateTokens(
    selector: string,
    state: string,
    baseStyles: Record<string, string>,
    stateStyles: Record<string, string>
  ): Token[] {
    const tokens: Token[] = [];
    const selectorName = this.selectorToTokenName(selector);

    // Compare state styles with base styles and only create tokens for differences
    const changedProps = this.getChangedProperties(baseStyles, stateStyles);

    for (const prop of changedProps) {
      const value = stateStyles[prop];
      const tokenName = `${selectorName}-${state}-${this.camelToKebab(prop)}`;
      const path = [selectorName, 'states', state, this.camelToKebab(prop)];

      tokens.push({
        name: tokenName,
        value,
        type: this.inferTypeFromProperty(prop),
        category: 'interaction-states',
        source: TokenSource.INTERACTION_STATES,
        priority: 60, // Higher priority than basic browser extraction
        path,
        description: `${selector} ${state} state ${prop}`,
        metadata: {
          extractedFrom: 'browser',
          selector,
          state,
          property: prop,
          baseValue: baseStyles[prop],
        },
      });
    }

    return tokens;
  }

  /**
   * Capture transition properties
   */
  private async captureTransitions(
    selector: string,
    styles: Record<string, string>
  ): Promise<Token[]> {
    const tokens: Token[] = [];
    const selectorName = this.selectorToTokenName(selector);

    // Extract transition-related properties
    const transitionProps = [
      'transition',
      'transitionProperty',
      'transitionDuration',
      'transitionTimingFunction',
      'transitionDelay',
    ];

    for (const prop of transitionProps) {
      if (styles[prop] && styles[prop] !== 'none' && styles[prop] !== '0s') {
        const tokenName = `${selectorName}-${this.camelToKebab(prop)}`;
        const path = [selectorName, 'transitions', this.camelToKebab(prop)];

        tokens.push({
          name: tokenName,
          value: styles[prop],
          type: 'transition',
          category: 'transitions',
          source: TokenSource.INTERACTION_STATES,
          priority: 60,
          path,
          description: `${selector} ${prop}`,
          metadata: {
            extractedFrom: 'browser',
            selector,
            property: prop,
          },
        });
      }
    }

    return tokens;
  }

  /**
   * Get properties that changed between base and state
   */
  private getChangedProperties(
    baseStyles: Record<string, string>,
    stateStyles: Record<string, string>
  ): string[] {
    const changed: string[] = [];
    const relevantProps = [
      'color',
      'backgroundColor',
      'borderColor',
      'opacity',
      'transform',
      'boxShadow',
      'textDecoration',
      'outline',
      'outlineColor',
      'outlineWidth',
    ];

    for (const prop of relevantProps) {
      if (stateStyles[prop] && stateStyles[prop] !== baseStyles[prop]) {
        changed.push(prop);
      }
    }

    return changed;
  }

  /**
   * Convert selector to token name
   */
  private selectorToTokenName(selector: string): string {
    return selector
      .replace(/[^a-zA-Z0-9\-]/g, '-')
      .replace(/^-+|-+$/g, '')
      .toLowerCase();
  }

  /**
   * Convert camelCase to kebab-case
   */
  private camelToKebab(str: string): string {
    return str.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase();
  }

  /**
   * Infer token type from CSS property
   */
  private inferTypeFromProperty(property: string): any {
    const typeMap: Record<string, string> = {
      color: 'color',
      backgroundColor: 'color',
      borderColor: 'color',
      outlineColor: 'color',
      opacity: 'number',
      transform: 'string',
      boxShadow: 'shadow',
      textDecoration: 'string',
      outline: 'string',
      outlineWidth: 'dimension',
    };
    return typeMap[property] || 'string';
  }

  /**
   * Mock base styles (to be replaced with real MCP calls)
   */
  private getMockBaseStyles(selector: string): Record<string, string> {
    return {
      color: '#000000',
      backgroundColor: '#f3f4f6',
      borderColor: '#d1d5db',
      opacity: '1',
      transform: 'none',
      boxShadow: 'none',
      textDecoration: 'none',
      outline: 'none',
      outlineColor: 'transparent',
      outlineWidth: '0px',
      transition: 'all 0.2s ease-in-out',
      transitionProperty: 'all',
      transitionDuration: '0.2s',
      transitionTimingFunction: 'ease-in-out',
      transitionDelay: '0s',
    };
  }

  /**
   * Mock state styles (to be replaced with real MCP calls)
   */
  private getMockStateStyles(selector: string, state: string): Record<string, string> {
    const base = this.getMockBaseStyles(selector);

    const stateChanges: Record<string, Partial<Record<string, string>>> = {
      hover: {
        backgroundColor: '#e5e7eb',
        borderColor: '#9ca3af',
        transform: 'translateY(-1px)',
        boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.1)',
      },
      focus: {
        outline: '2px solid #3b82f6',
        outlineColor: '#3b82f6',
        outlineWidth: '2px',
        borderColor: '#3b82f6',
      },
      active: {
        backgroundColor: '#d1d5db',
        transform: 'translateY(0)',
        boxShadow: '0 1px 2px 0 rgba(0, 0, 0, 0.05)',
      },
      disabled: {
        opacity: '0.5',
        color: '#9ca3af',
      },
      checked: {
        backgroundColor: '#3b82f6',
        borderColor: '#3b82f6',
      },
    };

    return {
      ...base,
      ...(stateChanges[state] || {}),
    };
  }
}

/**
 * Convenience function to extract interaction states
 */
export async function extractInteractionStates(
  url: string,
  tabId: number,
  options?: Partial<InteractionStatesOptions>
): Promise<BrowserExtractionResult> {
  const extractor = new InteractionStatesExtractor({
    url,
    tabId,
    ...options,
  });

  return extractor.extract();
}
