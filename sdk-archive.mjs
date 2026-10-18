import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

const normalize = (text) => text.replace(/\r\n/g, '\n');

// Apply the repository's text-only unified patch, with exact context and no fuzz.
export function applyPatch(root, patch) {
  const lines = normalize(patch).replace(/\n$/, '').split('\n');
  const writes = [];
  let i = 0;
  while (i < lines.length) {
    if (!lines[i].startsWith('--- a/')) throw new Error('Unsupported patch header');
    const name = lines[i++].slice(6);
    if (lines[i++] !== `+++ b/${name}`) throw new Error('Renamed files are not supported');
    const path = resolve(root, name);
    if (!path.startsWith(resolve(root) + sep)) throw new Error('Patch path escapes SDK');
    const original = normalize(readFileSync(path, 'utf8')).split('\n');
    const output = [];
    let cursor = 0;
    while (i < lines.length && lines[i].startsWith('@@')) {
      const hunk = /^@@ -(\d+),(\d+) \+(\d+),(\d+) @@$/.exec(lines[i++]);
      if (!hunk) throw new Error('Unsupported patch hunk');
      const start = Number(hunk[1]) - 1;
      if (start < cursor || start > original.length) throw new Error('Invalid patch offset');
      output.push(...original.slice(cursor, start));
      cursor = start;
      if (output.length !== Number(hunk[3]) - 1) throw new Error('Invalid output offset');
      let removed = 0, added = 0;
      while (i < lines.length && !lines[i].startsWith('@@') && !lines[i].startsWith('--- a/')) {
        const line = lines[i++];
        const kind = line[0], text = line.slice(1);
        if (![' ', '+', '-'].includes(kind)) throw new Error('Unsupported patch line');
        if (kind !== '+') {
          if (original[cursor++] !== text) throw new Error(`Patch context mismatch: ${name}`);
          removed++;
        }
        if (kind !== '-') { output.push(text); added++; }
      }
      if (removed !== Number(hunk[2]) || added !== Number(hunk[4])) throw new Error('Invalid patch hunk counts');
    }
    output.push(...original.slice(cursor));
    writes.push([path, output.join('\n')]);
  }
  // Validate every file before writing any of them.
  for (const [path, text] of writes) writeFileSync(path, text);
}

export function verifyExisting(source, existing) {
  for (const entry of readdirSync(source, { withFileTypes: true })) {
    const expected = resolve(source, entry.name), actual = resolve(existing, entry.name);
    if (entry.isDirectory()) { verifyExisting(expected, actual); continue; }
    const a = readFileSync(expected), b = readFileSync(actual);
    if (a.equals(b)) continue;
    // Existing Windows Git checkouts may have CRLF text; binary files stay exact.
    const text = a.toString('utf8');
    if (!a.includes(0) && Buffer.from(text).equals(a) && normalize(text) === normalize(b.toString('utf8'))) continue;
    throw new Error(`SDK source differs: ${actual}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const [action, source, target] = process.argv.slice(2);
    if (action === 'patch') applyPatch(source, readFileSync(target, 'utf8'));
    else if (action === 'verify') verifyExisting(source, target);
    else throw new Error('Expected patch or verify');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
