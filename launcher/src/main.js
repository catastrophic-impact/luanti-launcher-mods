'use strict';
const { app, BrowserWindow, ipcMain, dialog, Menu, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const portable = require('./portable');
const config = require('./config');
const { detect } = require('./install');
const worlds = require('./worlds');
const { listWorlds, WorldMT, listMods } = worlds;
const sync = require('./sync');
const updates = require('./updates');
const contentdb = require('./contentdb');
const categories = require('./categories');
const net = require('./net');

let dataDir; // launcher-data folder (portable)
let win;

try {
  dataDir = portable.setup(app);
} catch (e) {
  app.whenReady().then(() => { dialog.showErrorBox('Luanti Launcher', e.message); app.quit(); });
}

function state() {
  const cfg = config.load(dataDir);
  const inst = detect(cfg);
  return {
    cfg,
    install: inst,
    configDir: dataDir,
    worlds: inst ? listWorlds(inst.dataDir) : [],
    folders: sync.FOLDERS,
    modsSource: config.resolveModsSource(cfg, portable.launcherDir(app)),
    games: inst ? worlds.listGames(inst.dataDir) : [],
    cats: inst ? categories.overview(inst.dataDir, []).categories : [],
  };
}

// The renderer only ever names a world by path; check it is one of the real worlds.
function worldByPath(p) {
  const st = state();
  const w = st.worlds.find((x) => x.path === p);
  if (!w) throw new Error('Unknown world');
  return w;
}
function folderById(id) {
  const f = sync.FOLDERS.find((x) => x.id === id);
  if (!f) throw new Error('Unknown folder');
  return f;
}

const handle = (name, fn) => ipcMain.handle(name, async (_e, ...args) => {
  try { return { ok: true, value: await fn(...args) }; } catch (e) { return { ok: false, error: e.message || String(e) }; }
});

handle('state', () => state());

handle('mods', (worldPath) => {
  const st = state();
  const w = worldByPath(worldPath);
  const mt = WorldMT.read(w.path);
  const infos = worlds.listModsInfo(st.install.dataDir);
  const names = new Set(infos.map((m) => m.name));
  const game = worlds.gameModNames(st.install.dataDir, mt.get('gameid'));
  const cats = categories.overview(st.install.dataDir, infos.map((m) => m.name));
  return { categories: cats.categories, builtin: cats.builtin, mods: infos.map((m) => ({
    name: m.name, description: m.description, depends: m.depends, optional: m.optional,
    category: cats.of[m.name],
    enabled: mt.modEnabled(m.name),
    missing: m.depends.filter((d) => !names.has(d) && !game.has(d)),
  })) };
});
// Enabling a mod also enables the mods it requires; disabling one also disables the enabled mods that require it.
handle('setMod', (worldPath, name, enabled) => {
  const st = state();
  const mt = WorldMT.read(worldByPath(worldPath).path);
  const infos = worlds.listModsInfo(st.install.dataDir);
  const game = worlds.gameModNames(st.install.dataDir, mt.get('gameid'));
  let changed = [], missing = [];
  if (enabled) {
    const r = worlds.resolveEnable(infos, name, game);
    for (const n of r.enable) { if (n !== name && !mt.modEnabled(n)) changed.push(n); mt.set('load_mod_' + n, 'true'); }
    mt.set('load_mod_' + name, 'true');
    missing = r.missing;
  } else {
    changed = worlds.dependentsOf(infos, name, (n) => mt.modEnabled(n));
    for (const n of changed) mt.set('load_mod_' + n, 'false');
    mt.set('load_mod_' + name, 'false');
  }
  mt.save();
  return { changed, missing };
});
// Switch a whole category (or every mod when cat is empty) on or off; switching on pulls in what the mods need.
handle('setAllMods', (worldPath, enabled, cat) => {
  const st = state();
  const mt = WorldMT.read(worldByPath(worldPath).path);
  const infos = worlds.listModsInfo(st.install.dataDir);
  const of = categories.overview(st.install.dataDir, infos.map((m) => m.name)).of;
  const game = worlds.gameModNames(st.install.dataDir, mt.get('gameid'));
  const pick = infos.filter((m) => !cat || of[m.name] === cat).map((m) => m.name);
  const missing = [];
  const pulled = new Set();
  for (const n of pick) {
    if (enabled) {
      const r = worlds.resolveEnable(infos, n, game);
      for (const x of r.enable) { mt.set('load_mod_' + x, 'true'); if (!pick.includes(x)) pulled.add(x); }
      missing.push(...r.missing);
    } else mt.set('load_mod_' + n, 'false');
  }
  if (!enabled) { // mods outside the group that need a switched-off mod would break: switch them off too
    for (const n of pick) for (const d of worlds.dependentsOf(infos, n, (x) => mt.modEnabled(x))) mt.set('load_mod_' + d, 'false');
  }
  mt.save();
  return { pulled: [...pulled], missing };
});
handle('catAdd', (name) => categories.add(needInstall(), name));
handle('catRemove', (name) => categories.remove(needInstall(), name));
handle('catRename', (name, to) => categories.rename(needInstall(), name, to));
handle('catAssign', (mod, cat) => categories.assign(needInstall(), mod, cat));
handle('openModsFolder', async () => {
  const p = path.join(needInstall(), 'mods');
  fs.mkdirSync(p, { recursive: true });
  const err = await shell.openPath(p);
  if (err) throw new Error(err);
});
handle('cdbReachable', () => contentdb.reachable(net));

// Folders live in a world (skins, capes) or in the Luanti data folder (shared music mod).
function baseFor(f, worldPath) {
  if (f.scope === 'data') {
    const st = state();
    if (!st.install) throw new Error('No Luanti install found (Settings).');
    return st.install.dataDir;
  }
  return worldByPath(worldPath).path;
}
// Worlds where Wave Matrix is on need the music mod on too.
function enableMusicMod(dataDir) {
  for (const w of listWorlds(dataDir)) {
    const mt = WorldMT.read(w.path);
    if (mt.modEnabled('wavematrix') && !mt.modEnabled('wm_music')) { mt.set('load_mod_wm_music', 'true'); mt.save(); }
  }
}
handle('folder', (worldPath, id) => { const f = folderById(id); return sync.listFolder(baseFor(f, worldPath), f); });
handle('addFiles', (worldPath, id, paths) => {
  const f = folderById(id);
  const base = baseFor(f, worldPath);
  const r = sync.addFiles(base, f, paths);
  if (id === 'music') enableMusicMod(base);
  return r;
});
handle('removeFile', (worldPath, id, name) => { const f = folderById(id); return sync.removeFile(baseFor(f, worldPath), f, name); });
handle('pickFiles', async (id) => {
  const f = folderById(id);
  const r = await dialog.showOpenDialog(win, {
    title: `Add ${f.label}`,
    properties: ['openFile', 'multiSelections', 'openDirectory'],
    filters: [{ name: f.hint, extensions: f.exts.map((e) => e.slice(1)) }, { name: 'All files', extensions: ['*'] }],
  });
  return r.canceled ? [] : r.filePaths;
});
handle('pickFolder', async (title) => {
  const r = await dialog.showOpenDialog(win, { title, properties: ['openDirectory'] });
  return r.canceled ? '' : r.filePaths[0];
});
handle('openFolder', async (worldPath, id) => {
  const f = folderById(id);
  const p = sync.ensureFolder(baseFor(f, worldPath), f);
  const err = await shell.openPath(p);
  if (err) throw new Error(err);
});

// ---- updates (our GitHub repo) and ContentDB: network only when the user presses a button ----
const cacheDir = () => path.join(dataDir, 'cache');
const needInstall = () => { const st = state(); if (!st.install) throw new Error('No Luanti install found (Settings).'); return st.install.dataDir; };
handle('updatesStatus', () => updates.status(cacheDir(), state().install ? state().install.dataDir : null));
handle('updatesCheck', async () => {
  const d = needInstall();
  await updates.checkRepo(state().cfg, cacheDir(), net);
  return updates.status(cacheDir(), d);
});
handle('updatesInstall', (names, force) => {
  const d = needInstall();
  const res = { done: [], skipped: [] };
  if (!names) return updates.installAll(d, cacheDir());
  for (const n of names) { updates.installMod(d, cacheDir(), n, !!force); res.done.push(n); }
  return res;
});
handle('cdbSearch', (q, type) => contentdb.search(net, String(q || ''), String(type || 'mod')));
handle('cdbInstalled', () => contentdb.installed(needInstall()));
handle('cdbCheck', () => contentdb.checkUpdates(net, needInstall()));
handle('uninstall', (key, force) => require('./records').uninstall(needInstall(), key, !!force));
handle('dependents', (name) => {
  const infos = worlds.listModsInfo(needInstall());
  return worlds.dependentsOf(infos, name, () => true);
});
handle('cdbInstall', (pkg, force) => contentdb.install(net, needInstall(), pkg, !!force));

handle('createWorld', (opts) => {
  const st = state();
  if (!st.install) throw new Error('No Luanti install found (Settings).');
  // No mods by default; a chosen category switches on its mods plus what they need.
  let mods = [];
  if (opts.category) {
    const infos = worlds.listModsInfo(st.install.dataDir);
    const of = categories.overview(st.install.dataDir, infos.map((m) => m.name)).of;
    const game = worlds.gameModNames(st.install.dataDir, opts.gameid);
    const on = new Set();
    for (const m of infos) if (of[m.name] === opts.category) for (const x of worlds.resolveEnable(infos, m.name, game).enable) on.add(x);
    mods = [...on];
  }
  return worlds.createWorld(st.install.dataDir, { name: opts.name, gameid: opts.gameid, creative: !!opts.creative, flat: !!opts.flat, mods });
});
handle('deleteWorld', (worldPath) => {
  const st = state();
  const w = worldByPath(worldPath);
  worlds.deleteWorld(st.install.dataDir, w.path);
  return w.name;
});

handle('saveSettings', (cfg) => {
  const clean = {};
  for (const k of Object.keys(config.DEFAULTS)) clean[k] = typeof cfg[k] === 'string' ? cfg[k].trim() : '';
  config.save(dataDir, clean);
  return state();
});

// Launch Luanti detached (it keeps running if the launcher closes).
handle('launch', (worldPath, creative) => {
  const st = state();
  if (!st.install) throw new Error('No Luanti install found (Settings).');
  const args = [...st.install.cmd.slice(1)];
  if (worldPath) {
    const w = worldByPath(worldPath);
    // Creative is chosen at every start (Play tab checkbox) and written into the world before Luanti reads it.
    if (typeof creative === 'boolean') { const mt = WorldMT.read(w.path); mt.set('creative_mode', creative ? 'true' : 'false'); mt.save(); }
    if (st.install.dataDir) worlds.applyWorldSettings(st.install.dataDir, w.path);
    args.push('--go', '--world', w.path);
    const gid = WorldMT.read(w.path).get('gameid');
    if (gid) args.push('--gameid', gid);
  }
  const child = spawn(st.install.cmd[0], args, { detached: true, stdio: 'ignore' });
  return new Promise((resolve, reject) => {
    child.once('error', (e) => reject(new Error('Could not start Luanti: ' + e.message)));
    child.once('spawn', () => { child.unref(); resolve(true); });
  });
});

function createWindow() {
  win = new BrowserWindow({
    width: 1040, height: 680, minWidth: 820, minHeight: 560,
    title: 'Luanti Launcher', backgroundColor: '#0b1220', show: false, icon: path.join(__dirname, '..', 'assets', 'icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true },
  });
  Menu.setApplicationMenu(null);
  win.loadFile(path.join(__dirname, '..', 'ui', 'index.html'));
  win.once('ready-to-show', () => win.show());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e) => e.preventDefault());
}

