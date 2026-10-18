import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { resolveDataDir } from './data-dir.mjs';

test('default stays beside the installation, independently of AppData virtualization', () => {
  const root = resolve('test-install');
  assert.equal(resolveDataDir(root, ''), resolve(root, '.local-data'));
});
test('explicit absolute directory wins and relative paths fail closed', () => {
  const root = resolve('test-install');
  const fixed = resolve('shared-data');
  assert.equal(resolveDataDir(root, fixed), fixed);
  assert.throws(() => resolveDataDir(root, 'relative-data'), /absolute path/);
});
