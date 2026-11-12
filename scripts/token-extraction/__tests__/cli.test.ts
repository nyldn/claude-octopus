import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

const packageRoot = path.resolve(__dirname, '..');
const resolve = createRequire(path.join(packageRoot, 'package.json'));
const runner = resolve.resolve('ts-node/dist/bin.js');
let fixture: string;

function runCLI(...args: string[]): string {
  return execFileSync(process.execPath, [runner, 'cli.ts', ...args], {
    cwd: packageRoot,
    encoding: 'utf8',
    timeout: 30_000,
    env: {
      ...Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('TS_NODE_'))),
      TS_NODE_PROJECT: path.join(packageRoot, 'tsconfig.json'),
      TS_NODE_TRANSPILE_ONLY: 'false',
    },
  });
}

describe('documented token-extraction CLI', () => {
  beforeEach(() => {
    fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'octopus-token-cli-'));
  });

  afterEach(() => {
    fs.rmSync(fixture, { recursive: true, force: true });
  });

  it('compiles the real entry point and prints help', () => {
    expect(runCLI('--help')).toContain('Token Extraction Pipeline CLI');
  }, 30_000);

  it('extracts CSS values into a JSON artifact', () => {
    const project = path.join(fixture, 'project');
    const output = path.join(project, 'output');
    fs.mkdirSync(project);
    fs.writeFileSync(path.join(project, 'styles.css'),
      ':root { --color-primary: #123456; --spacing-small: 4px; }');

    runCLI('--project', project, '--output', output,
      '--include-sources', 'css-variables', '--formats', 'json');

    const artifact = fs.readFileSync(path.join(output, 'tokens.json'), 'utf8');
    expect(() => JSON.parse(artifact)).not.toThrow();
    expect(artifact).toContain('#123456');
    expect(artifact).toContain('4px');
  }, 30_000);
});
