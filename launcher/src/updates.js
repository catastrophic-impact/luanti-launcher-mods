'use strict';
// Updates from our own GitHub repo (layout: <repo>/mods/<mod>/mod.conf with a "version = ..." line).
// The repo archive is downloaded only when the user presses "Check for updates"; mods are cached in <launcher-data>/cache/repo.
const fs = require('fs');
const path = require('path');
const { readTarGz, writeEntries } = require('./archive');
const { loadRecords, saveRecords, hashDir, readConf } = require('./records');
const { syncTree } = require('./sync');

const REPO_PLACEHOLDER = 'https://github.com/OWNER/REPO';

function parseRepo(url, branch) {
  const m = /^https:\/\/github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+?)(?:\.git)?\/?$/.exec((url || '').trim());
  if (!m || (m[1] === 'OWNER' && m[2] === 'REPO')) throw new Error('Set your GitHub repository (https://github.com/<owner>/<repo>) in Settings first.');
  const b = (branch || 'main').trim();
  if (!/^[A-Za-z0-9_][A-Za-z0-9_./-]*$/.test(b) || b.includes('..')) throw new Error('Bad branch name');
  return { owner: m[1], repo: m[2], branch: b };
}
const archiveUrl = (r) => `https://codeload.github.com/${r.owner}/${r.repo}/tar.gz/refs/heads/${r.branch}`;

const cacheRepoDir = (cacheDir) => path.join(cacheDir, 'repo');
const metaFile = (cacheDir) => path.join(cacheDir, 'repo.json');

// Downloads the repo archive and caches every mods/<name>/ folder. net = { buffer(url) } (injected for tests).
async function checkRepo(cfg, cacheDir, net) {
  const r = parseRepo(cfg.repoUrl, cfg.repoBranch);
  const gz = await net.buffer(archiveUrl(r));
  const entries = readTarGz(gz);
  const items = [];
  const names = new Set();
  for (const e of entries) {
    const parts = e.name.split('/'); // <repo>-<branch>/mods/<mod>/...
    if (parts.length < 4 || parts[1] !== 'mods') continue;
    if (!/^[a-z0-9_]+$/.test(parts[2])) continue;
    names.add(parts[2]);
    items.push({ rel: parts.slice(2).join('/'), data: e.data });
  }
  if (!names.size) throw new Error('No mods found in the repository (expected a mods/ folder in the branch).');
  const dst = cacheRepoDir(cacheDir);
  fs.rmSync(dst, { recursive: true, force: true });
  writeEntries(dst, items);
  fs.mkdirSync(cacheDir, { recursive: true });
  fs.writeFileSync(metaFile(cacheDir), JSON.stringify({ checked: new Date().toISOString(), repo: `${r.owner}/${r.repo}`, branch: r.branch }));
  return status(cacheDir, null);
}

// status of every cached repo mod against the installed copy in <dataDir>/mods.
function status(cacheDir, dataDir) {
  let meta = null;
  try { meta = JSON.parse(fs.readFileSync(metaFile(cacheDir), 'utf8')); } catch { /* never checked */ }
  const root = cacheRepoDir(cacheDir);
  const rec = dataDir ? loadRecords(dataDir) : {};
  const items = [];
  let names = [];
  try { names = fs.readdirSync(root, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name).sort(); } catch { /* none */ }
  for (const name of names) {
    const src = path.join(root, name);
    const conf = readConf(path.join(src, 'mod.conf'));
    const item = { name, description: conf.description || '', version: conf.version || '', state: 'new', installedVersion: '', tracked: !!rec['mods/' + name] };
    if (dataDir) {
      const dst = path.join(dataDir, 'mods', name);
      const have = hashDir(dst);
      if (have) {
        item.installedVersion = readConf(path.join(dst, 'mod.conf')).version || '';
        const r = rec['mods/' + name];
        if (have === hashDir(src)) item.state = 'current';
        else if (r && r.source !== 'contentdb' && r.hash === have) item.state = 'update';
        else item.state = 'modified';
        if (item.state === 'modified') item.why = r && r.source === 'contentdb' ? 'installed from ContentDB' : r ? 'changed on disk since the launcher installed it' : 'not installed by the launcher';
      }
    }
    items.push(item);
  }
  return { checked: meta ? meta.checked : '', repo: meta ? meta.repo : '', branch: meta ? meta.branch : '', items };
}

// Installs/updates one cached mod. A locally modified mod is skipped unless force is set.
function installMod(dataDir, cacheDir, name, force) {
  if (!/^[a-z0-9_]+$/.test(name)) throw new Error('Bad mod name');
  const st = status(cacheDir, dataDir).items.find((i) => i.name === name);
  if (!st) throw new Error(`${name}: not in the last check. Press "Check for updates" first.`);
  if (st.state === 'current') return { name, state: 'current' };
  if (st.state === 'modified' && !force) throw new Error(`${name}: modified locally (${st.why}); not overwritten.`);
  const src = path.join(cacheRepoDir(cacheDir), name);
  const dst = path.join(dataDir, 'mods', name);
  fs.mkdirSync(path.join(dataDir, 'mods'), { recursive: true });
  syncTree(src, dst);
  const rec = loadRecords(dataDir);
  rec['mods/' + name] = { source: 'repo', version: st.version, hash: hashDir(dst), time: new Date().toISOString() };
  saveRecords(dataDir, rec);
  return { name, state: 'installed', version: st.version };
}

// Installs every mod that is new or has an update; reports the ones skipped because they were modified.
function installAll(dataDir, cacheDir) {
  const done = [], skipped = [];
  for (const i of status(cacheDir, dataDir).items) {
    if (i.state === 'new' || i.state === 'update') done.push(installMod(dataDir, cacheDir, i.name, false).name);
    else if (i.state === 'modified') skipped.push(i.name);
  }
  return { done, skipped };
}

module.exports = { REPO_PLACEHOLDER, parseRepo, archiveUrl, checkRepo, status, installMod, installAll };
