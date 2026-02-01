/**
 * Debate Integration Tests
 * Verify multi-AI debate orchestration for token validation
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  runDebateOnTokens,
  applyDebateImprovements,
  generateAuditTrail,
} from '../../debate-integration';
import { Token, TokenSource, DebateResult } from '../../types';

// Helper function to create fresh mock tokens
function createMockTokens(): Token[] {
  return [
    {
      name: 'primary-500',
      value: '#3b82f6',
      type: 'color',
      category: 'colors',
      source: TokenSource.TAILWIND_CONFIG,
      priority: 80,
      path: ['colors', 'primary', '500'],
      description: 'Primary color 500',
    },
    {
      name: 'spacing-4',
      value: '16px',
      type: 'dimension',
      category: 'spacing',
      source: TokenSource.CSS_VARIABLES,
      priority: 70,
      path: ['spacing', '4'],
      description: 'Spacing scale 4',
    },
    {
      name: 'font-size-base',
      value: '16px',
      type: 'dimension',
      category: 'typography',
      source: TokenSource.THEME_FILE,
      priority: 75,
      path: ['typography', 'fontSize', 'base'],
      description: 'Base font size',
    },
  ];
}

describe('Debate Integration', () => {
  beforeEach(() => {
    // Clear all mocks before each test
    vi.clearAllMocks();
  });

  describe('runDebateOnTokens', () => {
    it('should run debate with default options', async () => {
      const result = await runDebateOnTokens(createMockTokens());

      expect(result).toBeDefined();
      expect(result.rounds).toBe(2); // Default rounds
      expect(result.consensus).toBeDefined();
      expect(result.improvements).toBeDefined();
      expect(result.auditTrail).toBeDefined();
      expect(result.timestamp).toBeDefined();
    });

    it('should respect custom rounds option', async () => {
      const result = await runDebateOnTokens(createMockTokens(), { rounds: 3 });

      expect(result.rounds).toBe(3);
    });

    it('should respect custom consensus threshold', async () => {
      const result = await runDebateOnTokens(createMockTokens(), {
        consensusThreshold: 0.8,
      });

      // All consensus items should meet the threshold
      for (const item of result.consensus) {
        expect(item.agreement).toBeGreaterThanOrEqual(0.8);
      }
    });

    it('should filter improvements by minConfidence', async () => {
      const result = await runDebateOnTokens(createMockTokens(), {
        minConfidence: 0.9,
      });

      // All improvements should meet the confidence threshold
      for (const improvement of result.improvements) {
        expect(improvement.confidence).toBeGreaterThanOrEqual(0.9);
      }
    });

    it('should handle empty token list', async () => {
      const result = await runDebateOnTokens([]);

      expect(result).toBeDefined();
      // Mock implementation still generates consensus/improvements
      // This would be empty in real implementation with no tokens to analyze
      expect(result.consensus).toBeDefined();
      expect(result.improvements).toBeDefined();
    });

    it('should generate consensus items', async () => {
      const result = await runDebateOnTokens(createMockTokens());

      expect(result.consensus).toBeDefined();
      expect(Array.isArray(result.consensus)).toBe(true);

      if (result.consensus.length > 0) {
        const consensusItem = result.consensus[0];
        expect(consensusItem).toHaveProperty('topic');
        expect(consensusItem).toHaveProperty('agreement');
        expect(consensusItem).toHaveProperty('recommendation');
        expect(consensusItem).toHaveProperty('providers');
        expect(consensusItem.agreement).toBeGreaterThanOrEqual(0);
        expect(consensusItem.agreement).toBeLessThanOrEqual(1);
      }
    });

    it('should generate improvement suggestions', async () => {
      const result = await runDebateOnTokens(createMockTokens());

      expect(result.improvements).toBeDefined();
      expect(Array.isArray(result.improvements)).toBe(true);

      if (result.improvements.length > 0) {
        const improvement = result.improvements[0];
        expect(improvement).toHaveProperty('tokenName');
        expect(improvement).toHaveProperty('path');
        expect(improvement).toHaveProperty('oldValue');
        expect(improvement).toHaveProperty('newValue');
        expect(improvement).toHaveProperty('reason');
        expect(improvement).toHaveProperty('confidence');
        expect(improvement).toHaveProperty('approvedBy');
      }
    });

    it('should generate audit trail', async () => {
      const result = await runDebateOnTokens(createMockTokens());

      expect(result.auditTrail).toBeDefined();
      expect(typeof result.auditTrail).toBe('string');
      expect(result.auditTrail.length).toBeGreaterThan(0);
      expect(result.auditTrail).toContain('Round');
    });

    it('should include timestamp in ISO format', async () => {
      const result = await runDebateOnTokens(createMockTokens());

      expect(result.timestamp).toBeDefined();
      expect(() => new Date(result.timestamp)).not.toThrow();
      expect(new Date(result.timestamp).toISOString()).toBe(result.timestamp);
    });
  });

  describe('applyDebateImprovements', () => {
    it('should apply improvements to tokens', () => {
      const debateResult: DebateResult = {
        rounds: 2,
        consensus: [],
        improvements: [
          {
            tokenName: 'primary-500',
            path: ['colors', 'primary', '500'],
            oldValue: '#3b82f6',
            newValue: '#3b82f6',
            reason: 'Add accessibility metadata',
            confidence: 0.9,
            approvedBy: ['synthesizer'],
          },
        ],
        auditTrail: 'Test audit trail',
        timestamp: new Date().toISOString(),
      };

      const improvedTokens = applyDebateImprovements(createMockTokens(), debateResult);

      expect(improvedTokens).toHaveLength(createMockTokens().length);

      const improvedToken = improvedTokens.find(t => t.name === 'primary-500');
      expect(improvedToken).toBeDefined();
      expect(improvedToken?.metadata?.debateImproved).toBe(true);
      expect(improvedToken?.metadata?.debateConfidence).toBe(0.9);
      expect(improvedToken?.metadata?.debateReason).toBe('Add accessibility metadata');
      expect(improvedToken?.metadata?.originalValue).toBe('#3b82f6');
    });

    it('should only apply high-confidence improvements', () => {
      const testTokens = createMockTokens();

      const debateResult: DebateResult = {
        rounds: 2,
        consensus: [],
        improvements: [
          {
            tokenName: 'primary-500',
            path: ['colors', 'primary', '500'],
            oldValue: '#3b82f6',
            newValue: '#4b92f6',
            reason: 'Low confidence change',
            confidence: 0.5, // Below 0.75 threshold
            approvedBy: ['synthesizer'],
          },
        ],
        auditTrail: 'Test audit trail',
        timestamp: new Date().toISOString(),
      };

      const improvedTokens = applyDebateImprovements(testTokens, debateResult);

      const token = improvedTokens.find(t => t.name === 'primary-500');
      expect(token?.metadata?.debateImproved).toBeUndefined();
    });

    it('should handle empty improvements list', () => {
      const testTokens = createMockTokens();

      const debateResult: DebateResult = {
        rounds: 2,
        consensus: [],
        improvements: [],
        auditTrail: 'Test audit trail',
        timestamp: new Date().toISOString(),
      };

      const improvedTokens = applyDebateImprovements(testTokens, debateResult);

      expect(improvedTokens).toHaveLength(testTokens.length);
      improvedTokens.forEach(token => {
        expect(token.metadata?.debateImproved).toBeUndefined();
      });
    });

    it('should preserve original token data', () => {
      const debateResult: DebateResult = {
        rounds: 2,
        consensus: [],
        improvements: [
          {
            tokenName: 'primary-500',
            path: ['colors', 'primary', '500'],
            oldValue: '#3b82f6',
            newValue: '#3b82f6',
            reason: 'Metadata update',
            confidence: 0.85,
            approvedBy: ['synthesizer'],
          },
        ],
        auditTrail: 'Test audit trail',
        timestamp: new Date().toISOString(),
      };

      const improvedTokens = applyDebateImprovements(createMockTokens(), debateResult);

      const token = improvedTokens.find(t => t.name === 'primary-500');
      expect(token?.name).toBe('primary-500');
      expect(token?.value).toBe('#3b82f6');
      expect(token?.type).toBe('color');
      expect(token?.source).toBe(TokenSource.TAILWIND_CONFIG);
    });
  });

  describe('generateAuditTrail', () => {
    it('should generate complete audit trail document', () => {
      const debateResult: DebateResult = {
        rounds: 2,
        consensus: [
          {
            topic: 'WCAG contrast validation needed',
            agreement: 0.9,
            recommendation: 'Run accessibility audit on all color tokens',
            providers: ['proposer', 'critic', 'synthesizer'],
          },
        ],
        improvements: [
          {
            tokenName: 'primary-500',
            path: ['colors', 'primary', '500'],
            oldValue: '#3b82f6',
            newValue: '#3b82f6',
            reason: 'Add accessibility metadata',
            confidence: 0.85,
            approvedBy: ['synthesizer'],
          },
        ],
        auditTrail: '## Round 1\nProposer analysis...\n## Round 2\nCritic response...',
        timestamp: '2026-02-01T12:00:00.000Z',
      };

      const auditTrail = generateAuditTrail(createMockTokens(), createMockTokens(), debateResult);

      // Should include header
      expect(auditTrail).toContain('# Debate Audit Trail');

      // Should include timestamp
      expect(auditTrail).toContain('**Timestamp**:');
      expect(auditTrail).toContain('2026-02-01T12:00:00.000Z');

      // Should include rounds
      expect(auditTrail).toContain('**Rounds**: 2');

      // Should include consensus count
      expect(auditTrail).toContain('**Total Consensus Items**: 1');

      // Should include improvements count (based on debateImproved metadata in improved tokens)
      expect(auditTrail).toContain('**Improvements Applied**:');

      // Should include debate summary
      expect(auditTrail).toContain('## Debate Summary');
      expect(auditTrail).toContain('Round 1');
      expect(auditTrail).toContain('Round 2');

      // Should include consensus section
      expect(auditTrail).toContain('## Consensus');
      expect(auditTrail).toContain('WCAG contrast validation needed');
      expect(auditTrail).toContain('90% agreement');

      // Should include footer
      expect(auditTrail).toContain('Generated by Claude Octopus Multi-AI Debate System');
    });

    it('should handle empty consensus', () => {
      const debateResult: DebateResult = {
        rounds: 1,
        consensus: [],
        improvements: [],
        auditTrail: 'Test trail',
        timestamp: new Date().toISOString(),
      };

      const auditTrail = generateAuditTrail(createMockTokens(), createMockTokens(), debateResult);

      expect(auditTrail).toContain('**Total Consensus Items**: 0');
    });

    it('should list applied changes', () => {
      const originalTokens = [...createMockTokens()];
      const improvedTokens = createMockTokens().map(t => ({
        ...t,
        metadata: {
          ...t.metadata,
          debateImproved: true,
          debateConfidence: 0.85,
          debateReason: 'Test improvement',
        },
      }));

      const debateResult: DebateResult = {
        rounds: 2,
        consensus: [],
        improvements: [],
        auditTrail: 'Test trail',
        timestamp: new Date().toISOString(),
      };

      const auditTrail = generateAuditTrail(originalTokens, improvedTokens, debateResult);

      expect(auditTrail).toContain('## Applied Changes');
      expect(auditTrail).toContain('primary-500');
      expect(auditTrail).toContain('spacing-4');
      expect(auditTrail).toContain('font-size-base');
      expect(auditTrail).toContain('Test improvement');
      expect(auditTrail).toContain('0.85');
    });
  });
});
