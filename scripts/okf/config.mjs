// The project's OKF manifest. Every gate loads it through here: okf.config.json
// in the directory the gate runs from (the repository root), or the file the
// OKF_CONFIG environment variable names. The file is DATA — it is parsed as
// JSON, never executed.
//
// The gates refuse to run until the manifest sets "template": false
// EXPLICITLY: an unconfigured docs gate that passes green on an empty bundle
// is worse than no gate at all. Every other field has a default below.
import fs from 'node:fs';
import path from 'node:path';

export const CONFIG_FILE = process.env.OKF_CONFIG || 'okf.config.json';

const DEFAULTS = {
  okfVersion: '0.1',
  // Bundle root, relative to the repository root.
  docRoot: 'doc',
  // Directory names skipped entirely (raw exports, image dumps, site output).
  skipDirs: [],
  // Files with NO frontmatter: generated indexes and logs.
  reservedFiles: ['index.md', 'log.md'],
  // Conventions doc at the bundle root; '' means the project has none.
  conventionsFile: 'okf-conventions.md',
  bundleTitle: 'Project Knowledge Bundle (OKF)',
  readmeStub: {
    enabled: true,
    title: 'Project Documentation',
    description: 'Entry point for the docs bundle; start at index.md.',
  },
  // Extensions the prose-reference checker treats as bundle files, and asset
  // extensions excluded from basename resolution.
  refExtensions: ['md', 'json', 'html'],
  assetExcludeExts: ['.png', '.jpg', '.jpeg', '.gif', '.svg'],
  // Frontmatter `status` that means "current".
  activeStatus: 'active',
  // Read by the Stop hook, not by the gates: what it does when the bundle is
  // implicated and node is not installed ("block" or "warn").
  onMissingNode: 'block',
  // Domain folders: name -> one-line description, in root-index order.
  folders: {},
  // Pinned "Rules & Invariants": docRoot-relative paths or unique basenames.
  rulesAndInvariants: [],
};

function refuse(msg) {
  console.error(`okf gate: ${msg}`);
  process.exit(1);
}

const isStr = (v) => typeof v === 'string';
const isStrList = (v) => Array.isArray(v) && v.every(isStr);
const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

export function loadConfig() {
  let raw;
  try {
    raw = fs.readFileSync(CONFIG_FILE, 'utf8');
  } catch {
    refuse(`no ${CONFIG_FILE} in ${process.cwd()} — run the gate from the repository root; create the config with /okf:init, or copy templates/okf.config.json from the plugin and edit it.`);
  }
  let given;
  try {
    given = JSON.parse(raw);
  } catch (e) {
    refuse(`${CONFIG_FILE} is not valid JSON (${e.message}).`);
  }
  if (!isObj(given)) refuse(`${CONFIG_FILE} must hold one JSON object.`);
  if (given.template !== false) {
    refuse(`${CONFIG_FILE} must set "template": false EXPLICITLY — it is still the shipped template, or the flag was removed/misspelled. Edit the config for this project first.`);
  }

  const c = { ...DEFAULTS, ...given };
  c.readmeStub = { ...DEFAULTS.readmeStub, ...(isObj(given.readmeStub) ? given.readmeStub : {}) };
  if (c.conventionsFile === null) c.conventionsFile = '';

  const bad = [];
  if (!isStr(c.docRoot) || c.docRoot.trim() === '') {
    bad.push('docRoot must be a non-empty string');
  } else {
    // The generator WRITES under docRoot, so it must stay inside the repo.
    const d = path.posix.normalize(c.docRoot.replace(/\\/g, '/')).replace(/\/+$/, '');
    if (d === '' || path.posix.isAbsolute(d) || /^[A-Za-z]:/.test(d) || d === '..' || d.startsWith('../')) {
      bad.push(`docRoot must be a path inside the repository (got: ${c.docRoot})`);
    } else {
      c.docRoot = d;
    }
  }
  for (const k of ['okfVersion', 'bundleTitle', 'activeStatus', 'conventionsFile']) {
    if (!isStr(c[k])) bad.push(`${k} must be a string`);
  }
  for (const k of ['skipDirs', 'reservedFiles', 'refExtensions', 'assetExcludeExts', 'rulesAndInvariants']) {
    if (!isStrList(c[k])) bad.push(`${k} must be a list of strings`);
  }
  if (isStrList(c.refExtensions) && c.refExtensions.length === 0) bad.push('refExtensions must list at least one extension');
  if (!isObj(c.folders) || !Object.values(c.folders).every(isStr)) bad.push('folders must map folder names to description strings');
  if (given.readmeStub !== undefined && !isObj(given.readmeStub)) bad.push('readmeStub must be an object');
  if (typeof c.readmeStub.enabled !== 'boolean') bad.push('readmeStub.enabled must be true or false');
  if (!isStr(c.readmeStub.title) || !isStr(c.readmeStub.description)) bad.push('readmeStub.title and readmeStub.description must be strings');
  if (c.onMissingNode !== 'block' && c.onMissingNode !== 'warn') bad.push('onMissingNode must be "block" or "warn"');
  if (bad.length) refuse(`${CONFIG_FILE} has ${bad.length} invalid field(s):\n  ` + bad.join('\n  '));

  // A misspelled key would otherwise be ignored in silence. Keys starting
  // with _ or $ are the project's own notes (JSON has no comments).
  for (const k of Object.keys(given)) {
    if (k === 'template' || k in DEFAULTS || k.startsWith('_') || k.startsWith('$')) continue;
    console.warn(`okf gate: note: unknown key "${k}" in ${CONFIG_FILE} (ignored)`);
  }
  return c;
}
