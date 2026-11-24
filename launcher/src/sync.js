'use strict';
const fs = require('fs');
const path = require('path');
const { isMod, exists } = require('./worlds');
const { loadRecords, saveRecords, hashDir, modVersion } = require('./records');

const MANIFEST = '.launcher-managed.json';

// Makes dst an exact copy of src; files with equal size + mtime are skipped. Returns the number of changed files.
function syncTree(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  let changed = 0;
  const want = new Set();
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name);
    const d = path.join(dst, e.name);
    want.add(e.name);
    if (e.isDirectory()) { changed += syncTree(s, d); continue; }
    const si = fs.statSync(s);
    try {
      const di = fs.statSync(d);
      if (di.isFile() && di.size === si.size && Math.abs(di.mtimeMs - si.mtimeMs) < 1) continue;
    } catch { /* missing */ }
    fs.rmSync(d, { recursive: true, force: true });
    fs.copyFileSync(s, d);
    fs.utimesSync(d, si.atime, si.mtime);
    changed++;
  }
  for (const e of fs.readdirSync(dst)) {
    if (!want.has(e)) { fs.rmSync(path.join(dst, e), { recursive: true, force: true }); changed++; }
  }
  return changed;
}

// Copies every mod folder of cfg.modsSource into <dataDir>/mods; removes only mods this launcher installed earlier.
function syncMods(dataDir, cfg) {
  if (!cfg.modsSource) throw new Error('No mods source folder set (Settings).');
  const dst = path.join(dataDir, 'mods');
  const managed = [];
  const rec = loadRecords(dataDir);
  let changed = 0;
  for (const e of fs.readdirSync(cfg.modsSource, { withFileTypes: true })) {
    const s = path.join(cfg.modsSource, e.name);
    if (!e.isDirectory() || !(isMod(s) || exists(path.join(s, 'modpack.conf')))) continue;
    changed += syncTree(s, path.join(dst, e.name));
    managed.push(e.name);
    rec['mods/' + e.name] = { source: 'sync', version: modVersion(s), hash: hashDir(path.join(dst, e.name)), time: new Date().toISOString() };
  }
  const mf = path.join(dst, MANIFEST);
  let prev = [];
  try { prev = JSON.parse(fs.readFileSync(mf, 'utf8')); } catch { /* first run */ }
  let removed = 0;
  for (const p of prev) if (!managed.includes(p)) { fs.rmSync(path.join(dst, p), { recursive: true, force: true }); delete rec['mods/' + p]; removed++; }
  saveRecords(dataDir, rec);
  fs.writeFileSync(mf, JSON.stringify(managed));
  let msg = `${managed.length} mods synced (${changed} files changed, ${removed} removed)`;
  if (cfg.gameSource) {
    const n = syncTree(cfg.gameSource, path.join(dataDir, 'games', path.basename(cfg.gameSource)));
    msg += `; game ${path.basename(cfg.gameSource)}: ${n} files changed`;
  }
  return msg;
}

// Folders the launcher manages. scope "world" = inside a world folder, "data" = inside the Luanti data folder (shared by all worlds).
// Wave Matrix music is a data-only mod (<data>/mods/wm_music) because Luanti mods can only read their own folder and the world folder;
// subfolders are groups in the player. It is never part of the mods manifest, so Sync never deletes it.
const FOLDERS = [
  { id: 'music', label: 'Wave Matrix music (all worlds)', hint: '.ogg files or folders (a folder = a group)', rel: 'mods/wm_music', scope: 'data', groups: true, exts: ['.ogg'] },
  { id: 'skins', label: 'Skins', hint: '.png files (64x64 or 64x32)', rel: 'skindependence/skins', scope: 'world', exts: ['.png'] },
  { id: 'capes', label: 'Capes', hint: '.png files', rel: 'skindependence/capes', scope: 'world', exts: ['.png'] },
];

function folderPath(base, f) { return path.join(base, ...f.rel.split('/')); }

// The shared music folder must be a loadable mod.
function ensureFolder(base, f) {
  const dir = folderPath(base, f);
  fs.mkdirSync(dir, { recursive: true });
  if (f.id === 'music') {
    const mc = path.join(dir, 'mod.conf');
    if (!fs.existsSync(mc)) fs.writeFileSync(mc, 'name = wm_music\ndescription = Music folder for Wave Matrix (managed by the launcher)\n');
    const il = path.join(dir, 'init.lua');
    if (!fs.existsSync(il)) fs.writeFileSync(il, '-- data only: music files for wavematrix\n');
  }
  return dir;
}

const okExt = (f, name) => f.exts.includes(path.extname(name).toLowerCase());

// Files (relative paths with "/") of a folder; folders with groups list their subfolders too.
function listFolder(base, f) {
  const out = [];
  const walk = (dir, rel, depth) => {
    let ents = [];
    try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      const r = rel ? rel + '/' + e.name : e.name;
      if (e.isFile() && okExt(f, e.name)) out.push(r);
      else if (e.isDirectory() && f.groups && depth < 3 && !e.name.startsWith('.')) walk(path.join(dir, e.name), r, depth + 1);
    }
  };
  walk(folderPath(base, f), '', 0);
  return out.sort((a, b) => a.localeCompare(b));
}

// from = a list of files and/or folders. Plain folders contribute their files; with groups a folder keeps its name as a subfolder.
function addFiles(base, f, from) {
  const dst = ensureFolder(base, f);
  let copied = 0, skipped = 0;
  const copyDir = (src, to, depth) => {
    for (const e of fs.readdirSync(src, { withFileTypes: true })) {
      const sp = path.join(src, e.name);
      if (e.isFile()) {
        if (okExt(f, e.name)) { fs.mkdirSync(to, { recursive: true }); fs.copyFileSync(sp, path.join(to, e.name)); copied++; } else skipped++;
      } else if (e.isDirectory() && f.groups && depth < 3) copyDir(sp, path.join(to, e.name), depth + 1);
    }
  };
  for (const p of from) {
    const st = fs.statSync(p);
    if (st.isDirectory()) copyDir(p, f.groups ? path.join(dst, path.basename(p)) : dst, f.groups ? 1 : 3);
    else if (okExt(f, p)) { fs.copyFileSync(p, path.join(dst, path.basename(p))); copied++; }
    else skipped++;
  }
  return { copied, skipped };
}

function removeFile(base, f, name) {
  const root = folderPath(base, f);
  const full = path.resolve(root, name);
  if (!full.startsWith(root + path.sep) || (!f.groups && name !== path.basename(name))) throw new Error('bad file name');
  fs.rmSync(full, { force: true });
  if (f.groups) { // drop group folders that became empty
    for (let d = path.dirname(full); d !== root && d.startsWith(root); d = path.dirname(d)) {
      try { if (fs.readdirSync(d).length === 0) fs.rmdirSync(d); else break; } catch { break; }
    }
  }
}

module.exports = { syncTree, syncMods, FOLDERS, folderPath, ensureFolder, listFolder, addFiles, removeFile };
