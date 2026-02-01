/**
 * Feature Detector Tests
 * Verify feature detection heuristics and scope creation
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { FeatureDetector } from '../../extractors/feature-detector';
import * as fs from 'fs/promises';
import * as path from 'path';

// Mock fs module
vi.mock('fs/promises');

describe('FeatureDetector', () => {
  const mockProjectRoot = '/test/project';
  let detector: FeatureDetector;

  beforeEach(() => {
    vi.clearAllMocks();
    detector = new FeatureDetector(mockProjectRoot);
  });

  describe('detectFeatures', () => {
    it('should detect features from directory structure', async () => {
      // Mock directory structure
      vi.mocked(fs.readdir).mockImplementation(async (dirPath: any) => {
        const dir = dirPath.toString();
        if (dir.includes('features')) {
          return [
            { name: 'authentication', isDirectory: () => true },
            { name: 'payment', isDirectory: () => true },
            { name: 'user-profile', isDirectory: () => true },
          ] as any;
        }
        return [] as any;
      });

      vi.mocked(fs.access).mockResolvedValue(undefined);

      // Mock file scanning
      const scanFilesSpy = vi.spyOn(detector as any, 'scanFiles');
      scanFilesSpy.mockResolvedValue(undefined);

      // Set up allFiles with feature files
      (detector as any).allFiles = [
        'features/authentication/login.ts',
        'features/authentication/logout.ts',
        'features/authentication/session.ts',
        'features/payment/checkout.ts',
        'features/payment/billing.ts',
        'features/user-profile/settings.ts',
      ];

      const result = await detector.detectFeatures();

      expect(result.features.length).toBeGreaterThan(0);
      expect(result.metadata.totalFiles).toBe(6);
      expect(result.metadata.detectionMethod).toBe('hybrid');
    });

    it('should detect features from keywords', async () => {
      vi.mocked(fs.access).mockRejectedValue(new Error('not found'));

      const scanFilesSpy = vi.spyOn(detector as any, 'scanFiles');
      scanFilesSpy.mockResolvedValue(undefined);

      // Set up allFiles with keyword-based files
      (detector as any).allFiles = [
        'src/auth/login.ts',
        'src/auth/logout.ts',
        'src/auth/session.ts',
        'src/auth/signup.ts',
        'src/payment/checkout.ts',
        'src/payment/stripe.ts',
        'src/payment/paypal.ts',
      ];

      const result = await detector.detectFeatures();

      // Should detect auth and payment features via keywords
      const authFeature = result.features.find(f => f.name.toLowerCase().includes('auth'));
      const paymentFeature = result.features.find(f => f.name.toLowerCase().includes('payment'));

      expect(authFeature).toBeDefined();
      expect(paymentFeature).toBeDefined();
      expect(authFeature?.fileCount).toBeGreaterThanOrEqual(4);
      expect(paymentFeature?.fileCount).toBeGreaterThanOrEqual(3);
    });

    it('should merge overlapping features', async () => {
      vi.mocked(fs.readdir).mockResolvedValue([
        { name: 'auth', isDirectory: () => true },
      ] as any);

      vi.mocked(fs.access).mockResolvedValue(undefined);

      const scanFilesSpy = vi.spyOn(detector as any, 'scanFiles');
      scanFilesSpy.mockResolvedValue(undefined);

      // Set up files that match both directory and keyword patterns
      (detector as any).allFiles = [
        'features/auth/login.ts',
        'features/auth/logout.ts',
        'features/auth/session.ts',
        'features/auth/signup.ts',
      ];

      const result = await detector.detectFeatures();

      // Should merge directory-based and keyword-based features
      const authFeatures = result.features.filter(f =>
        f.name.toLowerCase().includes('auth')
      );

      // Should be merged into single feature
      expect(authFeatures.length).toBeLessThanOrEqual(1);
    });

    it('should track unassigned files', async () => {
      vi.mocked(fs.access).mockRejectedValue(new Error('not found'));

      const scanFilesSpy = vi.spyOn(detector as any, 'scanFiles');
      scanFilesSpy.mockResolvedValue(undefined);

      (detector as any).allFiles = [
        'src/auth/login.ts',
        'src/auth/logout.ts',
        'src/utils/helpers.ts',
        'src/config.ts',
        'src/index.ts',
      ];

      const result = await detector.detectFeatures();

      // Should have unassigned files (utils, config, index)
      expect(result.unassignedFiles.length).toBeGreaterThan(0);
      expect(result.unassignedFiles).toContain('src/utils/helpers.ts');
    });

    it('should respect minFilesPerFeature option', async () => {
      const detectorWithMin = new FeatureDetector(mockProjectRoot, {
        minFilesPerFeature: 5,
      });

      vi.mocked(fs.access).mockRejectedValue(new Error('not found'));

      const scanFilesSpy = vi.spyOn(detectorWithMin as any, 'scanFiles');
      scanFilesSpy.mockResolvedValue(undefined);

      // Only 3 auth files - below threshold
      (detectorWithMin as any).allFiles = [
        'src/auth/login.ts',
        'src/auth/logout.ts',
        'src/auth/session.ts',
      ];

      const result = await detectorWithMin.detectFeatures();

      // Should not detect auth feature (below threshold)
      const authFeature = result.features.find(f => f.name.toLowerCase().includes('auth'));
      expect(authFeature).toBeUndefined();
    });

    it('should calculate confidence scores', async () => {
      vi.mocked(fs.readdir).mockResolvedValue([
        { name: 'auth', isDirectory: () => true },
      ] as any);

      vi.mocked(fs.access).mockResolvedValue(undefined);

      const scanFilesSpy = vi.spyOn(detector as any, 'scanFiles');
      scanFilesSpy.mockResolvedValue(undefined);

      (detector as any).allFiles = [
        'features/auth/login.ts',
        'features/auth/logout.ts',
        'features/auth/session.ts',
      ];

      const result = await detector.detectFeatures();

      // Directory-based detection should have high confidence
      const authFeature = result.features.find(f => f.name.toLowerCase().includes('auth'));
      expect(authFeature?.confidence).toBeGreaterThanOrEqual(0.7);
    });
  });

  describe('createScope', () => {
    it('should create scope for known feature', async () => {
      const scanFilesSpy = vi.spyOn(detector as any, 'scanFiles');
      scanFilesSpy.mockResolvedValue(undefined);

      vi.mocked(fs.readdir).mockResolvedValue([
        { name: 'authentication', isDirectory: () => true },
      ] as any);

      vi.mocked(fs.access).mockResolvedValue(undefined);

      (detector as any).allFiles = [
        'features/authentication/login.ts',
        'features/authentication/logout.ts',
        'features/authentication/session.ts',
      ];

      const scope = await detector.createScope('authentication');

      expect(scope.name).toBe('authentication');
      expect(scope.includePaths.length).toBeGreaterThan(0);
    });

    it('should create keyword-based scope for unknown feature', async () => {
      const scanFilesSpy = vi.spyOn(detector as any, 'scanFiles');
      scanFilesSpy.mockResolvedValue(undefined);

      vi.mocked(fs.access).mockRejectedValue(new Error('not found'));

      (detector as any).allFiles = [
        'src/custom-feature/file1.ts',
        'src/custom-feature/file2.ts',
      ];

      const scope = await detector.createScope('custom-feature');

      expect(scope.name).toBe('custom-feature');
      expect(scope.keywords).toContain('custom-feature');
      expect(scope.includePaths.length).toBeGreaterThan(0);
    });

    it('should find keywords for feature name', async () => {
      const keywords = (detector as any).findKeywordsForFeature('authentication');

      // Should match known authentication keywords
      expect(keywords).toBeDefined();
      expect(keywords.length).toBeGreaterThan(0);
      expect(keywords.some((k: string) => k.includes('auth'))).toBe(true);
    });
  });

  describe('file scanning', () => {
    it('should skip node_modules and build artifacts', async () => {
      const shouldSkip = (detector as any).shouldSkip.bind(detector);

      expect(shouldSkip('node_modules/package/file.ts')).toBe(true);
      expect(shouldSkip('.git/objects/file')).toBe(true);
      expect(shouldSkip('dist/bundle.js')).toBe(true);
      expect(shouldSkip('build/output.js')).toBe(true);
      expect(shouldSkip('coverage/report.html')).toBe(true);

      expect(shouldSkip('src/features/auth.ts')).toBe(false);
    });

    it('should filter relevant file types', async () => {
      const isRelevant = (detector as any).isRelevantFile.bind(detector);

      expect(isRelevant('component.tsx')).toBe(true);
      expect(isRelevant('styles.css')).toBe(true);
      expect(isRelevant('config.json')).toBe(true);
      expect(isRelevant('component.vue')).toBe(true);

      expect(isRelevant('README.md')).toBe(false);
      expect(isRelevant('image.png')).toBe(false);
      expect(isRelevant('binary.exe')).toBe(false);
    });
  });

  describe('feature formatting', () => {
    it('should format feature names properly', async () => {
      const format = (detector as any).formatFeatureName.bind(detector);

      expect(format('user-profile')).toBe('User Profile');
      expect(format('authentication')).toBe('Authentication');
      expect(format('api_endpoints')).toBe('Api Endpoints');
      expect(format('PAYMENT_SYSTEM')).toBe('PAYMENT SYSTEM'); // Doesn't lowercase
    });
  });

  describe('findFilesByKeywords', () => {
    it('should find files matching keywords', async () => {
      (detector as any).allFiles = [
        'src/auth/login.ts',
        'src/auth/logout.ts',
        'src/payment/checkout.ts',
        'src/user/profile.ts',
      ];

      const authFiles = (detector as any).findFilesByKeywords(['auth', 'login']);

      expect(authFiles.length).toBe(2);
      expect(authFiles).toContain('src/auth/login.ts');
      expect(authFiles).toContain('src/auth/logout.ts');
    });

    it('should be case-insensitive', async () => {
      (detector as any).allFiles = [
        'src/AUTH/Login.ts',
        'src/Payment/Checkout.ts',
      ];

      const authFiles = (detector as any).findFilesByKeywords(['auth']);

      expect(authFiles.length).toBe(1);
      expect(authFiles).toContain('src/AUTH/Login.ts');
    });
  });
});
