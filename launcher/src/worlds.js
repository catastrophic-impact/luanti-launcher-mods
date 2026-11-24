'use strict';
const fs = require('fs');
const path = require('path');

const exists = (p) => fs.existsSync(p);

function listWorlds(dataDir) {
  const root = path.join(dataDir, 'worlds');
  let names = [];
  try { names = fs.readdirSync(root); } catch { /* none */ }
  return names
    .filter((n) => exists(path.join(root, n, 'world.mt')))
    .sort((a, b) => a.localeCompare(b))
    .map((n) => ({ name: n, path: path.join(root, n) }));
}

// world.mt is kept line by line: only load_mod_* lines are ever changed.
class WorldMT {
  constructor(file, lines) { this.file = file; this.lines = lines; }
  static read(worldPath) {
    const file = path.join(worldPath, 'world.mt');
    return new WorldMT(file, fs.readFileSync(file, 'utf8').split(/\r?\n/).filter((l, i, a) => !(i === a.length - 1 && l === '')));
  }
  get(key) {
    for (const l of this.lines) {
      const i = l.indexOf('=');
      if (i >= 0 && l.slice(0, i).trim() === key) return l.slice(i + 1).trim();
    }
    return undefined;
  }
  set(key, val) {
    for (let n = 0; n < this.lines.length; n++) {
      const i = this.lines[n].indexOf('=');
      if (i >= 0 && this.lines[n].slice(0, i).trim() === key) { this.lines[n] = `${key} = ${val}`; return; }
    }
    this.lines.push(`${key} = ${val}`);
  }
  modEnabled(name) { const v = this.get('load_mod_' + name); return v !== undefined && v !== 'false' && v !== ''; }
  save() { fs.writeFileSync(this.file, this.lines.join('\n') + '\n'); }
}

function modName(dir) {
  try {
    for (const l of fs.readFileSync(path.join(dir, 'mod.conf'), 'utf8').split('\n')) {
      const i = l.indexOf('=');
      if (i >= 0 && l.slice(0, i).trim() === 'name') return l.slice(i + 1).trim();
    }
  } catch { /* no mod.conf */ }
  return path.basename(dir);
}

const isMod = (d) => exists(path.join(d, 'mod.conf')) || exists(path.join(d, 'init.lua'));

function listMods(dataDir) {
  const seen = new Set();
  const scan = (dir, depth) => {
    let ents = [];
    try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      if (!e.isDirectory() || e.name.startsWith('.')) continue;
      const p = path.join(dir, e.name);
      if (isMod(p)) seen.add(modName(p));
      else if (depth < 2 && exists(path.join(p, 'modpack.conf'))) scan(p, depth + 1);
    }
  };
  scan(path.join(dataDir, 'mods'), 0);
  return [...seen].sort((a, b) => a.localeCompare(b));
}

// ---- mod metadata + dependencies --------------------------------------------------------------------------

// mod.conf: name, description, depends, optional_depends. "dep?" in depends marks an optional dependency.
function parseModConf(dir) {
  const out = { name: path.basename(dir), description: '', depends: [], optional: [] };
  let text = '';
  try { text = fs.readFileSync(path.join(dir, 'mod.conf'), 'utf8'); } catch { return out; }
  const list = (v) => v.split(',').map((x) => x.trim()).filter(Boolean);
  for (const l of text.split(/\r?\n/)) {
    const i = l.indexOf('=');
    if (i < 0 || l.trim().startsWith('#')) continue;
    const k = l.slice(0, i).trim(), v = l.slice(i + 1).trim();
    if (k === 'name' && v) out.name = v;
    else if (k === 'description') out.description = v;
    else if (k === 'depends') for (const d of list(v)) (d.endsWith('?') ? out.optional : out.depends).push(d.replace(/\?$/, ''));
    else if (k === 'optional_depends') out.optional.push(...list(v));
  }
  return out;
}

// All installed mods (modpacks included) with their metadata.
function listModsInfo(dataDir) {
  const found = new Map();
  const scan = (dir, depth) => {
    let ents = [];
    try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      if (!e.isDirectory() || e.name.startsWith('.')) continue;
      const p = path.join(dir, e.name);
      if (isMod(p)) { const m = parseModConf(p); found.set(m.name, m); }
      else if (depth < 2 && exists(path.join(p, 'modpack.conf'))) scan(p, depth + 1);
    }
  };
  scan(path.join(dataDir, 'mods'), 0);
  return [...found.values()].sort((a, b) => a.name.localeCompare(b.name));
}

