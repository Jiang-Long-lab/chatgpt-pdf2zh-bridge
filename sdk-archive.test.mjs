import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { applyPatch, verifyExisting } from './sdk-archive.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'bridge-sdk-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
}
const change = (name) => `--- a/${name}\n+++ b/${name}\n@@ -1,2 +1,3 @@\n-old\n+new\n+added\n \n`;

test('patch preserves blank context lines and supports CRLF input', (t) => {
  const root = fixture(t);
  writeFileSync(join(root, 'file.txt'), 'old\r\n\r\n');
  applyPatch(root, change('file.txt').replaceAll('\n', '\r\n'));
  assert.equal(readFileSync(join(root, 'file.txt'), 'utf8'), 'new\nadded\n\n');
});

test('a later context mismatch leaves every source file unchanged', (t) => {
  const root = fixture(t);
  writeFileSync(join(root, 'a.txt'), 'old\n\n');
  writeFileSync(join(root, 'b.txt'), 'custom\n\n');
  assert.throws(() => applyPatch(root, change('a.txt') + change('b.txt')), /context mismatch/);
  assert.equal(readFileSync(join(root, 'a.txt'), 'utf8'), 'old\n\n');
  assert.equal(readFileSync(join(root, 'b.txt'), 'utf8'), 'custom\n\n');
  assert.throws(() => applyPatch(root, change('../outside.txt')), /escapes SDK/);
});

test('repeat installation accepts CRLF and build outputs but rejects missing or changed source', (t) => {
  const root = fixture(t), source = join(root, 'source'), existing = join(root, 'existing');
  mkdirSync(source); mkdirSync(existing);
  writeFileSync(join(source, 'a.txt'), 'source\n');
  assert.throws(() => verifyExisting(source, existing), /ENOENT/);
  writeFileSync(join(existing, 'a.txt'), 'source\r\n');
  mkdirSync(join(existing, 'node_modules'));
  verifyExisting(source, existing);
  writeFileSync(join(existing, 'a.txt'), 'custom\n');
  assert.throws(() => verifyExisting(source, existing), /source differs/);
  assert.equal(readFileSync(join(existing, 'a.txt'), 'utf8'), 'custom\n');
});
