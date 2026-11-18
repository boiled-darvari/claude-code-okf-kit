#!/usr/bin/env node
// The one OKF gate entrypoint — npm-free by design (a bare `node` suffices):
//   okf check        (or: node <this folder>/check.mjs)
// Runs, in order: validate → check-links → check-refs → build-index --check.
// Fail-fast: exits with the first failing gate's code. Run it from the
// repository root, where okf.config.json lives.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig, CONFIG_FILE } from './config.mjs';

const CONFIG = loadConfig();
if (!fs.existsSync(CONFIG.docRoot)) {
  console.error(`okf gate: bundle root '${CONFIG.docRoot}' not found — run from the repository root (or fix docRoot in ${CONFIG_FILE}).`);
  process.exit(1);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const steps = [
  ['validate.mjs'],
  ['check-links.mjs'],
  ['check-refs.mjs'],
  ['build-index.mjs', '--check'],
];
for (const [script, ...args] of steps) {
  const r = spawnSync(process.execPath, [path.join(here, script), ...args], { stdio: 'inherit' });
  if (r.status !== 0) process.exit(r.status ?? 1);
}