// Dev/test helper: LAUNCHER_SHOTS=<dir> saves a PNG of every tab, then quits.
async function shots(dir) {
  fs.mkdirSync(dir, { recursive: true });
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  await wait(1200);
  for (const tab of ['play', 'mods', 'updates', 'contentdb', 'folders', 'settings']) {
    await win.webContents.executeJavaScript(`document.querySelector('[data-tab="${tab}"]').click()`);
    await wait(700);
    fs.writeFileSync(path.join(dir, tab + '.png'), (await win.webContents.capturePage()).toPNG());
  }
  app.quit();
}

// Dev/test helper: LAUNCHER_SCRIPT=<file.js> runs that script inside the page (it can use window.api and the DOM),
// writes its return value to <LAUNCHER_SCRIPT_OUT>/result.json and a final PNG, then quits.
async function runScript(file, out) {
  fs.mkdirSync(out, { recursive: true });
  await new Promise((r) => setTimeout(r, 1200));
  let res;
  try { res = { ok: true, value: await win.webContents.executeJavaScript('(async()=>{' + fs.readFileSync(file, 'utf8') + '})()') }; }
  catch (e) { res = { ok: false, error: String(e) }; }
  fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(res, null, 2));
  fs.writeFileSync(path.join(out, 'final.png'), (await win.webContents.capturePage()).toPNG());
  app.quit();
}

if (dataDir) {
  app.whenReady().then(() => {
    createWindow();
    if (process.env.LAUNCHER_SCRIPT) win.webContents.once('did-finish-load', () => runScript(process.env.LAUNCHER_SCRIPT, process.env.LAUNCHER_SCRIPT_OUT));
    if (process.env.LAUNCHER_SHOTS) win.webContents.once('did-finish-load', () => shots(process.env.LAUNCHER_SHOTS));
  });
  app.on('window-all-closed', () => app.quit());
}
