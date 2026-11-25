'use strict';
// Mod categories: the user's own groups ("Survival", ...) for enabling many mods at once. Stored next to the other launcher records in
// <data>/mods/.launcher-categories.json: { list: [user category names], assign: { mod: category } }.
// Built-in groups (not deletable): OURS = mods installed from the project repo or by Sync, OTHER = everything else.
const fs = require('fs');
const path = require('path');
const { loadRecords } = require('./records');

const FILE = '.launcher-categories.json';
const OURS = 'Luanti Mods'; // placeholder name until the project gets its own
const OTHER = 'Other';
const NAME_RE = /^[^\x00-\x1f]{1,40}$/;

function load(dataDir) {
  try {
    const j = JSON.parse(fs.readFileSync(path.join(dataDir, 'mods', FILE), 'utf8'));
    return { list: Array.isArray(j.list) ? j.list.filter((n) => typeof n === 'string') : [], assign: j.assign && typeof j.assign === 'object' ? j.assign : {} };
  } catch { return { list: [], assign: {} }; }
}
function save(dataDir, c) {
  fs.mkdirSync(path.join(dataDir, 'mods'), { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'mods', FILE), JSON.stringify(c, null, 2));
}

function managed(dataDir) {
  try { return new Set(JSON.parse(fs.readFileSync(path.join(dataDir, 'mods', '.launcher-managed.json'), 'utf8'))); } catch { return new Set(); }
}

// { categories: [names in display order], of: { mod: category } } for the given mod names.
function overview(dataDir, modNames) {
  const c = load(dataDir);
  const rec = loadRecords(dataDir);
  const mine = managed(dataDir);
  const all = [OURS, ...c.list, OTHER];
  const of = {};
  for (const n of modNames) {
    const a = c.assign[n];
    if (a && all.includes(a)) of[n] = a;
    else {
      const r = rec['mods/' + n];
      of[n] = mine.has(n) || (r && (r.source === 'sync' || r.source === 'repo')) ? OURS : OTHER;
    }
  }
  return { categories: all, builtin: [OURS, OTHER], of };
}

function clean(name) {
  const n = String(name || '').trim();
  if (!NAME_RE.test(n)) throw new Error('Category name: 1 to 40 characters.');
  if (n === OURS || n === OTHER) throw new Error(`"${n}" is a built-in category.`);
  return n;
}
function add(dataDir, name) {
  const n = clean(name);
  const c = load(dataDir);
  if (c.list.includes(n)) throw new Error(`Category "${n}" already exists.`);
  c.list.push(n);
  save(dataDir, c);
  return n;
}
function remove(dataDir, name) {
  const c = load(dataDir);
  if (!c.list.includes(name)) throw new Error('Only your own categories can be deleted.');
  c.list = c.list.filter((x) => x !== name);
  for (const k of Object.keys(c.assign)) if (c.assign[k] === name) delete c.assign[k];
  save(dataDir, c);
}
function rename(dataDir, name, to) {
  const n = clean(to);
  const c = load(dataDir);
  if (!c.list.includes(name)) throw new Error('Only your own categories can be renamed.');
  if (c.list.includes(n)) throw new Error(`Category "${n}" already exists.`);
  c.list = c.list.map((x) => (x === name ? n : x));
  for (const k of Object.keys(c.assign)) if (c.assign[k] === name) c.assign[k] = n;
  save(dataDir, c);
}
// Put a mod into a category. Moving it into its automatic group (Luanti Mods / Other) just clears the choice.
function assign(dataDir, mod, cat) {
  if (!/^[A-Za-z0-9_-]{1,80}$/.test(mod)) throw new Error('Bad mod name');
  const c = load(dataDir);
  if (!c.list.includes(cat) && cat !== OURS && cat !== OTHER) throw new Error('Unknown category');
  c.assign[mod] = cat;
  save(dataDir, c);
}

module.exports = { OURS, OTHER, overview, add, remove, rename, assign };
