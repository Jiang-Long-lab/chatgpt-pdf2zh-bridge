import { isAbsolute, join, resolve } from 'node:path';

export function resolveDataDir(root, configured = process.env.ZOTERO_CHATGPT_DATA_DIR) {
  const value = configured || join(root, '.local-data');
  if (!isAbsolute(value)) throw new Error('ZOTERO_CHATGPT_DATA_DIR must be an absolute path.');
  return resolve(value);
}
