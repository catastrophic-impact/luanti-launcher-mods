'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const crypto = require('crypto');
const { readTarGz, readZip } = require('../src/archive');
const updates = require('../src/updates');
const contentdb = require('../src/contentdb');
const { loadRecords, hashDir } = require('../src/records');
const sync = require('../src/sync');

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'll-'));

// --- tiny archive writers for fixtures ---
function paxRec(k, v) {
  const body = ` ${k}=${v}\n`;
  let n = body.length + 1;
  while (String(n).length + body.length !== n) n = String(n).length + body.length;
  return Buffer.from(n + body);
}
function tar(files, { pax = false } = {}) {
  const blocks = [];
  const hdr = (name, size, type) => {
    const b = Buffer.alloc(512);
    b.write(name.slice(0, 100), 0); b.write('0000644\0', 100); b.write('0000000\0', 108); b.write('0000000\0', 116);
    b.write(size.toString(8).padStart(11, '0') + '\0', 124); b.write('00000000000\0', 136); b.write('        ', 148); b.write(type, 156);
    b.write('ustar\0' + '00', 257);
    let sum = 0; for (const v of b) sum += v; b.write(sum.toString(8).padStart(6, '0') + '\0 ', 148);
    return b;
  };
  const pad = (d) => Buffer.concat([d, Buffer.alloc((512 - (d.length % 512)) % 512)]);
  if (pax) { const d = paxRec('comment', 'x'); blocks.push(hdr('pax_global', d.length, 'g'), pad(d)); }
  for (const [name, content] of Object.entries(files)) {
    const d = Buffer.from(content);
    if (name.length > 100) { const fixed = paxRec('path', name); blocks.push(hdr('PaxHeader', fixed.length, 'x'), pad(fixed)); }
    blocks.push(hdr(name, d.length, '0'), pad(d));
  }
  blocks.push(Buffer.alloc(1024));
  return zlib.gzipSync(Buffer.concat(blocks));
}
function zip(files, mode = 8, linkName) {
  const parts = []; const cd = []; let off = 0;
  for (const [name, content] of Object.entries(files)) {
    const raw = Buffer.from(content); const data = mode === 8 ? zlib.deflateRawSync(raw) : raw; const nm = Buffer.from(name);
    const lh = Buffer.alloc(30); lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(mode, 8); lh.writeUInt32LE(data.length, 18); lh.writeUInt32LE(raw.length, 22); lh.writeUInt16LE(nm.length, 26);
    parts.push(lh, nm, data);
    const ch = Buffer.alloc(46); ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE(mode, 10); ch.writeUInt32LE(data.length, 20); ch.writeUInt32LE(raw.length, 24); ch.writeUInt16LE(nm.length, 28);
    if (name === linkName) ch.writeUInt32LE((0o120777 << 16) >>> 0, 38);
    ch.writeUInt32LE(off, 42); cd.push(ch, nm); off += 30 + nm.length + data.length;
  }
  const cdb = Buffer.concat(cd); const e = Buffer.alloc(22); e.writeUInt32LE(0x06054b50, 0); e.writeUInt16LE(cd.length / 2, 8); e.writeUInt16LE(cd.length / 2, 10); e.writeUInt32LE(cdb.length, 12); e.writeUInt32LE(off, 16);
  return Buffer.concat([...parts, cdb, e]);
}
const fakeNet = (routes) => ({
  buffer: async (url) => { if (!(url in routes)) throw new Error('unexpected url ' + url); return routes[url]; },
  json: async (url) => { if (!(url in routes)) throw new Error('unexpected url ' + url); return routes[url]; },
});

test('tar.gz reader: files, long PAX paths, rejects traversal and links', () => {
  const long = 'repo-main/mods/a/' + 'x'.repeat(120) + '.lua';
  const e = readTarGz(tar({ 'repo-main/mods/a/mod.conf': 'name = a', [long]: 'L' }, { pax: true }));
  assert.deepStrictEqual(e.map((x) => x.name), ['repo-main/mods/a/mod.conf', long]);
  assert.strictEqual(e[1].data().toString(), 'L');
  assert.throws(() => readTarGz(tar({ 'r/../evil': 'x' })), /Unsafe/);
});

test('zip reader: deflate + stored, rejects traversal and symlinks', () => {
  for (const mode of [8, 0]) {
    const e = readZip(zip({ 'pkg/mod.conf': 'name = pkg', 'pkg/init.lua': '-- ok' }, mode));
    assert.strictEqual(e.find((x) => x.name === 'pkg/init.lua').data().toString(), '-- ok');
  }
  assert.throws(() => readZip(zip({ '../evil': 'x' })), /Unsafe/);
  assert.throws(() => readZip(zip({ 'pkg/l': 'target' }, 8, 'pkg/l')), /link/);
});

const repoCfg = { repoUrl: 'https://github.com/someone/proj', repoBranch: 'main' };
const repoUrl = 'https://codeload.github.com/someone/proj/tar.gz/refs/heads/main';
const repoTar = (v) => tar({ 'proj-main/README.md': 'x', 'proj-main/mods/alpha/mod.conf': `name = alpha\nversion = ${v}\ndescription = A`, 'proj-main/mods/alpha/init.lua': `-- ${v}`, 'proj-main/mods/beta/mod.conf': 'name = beta\nversion = 1.0.0', 'proj-main/tests/t/init.lua': '' });

