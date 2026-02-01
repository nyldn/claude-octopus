/**
 * Feature Detector
 * Automatically detects features in codebases using multiple heuristics
 */

import * as path from 'path';
import * as fs from 'fs/promises';
import { Feature, FeatureScope, FeatureDetectionResult } from '../types';

export interface FeatureDetectorOptions {
  minFilesPerFeature?: number;
  confidenceThreshold?: number;
  enableDirectoryDetection?: boolean;
  enableKeywordDetection?: boolean;
  enableImportClustering?: boolean;
}

const DEFAULT_OPTIONS: Required<FeatureDetectorOptions> = {
  minFilesPerFeature: 3,
  confidenceThreshold: 0.5,
  enableDirectoryDetection: true,
  enableKeywordDetection: true,
  enableImportClustering: false, // Disabled by default (more complex)
};

/**
 * Common feature keywords and their patterns
 */
const FEATURE_KEYWORDS = {
  authentication: ['auth', 'login', 'logout', 'session', 'signin', 'signup'],
  payment: ['payment', 'checkout', 'billing', 'invoice', 'stripe', 'paypal'],
  user: ['user', 'profile', 'account', 'settings'],
  product: ['product', 'catalog', 'item', 'inventory'],
  order: ['order', 'cart', 'basket', 'shopping'],
  analytics: ['analytics', 'tracking', 'metrics', 'stats'],
  notification: ['notification', 'alert', 'email', 'sms'],
  admin: ['admin', 'dashboard', 'management'],
  search: ['search', 'filter', 'query'],
  api: ['api', 'endpoint', 'route', 'controller'],
};

/**
 * Feature directory patterns
 */
const FEATURE_DIRECTORIES = [
  'features',
  'modules',
  'services',
  'domains',
  'apps',
  'packages',
];

export class FeatureDetector {
  private projectRoot: string;
  private options: Required<FeatureDetectorOptions>;
  private allFiles: string[] = [];

  constructor(projectRoot: string, options: FeatureDetectorOptions = {}) {
    this.projectRoot = projectRoot;
    this.options = { ...DEFAULT_OPTIONS, ...options };
  }

  /**
   * Detect all features in the codebase
   */
  async detectFeatures(): Promise<FeatureDetectionResult> {
    console.log('Detecting features in codebase...');

    // Scan all files
    await this.scanFiles();

    const features: Feature[] = [];
    let detectionMethod: FeatureDetectionResult['metadata']['detectionMethod'] = 'hybrid';

    // Method 1: Directory-based detection
    if (this.options.enableDirectoryDetection) {
      const dirFeatures = await this.detectByDirectory();
      features.push(...dirFeatures);
      if (dirFeatures.length > 0) {
        console.log(`  Found ${dirFeatures.length} features via directory structure`);
      }
    }

    // Method 2: Keyword-based detection
    if (this.options.enableKeywordDetection) {
      const keywordFeatures = await this.detectByKeywords();
      features.push(...keywordFeatures);
      if (keywordFeatures.length > 0) {
        console.log(`  Found ${keywordFeatures.length} features via keywords`);
      }
    }

    // Method 3: Import clustering (future)
    if (this.options.enableImportClustering) {
      // TODO: Implement import-based clustering
      detectionMethod = 'import-clustering';
    }

    // Filter by confidence and merge duplicates
    const filteredFeatures = this.filterAndMergeFeatures(features);

    // Find unassigned files
    const assignedFiles = new Set<string>();
    for (const feature of filteredFeatures) {
      feature.paths.forEach(p => assignedFiles.add(p));
    }
    const unassignedFiles = this.allFiles.filter(f => !assignedFiles.has(f));

    console.log(`  Total features detected: ${filteredFeatures.length}`);
    console.log(`  Unassigned files: ${unassignedFiles.length}`);
    console.log('');

    return {
      features: filteredFeatures,
      unassignedFiles,
      metadata: {
        totalFiles: this.allFiles.length,
        totalFeatures: filteredFeatures.length,
        detectionMethod,
        timestamp: new Date().toISOString(),
      },
    };
  }

  /**
   * Create a scope for a specific feature name
   */
  async createScope(featureName: string): Promise<FeatureScope> {
    console.log(`Creating scope for feature: ${featureName}`);

    // Scan files if not already done
    if (this.allFiles.length === 0) {
      await this.scanFiles();
    }

    // Try to find feature by name in detected features
    const detection = await this.detectFeatures();
    const existingFeature = detection.features.find(
      f => f.name.toLowerCase() === featureName.toLowerCase()
    );

    if (existingFeature && existingFeature.scope) {
      console.log(`  Using detected scope with ${existingFeature.fileCount} files`);
      return existingFeature.scope;
    }

    // If not found, create a keyword-based scope
    const keywords = this.findKeywordsForFeature(featureName);
    const matchingFiles = this.findFilesByKeywords(keywords);

    console.log(`  Created scope with ${matchingFiles.length} files based on keywords`);

    return {
      name: featureName,
      includePaths: matchingFiles,
      keywords,
    };
  }

  /**
   * Scan project directory for all relevant files
   */
  private async scanFiles(): Promise<void> {
    const files: string[] = [];

    const scanDir = async (dir: string): Promise<void> => {
      const entries = await fs.readdir(dir, { withFileTypes: true });

      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        const relativePath = path.relative(this.projectRoot, fullPath);

        // Skip node_modules, .git, build artifacts
        if (this.shouldSkip(relativePath)) {
          continue;
        }

        if (entry.isDirectory()) {
          await scanDir(fullPath);
        } else if (this.isRelevantFile(entry.name)) {
          files.push(relativePath);
        }
      }
    };

