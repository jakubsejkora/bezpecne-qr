#!/usr/bin/env node
// Builds the native UI strings for BQUI from the prototype (single source of design copy).
//   node scripts/gen-ui-strings.mjs           write ios/Packages/BQUI/Sources/BQUI/Resources/ui-strings.json
//   node scripts/gen-ui-strings.mjs --check   exit 1 if the committed file is out of date
//
// Input:  prototype/js/i18n.js (assigns window.BQ.strings = {cs:{…}, en:{…}}; evaluated with a fake window)
//       + ios/Packages/BQUI/Sources/BQUI/Resources/ios-strings.overlay.json (iOS-only strings and the few
//         prototype strings the native app must word differently, e.g. toasts that say "simulated").
// Output: {cs:{key:…}, en:{key:…}} with sorted keys. Placeholders use {name}, as in the prototype.
// Fails when a key is missing in one language or the {placeholders} of cs and en differ.

import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import vm from 'node:vm';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const resources = path.join(root, 'ios/Packages/BQUI/Sources/BQUI/Resources');
const sourcePath = path.join(root, 'prototype/js/i18n.js');
const overlayPath = path.join(resources, 'ios-strings.overlay.json');
const outPath = path.join(resources, 'ui-strings.json');
const check = process.argv.includes('--check');

// Prototype-only groups: the review tooling around the phone (catalogue, controls) and simulated system UI.
const EXCLUDED_PREFIXES = ['catalog.', 'group.', 'ctl.', 'picker.', 'safari.'];
const LANGS = ['cs', 'en'];

// 1. Evaluate i18n.js. It refers to both `window.BQ` and the global `BQ`, so the fake window is the global.
const sandbox = {};
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(await readFile(sourcePath, 'utf8'), sandbox, { filename: 'prototype/js/i18n.js' });
const prototype = sandbox.BQ?.strings;
if (!prototype || !LANGS.every((l) => prototype[l])) {
  console.error('prototype/js/i18n.js did not define BQ.strings.cs and BQ.strings.en');
  process.exit(1);
}

// 2. Merge the overlay.
const overlay = JSON.parse(await readFile(overlayPath, 'utf8'));
const errors = [];
const out = {};
const overridden = new Set();
for (const lang of LANGS) {
  const table = {};
  for (const [key, value] of Object.entries(prototype[lang])) {
    if (EXCLUDED_PREFIXES.some((p) => key.startsWith(p))) continue;
    table[key] = value;
  }
  for (const [key, value] of Object.entries(overlay[lang] || {})) {
    if (typeof value !== 'string') { errors.push(`overlay ${lang}.${key} is not a string`); continue; }
    if (key in table && table[key] !== value) overridden.add(key);
    table[key] = value;
  }
  out[lang] = table;
}

// 3. Validate: same keys in both languages, same placeholders, no empty strings.
const placeholders = (s) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(',');
const keys = new Set(LANGS.flatMap((l) => Object.keys(out[l])));
for (const key of keys) {
  for (const lang of LANGS) {
    if (!(key in out[lang])) errors.push(`missing ${lang}.${key}`);
    else if (!out[lang][key].trim()) errors.push(`empty ${lang}.${key}`);
  }
  if (key in out.cs && key in out.en && placeholders(out.cs[key]) !== placeholders(out.en[key])) {
    errors.push(`placeholders differ for ${key}: cs {${placeholders(out.cs[key])}} vs en {${placeholders(out.en[key])}}`);
  }
}
if (errors.length) {
  console.error(errors.map((e) => `✗ ${e}`).join('\n'));
  process.exit(1);
}

// 4. Write (sorted, stable).
const sorted = (o) => Object.fromEntries(Object.keys(o).sort().map((k) => [k, o[k]]));
const json = JSON.stringify({
  _generated: 'scripts/gen-ui-strings.mjs from prototype/js/i18n.js + ios-strings.overlay.json — do not edit',
  cs: sorted(out.cs),
  en: sorted(out.en),
}, null, 2) + '\n';

const current = await readFile(outPath, 'utf8').catch(() => '');
if (check) {
  if (current !== json) {
    console.error('ui-strings.json is out of date — run: node scripts/gen-ui-strings.mjs');
    process.exit(1);
  }
  console.log(`ui-strings.json is up to date (${keys.size} keys).`);
} else {
  if (current !== json) await writeFile(outPath, json);
  const fromOverlay = LANGS.map((l) => Object.keys(overlay[l] || {}).length);
  console.log(`Wrote ${path.relative(root, outPath)}: ${keys.size} keys (${fromOverlay[0]} from the iOS overlay).`);
  if (overridden.size) console.log(`Overlay rewords ${overridden.size} prototype string(s): ${[...overridden].sort().join(', ')}`);
}