test('repo: placeholder / bad URL refused', async () => {
  await assert.rejects(updates.checkRepo({ repoUrl: updates.REPO_PLACEHOLDER }, tmp(), fakeNet({})), /Settings/);
  await assert.rejects(updates.checkRepo({ repoUrl: 'https://evil.example/a/b' }, tmp(), fakeNet({})), /Settings/);
  await assert.rejects(updates.checkRepo({ ...repoCfg, repoBranch: '../x' }, tmp(), fakeNet({})), /branch/);
});

test('repo: install, up to date, update, modified is skipped, force overwrites', async () => {
  const cache = tmp(); const data = tmp();
  await updates.checkRepo(repoCfg, cache, fakeNet({ [repoUrl]: repoTar('0.1.0') }));
  let s = updates.status(cache, data);
  assert.deepStrictEqual(s.items.map((i) => [i.name, i.state, i.version]), [['alpha', 'new', '0.1.0'], ['beta', 'new', '1.0.0']]);
  assert.deepStrictEqual(updates.installAll(data, cache), { done: ['alpha', 'beta'], skipped: [] });
  assert.ok(fs.existsSync(path.join(data, 'mods', 'alpha', 'init.lua')));
  assert.ok(!fs.existsSync(path.join(data, 'mods', 'tests')));
  assert.ok(updates.status(cache, data).items.every((i) => i.state === 'current'));
  // new version upstream
  await updates.checkRepo(repoCfg, cache, fakeNet({ [repoUrl]: repoTar('0.2.0') }));
  s = updates.status(cache, data);
  assert.strictEqual(s.items[0].state, 'update'); assert.strictEqual(s.items[0].installedVersion, '0.1.0');
  // local edit => modified, not overwritten
  fs.appendFileSync(path.join(data, 'mods', 'alpha', 'init.lua'), '\n-- mine');
  assert.strictEqual(updates.status(cache, data).items[0].state, 'modified');
  assert.throws(() => updates.installMod(data, cache, 'alpha', false), /modified locally/);
  assert.deepStrictEqual(updates.installAll(data, cache), { done: [], skipped: ['alpha'] });
  assert.match(fs.readFileSync(path.join(data, 'mods', 'alpha', 'init.lua'), 'utf8'), /mine/);
  updates.installMod(data, cache, 'alpha', true);
  assert.strictEqual(updates.status(cache, data).items[0].state, 'current');
  assert.throws(() => updates.installMod(data, cache, '../x', true), /Bad mod name/);
});

test('repo: a mod installed by Sync counts as untouched; a foreign folder counts as modified', async () => {
  const cache = tmp(); const data = tmp(); const src = tmp();
  fs.mkdirSync(path.join(src, 'alpha')); fs.writeFileSync(path.join(src, 'alpha', 'mod.conf'), 'name = alpha\nversion = 0.0.1');
  sync.syncMods(data, { modsSource: src });
  assert.strictEqual(loadRecords(data)['mods/alpha'].version, '0.0.1');
  fs.mkdirSync(path.join(data, 'mods', 'beta')); fs.writeFileSync(path.join(data, 'mods', 'beta', 'init.lua'), '-- foreign');
  await updates.checkRepo(repoCfg, cache, fakeNet({ [repoUrl]: repoTar('0.1.0') }));
  const s = updates.status(cache, data).items;
  assert.strictEqual(s[0].state, 'update');
  assert.strictEqual(s[1].state, 'modified'); assert.match(s[1].why, /not installed by the launcher/);
});

// --- ContentDB ---
const B = contentdb.BASE;
const pkgZip = zip({ 'cool/mod.conf': 'name = cool', 'cool/init.lua': '-- hi' });
const rel = (id, extra = {}) => [{ id, title: '1.' + id, url: 'https://cdn.content.luanti.org/uploads/x.zip', sha256: crypto.createHash('sha256').update(pkgZip).digest('hex'), size: pkgZip.length, ...extra }];