    try {
      await scanDir(this.projectRoot);
      this.allFiles = files;
    } catch (error) {
      console.error('Error scanning files:', error);
      this.allFiles = [];
    }
  }

  /**
   * Detect features based on directory structure
   */
  private async detectByDirectory(): Promise<Feature[]> {
    const features: Feature[] = [];

    for (const featureDir of FEATURE_DIRECTORIES) {
      const featureDirPath = path.join(this.projectRoot, featureDir);

      try {
        await fs.access(featureDirPath);
        const subdirs = await fs.readdir(featureDirPath, { withFileTypes: true });

        for (const subdir of subdirs) {
          if (!subdir.isDirectory()) continue;

          const featureName = this.formatFeatureName(subdir.name);
          const featurePath = path.join(featureDir, subdir.name);
          const files = this.allFiles.filter(f => f.startsWith(featurePath));

          if (files.length >= this.options.minFilesPerFeature) {
            features.push({
              name: featureName,
              description: `Feature detected from ${featureDir}/${subdir.name}`,
              fileCount: files.length,
              tokenCount: 0, // Will be filled during extraction
              paths: files,
              scope: {
                name: featureName,
                includePaths: [`${featurePath}/**/*`],
              },
              confidence: 0.9, // High confidence for directory-based
            });
          }
        }
      } catch {
        // Directory doesn't exist, skip
        continue;
      }
    }

    return features;
  }

  /**
   * Detect features based on file/directory name keywords
   */
  private async detectByKeywords(): Promise<Feature[]> {
    const features: Feature[] = [];

    for (const [featureName, keywords] of Object.entries(FEATURE_KEYWORDS)) {
      const matchingFiles = this.findFilesByKeywords(keywords);

      if (matchingFiles.length >= this.options.minFilesPerFeature) {
        features.push({
          name: this.formatFeatureName(featureName),
          description: `Feature detected via keywords: ${keywords.join(', ')}`,
          fileCount: matchingFiles.length,
          tokenCount: 0,
          paths: matchingFiles,
          scope: {
            name: featureName,
            includePaths: matchingFiles,
            keywords,
          },
          confidence: 0.7, // Medium confidence for keyword-based
        });
      }
    }

    return features;
  }

  /**
   * Find files matching any of the keywords
   */
  private findFilesByKeywords(keywords: string[]): string[] {
    return this.allFiles.filter(file => {
      const lowerFile = file.toLowerCase();
      return keywords.some(keyword => lowerFile.includes(keyword.toLowerCase()));
    });
  }

  /**
   * Find keywords that match a feature name
   */
  private findKeywordsForFeature(featureName: string): string[] {
    const lowerName = featureName.toLowerCase();

    // Check if feature name matches known patterns
    for (const [category, keywords] of Object.entries(FEATURE_KEYWORDS)) {
      if (lowerName.includes(category) || keywords.some(k => lowerName.includes(k))) {
        return keywords;
      }
    }

    // If no match, use the feature name itself as keyword
    return [lowerName];
  }

  /**
   * Filter features by confidence and merge duplicates
   */
  private filterAndMergeFeatures(features: Feature[]): Feature[] {
    // Filter by confidence threshold
    let filtered = features.filter(
      f => (f.confidence ?? 1) >= this.options.confidenceThreshold
    );

    // Merge features with overlapping files
    const merged: Feature[] = [];
    const processed = new Set<number>();

    for (let i = 0; i < filtered.length; i++) {
      if (processed.has(i)) continue;

      const feature = filtered[i];
      const featureFiles = new Set(feature.paths);

      // Find overlapping features
      for (let j = i + 1; j < filtered.length; j++) {
        if (processed.has(j)) continue;

        const other = filtered[j];
        const overlapCount = other.paths.filter(p => featureFiles.has(p)).length;
        const overlapRatio = overlapCount / Math.min(feature.paths.length, other.paths.length);

        // If >50% overlap, merge
        if (overlapRatio > 0.5) {
          feature.paths = [...new Set([...feature.paths, ...other.paths])];
          feature.fileCount = feature.paths.length;
          feature.confidence = Math.max(feature.confidence ?? 0, other.confidence ?? 0);
          processed.add(j);
        }
      }

      merged.push(feature);
      processed.add(i);
    }

    return merged.sort((a, b) => b.fileCount - a.fileCount);
  }

  /**
   * Format feature name for display
   */
  private formatFeatureName(name: string): string {
    return name
      .split(/[-_]/)
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  }

  /**
   * Check if file should be skipped
   */
  private shouldSkip(relativePath: string): boolean {
    const skipPatterns = [
      'node_modules',
      '.git',
      '.next',
      'dist',
      'build',
      'out',
      'coverage',
      '.cache',
      '__pycache__',
      'vendor',
    ];

    return skipPatterns.some(pattern => relativePath.includes(pattern));
  }

  /**
   * Check if file is relevant for token extraction
   */
  private isRelevantFile(filename: string): boolean {
    const relevantExtensions = [
      '.js',
      '.jsx',
      '.ts',
      '.tsx',
      '.css',
      '.scss',
      '.sass',
      '.less',
      '.json',
      '.vue',
      '.svelte',
    ];

    return relevantExtensions.some(ext => filename.endsWith(ext));
  }
}
