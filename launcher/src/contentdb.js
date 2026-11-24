'use strict';
// ContentDB (https://content.luanti.org) browse / install / update. Public read API, no login; network only on button presses.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { readZip, writeEntries } = require('./archive');
const { loadRecords, saveRecords, hashDir } = require('./records');
const worlds = require('./worlds');

const BASE = 'https://content.luanti.org';
const TYPES = { mod: 'mods', game: 'games', txp: 'textures' }; // type -> folder in the Luanti data dir
const nameOk = (s) => /^[A-Za-z0-9_-]{1,80}$/.test(s);

async function search(net, q, type) {
  if (!TYPES[type]) throw new Error('Unknown package type');
  const url = `${BASE}/api/packages/?type=${type}&limit=40&q=${encodeURIComponent((q || '').slice(0, 100))}`;
  const list = await net.json(url);
  const items = list.map((p) => ({ author: p.author, name: p.name, title: p.title || p.name, description: p.short_description || '', type: p.type, release: p.release, thumbUrl: p.thumbnail || '' }))
    .filter((p) => nameOk(p.author) && nameOk(p.name) && TYPES[p.type]);
  await addThumbs(net, items);
  return items;
}

// Small preview pictures, fetched here (the page may not load remote images) and handed over as data: URIs.
// Only content.luanti.org, only real PNG/JPEG/WebP bytes, at most 400 KB each; a failed picture is simply left out.
function imageMime(b) {
  if (b.length > 12 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return 'image/png';
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length > 12 && b.toString('latin1', 0, 4) === 'RIFF' && b.toString('latin1', 8, 12) === 'WEBP') return 'image/webp';
  return '';
}
async function addThumbs(net, items) {
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const p = items[next++];
      const url = p.thumbUrl; delete p.thumbUrl;
      try {
        if (!url || !/^https:\/\/(cdn\.)?content\.luanti\.org\//.test(url)) continue;
        const b = await net.buffer(url, { maxBytes: 400 * 1024, timeoutMs: 15000 });
        const mime = imageMime(b);
        if (mime) p.thumb = `data:${mime};base64,${b.toString('base64')}`;
      } catch { /* no picture */ }
    }
  };
  await Promise.all([worker(), worker(), worker(), worker(), worker(), worker()]);
}

async function latestRelease(net, author, name) {
  const rels = await net.json(`${BASE}/api/packages/${author}/${name}/releases/`);
  if (!Array.isArray(rels) || !rels.length) throw new Error(`${author}/${name} has no releases`);
  const r = rels[0]; // newest first
  return { id: r.id, title: r.title || r.name || String(r.id), url: r.url, sha256: r.sha256 || '', size: r.size || 0 };
}

const keyOf = (type, name) => `${TYPES[type]}/${name}`;

// Strip one shared top folder; the package root is where mod.conf/modpack.conf/game.conf/texture_pack.conf sits.
function packageItems(entries) {
  const isConf = (n) => /(^|\/)(mod\.conf|modpack\.conf|game\.conf|texture_pack\.conf)$/.test(n);
  const tops = new Set(entries.map((e) => e.name.split('/')[0]));
  const nested = tops.size === 1 && entries.every((e) => e.name.includes('/'));
  const items = entries.map((e) => ({ rel: nested ? e.name.split('/').slice(1).join('/') : e.name, data: e.data }));
  if (!items.some((i) => ['mod.conf', 'modpack.conf', 'game.conf', 'texture_pack.conf'].includes(i.rel)) && !items.some((i) => isConf(i.rel))) throw new Error('Not a Luanti package (no mod.conf, game.conf or texture_pack.conf)');
  return items;
}

async function install(net, dataDir, p, force) {
  if (!nameOk(p.author) || !nameOk(p.name) || !TYPES[p.type]) throw new Error('Bad package');
  const key = keyOf(p.type, p.name);
  const target = path.join(dataDir, TYPES[p.type], p.name);
  const rec = loadRecords(dataDir);
  const have = hashDir(target);
  if (have) {
    const r = rec[key];
    if (!r || r.source !== 'contentdb' || r.author !== p.author) throw new Error(`${p.name}: a folder with this name exists that was not installed from this ContentDB package.`);
    if (r.hash !== have && !force) throw new Error(`${p.name}: modified locally; not overwritten.`);
  }
  const rel = await latestRelease(net, p.author, p.name);
  let host;
  try { host = new URL(rel.url).hostname; } catch { host = ''; }
  if (!/(^|\.)content\.luanti\.org$/.test(host)) throw new Error('Unexpected download host: ' + host);
  const buf = await net.buffer(rel.url, { maxBytes: 300 * 1024 * 1024 });
  if (rel.sha256 && crypto.createHash('sha256').update(buf).digest('hex') !== rel.sha256) throw new Error('Download checksum does not match ContentDB.');
  const items = packageItems(readZip(buf));
  const tmp = target + '.launcher-tmp';
  fs.rmSync(tmp, { recursive: true, force: true });
  try {
    writeEntries(tmp, items);
    fs.rmSync(target, { recursive: true, force: true });
    fs.renameSync(tmp, target);
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  rec[key] = { source: 'contentdb', author: p.author, name: p.name, type: p.type, release: rel.id, version: rel.title, hash: hashDir(target), time: new Date().toISOString() };
  saveRecords(dataDir, rec);
  return { name: p.name, version: rel.title, missing: p.type === 'mod' ? missingDeps(dataDir, p.name) : [] };
}

// Packages installed through ContentDB (from the launcher's records).
function installed(dataDir) {
  const rec = loadRecords(dataDir);
  return Object.values(rec).filter((r) => r.source === 'contentdb').map((r) => ({ author: r.author, name: r.name, type: r.type, release: r.release, version: r.version,
    modified: hashDir(path.join(dataDir, TYPES[r.type], r.name)) !== r.hash }));
}

// For each installed package: is there a newer release? (one request each)
async function checkUpdates(net, dataDir) {
  const out = [];
  for (const p of installed(dataDir)) {
    try { const r = await latestRelease(net, p.author, p.name); out.push({ ...p, latest: r.title, update: r.id !== p.release }); }
    catch (e) { out.push({ ...p, error: e.message }); }
  }
  return out;
}

// Hard dependencies of an installed mod that nothing provides (not in <data>/mods, not in any game).
function missingDeps(dataDir, name) {
  const infos = worlds.listModsInfo(dataDir);
  const have = new Set(infos.map((m) => m.name));
  for (const g of worlds.listGames(dataDir)) for (const n of worlds.gameModNames(dataDir, g.id)) have.add(n);
  const me = infos.find((m) => m.name === name);
  return me ? me.depends.filter((d) => !have.has(d)) : [];
}

module.exports = { missingDeps, BASE, TYPES, search, latestRelease, install, installed, checkUpdates, packageItems };