test('contentdb: search filters odd names; install, checksum, foreign folder, update, modified', async () => {
  const net = fakeNet({
    [`${B}/api/packages/?type=mod&limit=40&q=cool`]: [{ author: 'bob', name: 'cool', title: 'Cool', short_description: 'd', type: 'mod', release: 1 }, { author: '../x', name: 'bad', type: 'mod' }],
    [`${B}/api/packages/bob/cool/releases/`]: rel(1),
    'https://cdn.content.luanti.org/uploads/x.zip': pkgZip,
  });
  const found = await contentdb.search(net, 'cool', 'mod');
  assert.deepStrictEqual(found.map((p) => p.name), ['cool']);
  const data = tmp();
  fs.mkdirSync(path.join(data, 'mods', 'cool'), { recursive: true }); fs.writeFileSync(path.join(data, 'mods', 'cool', 'x'), 'mine');
  await assert.rejects(contentdb.install(net, data, found[0], false), /not installed from this ContentDB/);
  fs.rmSync(path.join(data, 'mods', 'cool'), { recursive: true });
  assert.deepStrictEqual(await contentdb.install(net, data, found[0], false), { name: 'cool', version: '1.1', missing: [] });
  assert.ok(fs.existsSync(path.join(data, 'mods', 'cool', 'init.lua')));
  assert.ok(!fs.existsSync(path.join(data, 'mods', 'cool.launcher-tmp')));
  assert.strictEqual(contentdb.installed(data)[0].modified, false);
  // update available
  const net2 = fakeNet({ [`${B}/api/packages/bob/cool/releases/`]: rel(2) });
  assert.deepStrictEqual((await contentdb.checkUpdates(net2, data)).map((x) => [x.name, x.update, x.latest]), [['cool', true, '1.2']]);
  // modified locally is not overwritten
  fs.appendFileSync(path.join(data, 'mods', 'cool', 'init.lua'), 'x');
  await assert.rejects(contentdb.install(net2, data, found[0], false), /modified locally/);
  // bad checksum
  const bad = fakeNet({ [`${B}/api/packages/bob/cool/releases/`]: rel(3, { sha256: '00' }), 'https://cdn.content.luanti.org/uploads/x.zip': pkgZip });
  await assert.rejects(contentdb.install(bad, data, found[0], true), /checksum/);
  // foreign download host
  const evil = fakeNet({ [`${B}/api/packages/bob/cool/releases/`]: rel(3, { url: 'https://evil.example/x.zip' }) });
  await assert.rejects(contentdb.install(evil, data, found[0], true), /host/);
});

test('contentdb: thumbnails become data URIs only for real images on content.luanti.org', async () => {
  const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47]), Buffer.alloc(20, 1)]);
  const t = 'https://content.luanti.org/thumbnails/1/a.png';
  const net = fakeNet({
    [`${B}/api/packages/?type=mod&limit=40&q=`]: [
      { author: 'a', name: 'one', type: 'mod', thumbnail: t }, { author: 'a', name: 'two', type: 'mod', thumbnail: 'https://evil.example/x.png' },
      { author: 'a', name: 'three', type: 'mod', thumbnail: t + '2' }, { author: 'a', name: 'four', type: 'mod' }],
    [t]: png, [t + '2']: Buffer.from('<svg onload=alert(1)>'),
  });
  const r = await contentdb.search(net, '', 'mod');
  assert.match(r[0].thumb, /^data:image\/png;base64,/);
  assert.ok(!r[1].thumb && !r[2].thumb && !r[3].thumb);
  assert.ok(!('thumbUrl' in r[0]));
});

test('missing hard dependencies are reported; optional ones and game-provided ones are not', async () => {
  const data = tmp();
  const modzip = zip({ 'dep/mod.conf': 'name = dep\ndepends = default, other, hq\noptional_depends = nice', 'dep/init.lua': '' });
  fs.mkdirSync(path.join(data, 'games', 'g', 'mods', 'default'), { recursive: true }); fs.writeFileSync(path.join(data, 'games', 'g', 'mods', 'default', 'mod.conf'), 'name = default');
  fs.writeFileSync(path.join(data, 'games', 'g', 'game.conf'), 'title = G');
  fs.mkdirSync(path.join(data, 'mods', 'hq'), { recursive: true }); fs.writeFileSync(path.join(data, 'mods', 'hq', 'mod.conf'), 'name = hq');
  const net = fakeNet({ [`${B}/api/packages/bob/dep/releases/`]: rel(1, { sha256: crypto.createHash('sha256').update(modzip).digest('hex') }), 'https://cdn.content.luanti.org/uploads/x.zip': modzip });
  const r = await contentdb.install(net, data, { author: 'bob', name: 'dep', type: 'mod' }, false);
  assert.deepStrictEqual(r.missing, ['other']);
});

test('uninstall: needs a record, refuses modified without force, removes folder + record', async () => {
  const data = tmp(); const cache = tmp();
  await updates.checkRepo(repoCfg, cache, fakeNet({ [repoUrl]: repoTar('1.0.0') }));
  updates.installMod(data, cache, 'alpha', false);
  fs.mkdirSync(path.join(data, 'mods', 'foreign')); fs.writeFileSync(path.join(data, 'mods', 'foreign', 'init.lua'), '');
  assert.throws(() => require('../src/records').uninstall(data, 'mods/foreign', true), /not installed by this launcher/);
  assert.throws(() => require('../src/records').uninstall(data, 'mods/../x', true), /Bad package key/);
  fs.appendFileSync(path.join(data, 'mods', 'alpha', 'init.lua'), 'x');
  assert.throws(() => require('../src/records').uninstall(data, 'mods/alpha', false), /modified locally/);
  assert.strictEqual(require('../src/records').uninstall(data, 'mods/alpha', true), 'alpha');
  assert.ok(!fs.existsSync(path.join(data, 'mods', 'alpha')));
  assert.ok(fs.existsSync(path.join(data, 'mods', 'foreign')));
  assert.ok(!loadRecords(data)['mods/alpha']);
});
