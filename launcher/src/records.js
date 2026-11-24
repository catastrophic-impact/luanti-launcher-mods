'use strict';
// Small shared helpers: what the launcher installed (records), folder hashes and mod.conf values.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const RECORDS = '.launcher-installed.json'; // lives in <data>/mods next to .launcher-managed.json

// Keys look like "mods/<name>", "games/<name>" or "textures/<name>".
function loadRecords(dataDir) {
  try { return JSON.parse(fs.readFileSync(path.join(dataDir, 'mods', RECORDS), 'utf8')); } catch { return {}; }
}
function saveRecords(dataDir, rec) {
  fs.mkdirSync(path.join(dataDir, 'mods'), { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'mods', RECORDS), JSON.stringify(rec, null, 2));
}

// sha256 over every file (relative path, size, bytes) in a stable order; "" when the folder does not exist.
function hashDir(dir) {
  const h = crypto.createHash('sha256');
  let any = false;
  const walk = (d, rel) => {
    let ents;
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    ents.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    for (const e of ents) {
      const r = rel ? rel + '/' + e.name : e.name;
      if (e.isDirectory()) walk(path.join(d, e.name), r);
      else if (e.isFile()) {
        const data = fs.readFileSync(path.join(d, e.name));
        h.update(r + '\0' + data.length + '\0'); h.update(data); any = true;
      }
    }
  };
  walk(dir, '');
  return any ? h.digest('hex') : '';
}

function readConf(file) {
  const out = {};
  let txt = '';
  try { txt = fs.readFileSync(file, 'utf8'); } catch { return out; }
  for (const line of txt.split(/\r?\n/)) {
    const m = /^\s*([A-Za-z_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (m && !line.trim().startsWith('#')) out[m[1]] = m[2];
  }
  return out;
}
const modVersion = (dir) => readConf(path.join(dir, 'mod.conf')).version || '';

// Removes something the launcher installed (it must have a record). A folder changed since install needs force.
function uninstall(dataDir, key, force) {
  const m = /^(mods|games|textures)\/([A-Za-z0-9_-]{1,80})$/.exec(key || '');
  if (!m) throw new Error('Bad package key');
  const rec = loadRecords(dataDir);
  if (!rec[key]) throw new Error(`${m[2]}: not installed by this launcher, so it is not removed here.`);
  const dir = path.join(dataDir, m[1], m[2]);
  const have = hashDir(dir);
  if (have && have !== rec[key].hash && !force) throw new Error(`${m[2]}: modified locally; not removed.`);
  fs.rmSync(dir, { recursive: true, force: true });
  delete rec[key];
  saveRecords(dataDir, rec);
  return m[2];
}

module.exports = { uninstall, RECORDS, loadRecords, saveRecords, hashDir, readConf, modVersion };