// Names of the mods a game ships (its own mods satisfy dependencies).
function gameModNames(dataDir, gameid) {
  const names = new Set();
  if (!gameid) return names;
  const scan = (dir, depth) => {
    let ents = [];
    try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      if (!e.isDirectory() || e.name.startsWith('.')) continue;
      const p = path.join(dir, e.name);
      if (isMod(p)) names.add(parseModConf(p).name);
      else if (depth < 3) scan(p, depth + 1);
    }
  };
  scan(path.join(dataDir, 'games', gameid, 'mods'), 0);
  return names;
}

// Enabling `name` needs its required (non-optional) installed dependencies enabled too. Returns { enable: [names to switch on, incl. name],
// missing: [{ mod, dep }] for dependencies that are neither installed nor part of the game }.
function resolveEnable(infos, name, gameMods) {
  const by = new Map(infos.map((m) => [m.name, m]));
  const enable = [], missing = [], seen = new Set();
  const walk = (n) => {
    if (seen.has(n)) return;
    seen.add(n);
    const m = by.get(n);
    if (!m) return;
    enable.push(n);
    for (const d of m.depends) {
      if (by.has(d)) walk(d);
      else if (!gameMods.has(d)) missing.push({ mod: n, dep: d });
    }
  };
  walk(name);
  return { enable, missing };
}

// Disabling `name` breaks every enabled mod that (transitively) requires it. Returns their names.
function dependentsOf(infos, name, isEnabled) {
  const out = [], seen = new Set([name]);
  let grew = true;
  while (grew) {
    grew = false;
    for (const m of infos) {
      if (seen.has(m.name) || !isEnabled(m.name)) continue;
      if (m.depends.some((d) => seen.has(d))) { seen.add(m.name); out.push(m.name); grew = true; }
    }
  }
  return out;
}

// ---- worlds: create / delete --------------------------------------------------------------------------------

function listGames(dataDir) {
  const root = path.join(dataDir, 'games');
  let names = [];
  try { names = fs.readdirSync(root); } catch { /* none */ }
  return names.filter((n) => exists(path.join(root, n, 'game.conf'))).sort().map((id) => {
    let title = id;
    try { const m = fs.readFileSync(path.join(root, id, 'game.conf'), 'utf8').match(/^\s*title\s*=\s*(.+)$/m); if (m) title = m[1].trim(); } catch { /* keep id */ }
    return { id, title };
  });
}

const WORLD_NAME_RE = /^[^\\/:*?"<>|\x00-\x1f.][^\\/:*?"<>|\x00-\x1f]{0,63}$/;

// opts: { name, gameid, creative, flat, mods: [names to switch on] }
function createWorld(dataDir, opts) {
  const name = (opts.name || '').trim();
  if (!WORLD_NAME_RE.test(name)) throw new Error('Pick a world name: up to 64 characters, no slashes or special characters, not starting with a dot.');
  if (!listGames(dataDir).some((g) => g.id === opts.gameid)) throw new Error('Unknown game: ' + opts.gameid);
  const dir = path.join(dataDir, 'worlds', name);
  if (exists(dir)) throw new Error(`A world called "${name}" already exists.`);
  fs.mkdirSync(dir, { recursive: true });
  const lines = [
    `gameid = ${opts.gameid}`, 'backend = sqlite3', 'player_backend = sqlite3', 'auth_backend = sqlite3', 'mod_storage_backend = sqlite3',
    `world_name = ${name}`, `creative_mode = ${opts.creative ? 'true' : 'false'}`, 'enable_damage = true', 'server_announce = false',
  ];
  for (const m of opts.mods || []) lines.push(`load_mod_${m} = true`);
  fs.writeFileSync(path.join(dir, 'world.mt'), lines.join('\n') + '\n');
  // (a map_meta.txt needs its own seed: without one the game's mods see no world seed and Mineclonia fails to start)
  if (opts.flat) fs.writeFileSync(path.join(dir, 'map_meta.txt'), `mg_name = flat\nseed = ${require('crypto').randomInt(1, 2 ** 48)}\n[end_of_params]\n`);
  return { name, path: dir };
}

// Deletes a world for good. Only a folder directly inside <dataDir>/worlds that holds a world.mt is ever removed.
function deleteWorld(dataDir, worldPath) {
  const root = path.resolve(path.join(dataDir, 'worlds'));
  const dir = path.resolve(worldPath);
  if (path.dirname(dir) !== root || !exists(path.join(dir, 'world.mt'))) throw new Error('Not a world folder: refusing to delete it.');
  fs.rmSync(dir, { recursive: true, force: true });
}

module.exports = { listWorlds, WorldMT, listMods, isMod, exists, parseModConf, listModsInfo, gameModNames, resolveEnable, dependentsOf, listGames, createWorld, deleteWorld };
