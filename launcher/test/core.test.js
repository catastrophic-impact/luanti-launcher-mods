'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { WorldMT, listMods } = require('../src/worlds');
const sync = require('../src/sync');
const { splitCommand } = require('../src/install');

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'll-'));

test('world.mt round trip changes only load_mod lines', () => {
  const d = tmp();
  fs.writeFileSync(path.join(d, 'world.mt'), 'gameid = mineclonia\nload_mod_a = true\nload_mod_b = false\nbackend = sqlite3\n');
  const w = WorldMT.read(d);
  assert.ok(w.modEnabled('a')); assert.ok(!w.modEnabled('b')); assert.ok(!w.modEnabled('zzz'));
  w.set('load_mod_b', 'true'); w.set('load_mod_c', 'true'); w.save();
  assert.strictEqual(fs.readFileSync(path.join(d, 'world.mt'), 'utf8'), 'gameid = mineclonia\nload_mod_a = true\nload_mod_b = true\nbackend = sqlite3\nload_mod_c = true\n');
});

test('syncMods is idempotent, mirrors, and only removes its own mods', () => {
  const src = tmp(); const data = tmp();
  fs.mkdirSync(path.join(src, 'm1')); fs.writeFileSync(path.join(src, 'm1', 'init.lua'), '-- x');
  fs.mkdirSync(path.join(data, 'mods', 'foreign'), { recursive: true }); fs.writeFileSync(path.join(data, 'mods', 'foreign', 'init.lua'), '');
  assert.match(sync.syncMods(data, { modsSource: src }), /1 mods synced \(1 files changed, 0 removed\)/);
  assert.match(sync.syncMods(data, { modsSource: src }), /0 files changed/);
  fs.rmSync(path.join(src, 'm1'), { recursive: true });
  assert.match(sync.syncMods(data, { modsSource: src }), /1 removed/);
  assert.ok(fs.existsSync(path.join(data, 'mods', 'foreign')));
  assert.deepStrictEqual(listMods(data), ['foreign']);
});

test('addFiles filters by extension and accepts folders', () => {
  const src = tmp(); const world = tmp();
  fs.writeFileSync(path.join(src, 'a.ogg'), 'x'); fs.writeFileSync(path.join(src, 'b.txt'), 'x');
  const f = sync.FOLDERS.find((x) => x.id === 'skins');
  fs.writeFileSync(path.join(src, 'a.png'), 'x');
  assert.deepStrictEqual(sync.addFiles(world, f, [src]), { copied: 1, skipped: 2 });
  assert.deepStrictEqual(sync.listFolder(world, f), ['a.png']);
  assert.deepStrictEqual(sync.addFiles(world, f, [path.join(src, 'b.txt')]), { copied: 0, skipped: 1 });
  assert.throws(() => sync.removeFile(world, f, '../x'));
});

test('splitCommand keeps quoted parts', () => {
  assert.deepStrictEqual(splitCommand('flatpak run "org.luanti.luanti"'), ['flatpak', 'run', 'org.luanti.luanti']);
});

test('music folder: shared mod, folders become groups, Sync never removes it, safe removal', () => {
  const src = tmp(); const data = tmp(); const mods = tmp();
  const f = sync.FOLDERS.find((x) => x.id === 'music');
  fs.mkdirSync(path.join(src, 'Rock')); fs.writeFileSync(path.join(src, 'Rock', 'a.ogg'), 'x'); fs.writeFileSync(path.join(src, 'Rock', 'b.mp3'), 'x');
  fs.writeFileSync(path.join(src, 'solo.ogg'), 'x');
  const r = sync.addFiles(data, f, [path.join(src, 'Rock'), path.join(src, 'solo.ogg')]);
  assert.deepStrictEqual(r, { copied: 2, skipped: 1 });
  assert.deepStrictEqual(sync.listFolder(data, f), ['Rock/a.ogg', 'solo.ogg']);
  assert.ok(fs.existsSync(path.join(data, 'mods', 'wm_music', 'mod.conf')) && fs.existsSync(path.join(data, 'mods', 'wm_music', 'init.lua')));
  assert.deepStrictEqual(listMods(data), ['wm_music']);
  fs.mkdirSync(path.join(mods, 'm1')); fs.writeFileSync(path.join(mods, 'm1', 'init.lua'), '');
  sync.syncMods(data, { modsSource: mods }); sync.syncMods(data, { modsSource: mods });
  assert.deepStrictEqual(sync.listFolder(data, f), ['Rock/a.ogg', 'solo.ogg']); // Sync leaves it alone
  assert.throws(() => sync.removeFile(data, f, '../x.ogg'));
  assert.throws(() => sync.removeFile(data, f, '../../etc/passwd'));
  sync.removeFile(data, f, 'Rock/a.ogg');
  assert.ok(!fs.existsSync(path.join(data, 'mods', 'wm_music', 'Rock'))); // empty group folder removed
  assert.deepStrictEqual(sync.listFolder(data, f), ['solo.ogg']);
});

test('mod metadata, dependency resolution and dependents', () => {
  const data = tmp();
  const mk = (n, conf) => { const d = path.join(data, 'mods', n); fs.mkdirSync(d, { recursive: true }); fs.writeFileSync(path.join(d, 'mod.conf'), conf); fs.writeFileSync(path.join(d, 'init.lua'), ''); };
  mk('a', 'name = a\ndescription = The A mod\ndepends = b, game_mod, ghost, opt?\n');
  mk('b', 'name = b\ndepends = c\noptional_depends = a, zzz\n');
  mk('c', 'name = c\n');
  fs.mkdirSync(path.join(data, 'games', 'g', 'mods', 'game_mod'), { recursive: true });
  fs.writeFileSync(path.join(data, 'games', 'g', 'mods', 'game_mod', 'init.lua'), '');
  const w = require('../src/worlds');
  const infos = w.listModsInfo(data);
  const a = infos.find((m) => m.name === 'a');
  assert.deepStrictEqual([a.description, a.depends, a.optional], ['The A mod', ['b', 'game_mod', 'ghost'], ['opt']]);
  const game = w.gameModNames(data, 'g');
  assert.ok(game.has('game_mod'));
  const r = w.resolveEnable(infos, 'a', game);
  assert.deepStrictEqual(r.enable.sort(), ['a', 'b', 'c']);
  assert.deepStrictEqual(r.missing, [{ mod: 'a', dep: 'ghost' }]); // game_mod is provided by the game, ghost is nowhere
  const on = new Set(['a', 'b', 'c']);
  assert.deepStrictEqual(w.dependentsOf(infos, 'c', (n) => on.has(n)).sort(), ['a', 'b']);
  assert.deepStrictEqual(w.dependentsOf(infos, 'a', (n) => on.has(n)), []);
});

test('create and delete worlds, with safety checks', () => {
  const data = tmp();
  fs.mkdirSync(path.join(data, 'games', 'mineclonia'), { recursive: true });
  fs.writeFileSync(path.join(data, 'games', 'mineclonia', 'game.conf'), 'title = Mineclonia\n');
  const w = require('../src/worlds');
  assert.deepStrictEqual(w.listGames(data), [{ id: 'mineclonia', title: 'Mineclonia' }]);
  const r = w.createWorld(data, { name: 'Alpha', gameid: 'mineclonia', creative: true, flat: true, mods: ['a', 'b'] });
  const mt = WorldMT.read(r.path);
  assert.strictEqual(mt.get('gameid'), 'mineclonia'); assert.strictEqual(mt.get('creative_mode'), 'true'); assert.ok(mt.modEnabled('a') && mt.modEnabled('b'));
  const meta = fs.readFileSync(path.join(r.path, 'map_meta.txt'), 'utf8');
  assert.match(meta, /mg_name = flat/); assert.match(meta, /^seed = \d+$/m); assert.match(meta, /\[end_of_params\]/);
  assert.strictEqual(w.listWorlds(data).length, 1);
  for (const bad of ['', '  ', '../x', 'a/b', '.hidden', 'x'.repeat(65), 'a:b']) assert.throws(() => w.createWorld(data, { name: bad, gameid: 'mineclonia' }), /name/i);
  assert.throws(() => w.createWorld(data, { name: 'Alpha', gameid: 'mineclonia' }), /already exists/);
  assert.throws(() => w.createWorld(data, { name: 'Beta', gameid: 'nope' }), /Unknown game/);
  // delete: only real worlds directly inside worlds/
  assert.throws(() => w.deleteWorld(data, data), /refusing/);
  assert.throws(() => w.deleteWorld(data, path.join(data, 'worlds')), /refusing/);
  assert.throws(() => w.deleteWorld(data, path.join(data, 'worlds', 'Alpha', '..', '..')), /refusing/);
  fs.mkdirSync(path.join(data, 'worlds', 'notaworld')); // no world.mt
  assert.throws(() => w.deleteWorld(data, path.join(data, 'worlds', 'notaworld')), /refusing/);
  w.deleteWorld(data, r.path);
  assert.ok(!fs.existsSync(r.path));
  assert.ok(fs.existsSync(path.join(data, 'games')));
});

test('mods source: configured wins, else a mods folder next to the launcher', () => {
  const base = tmp();
  const config = require('../src/config');
  assert.deepStrictEqual(config.resolveModsSource({ modsSource: '' }, base), { path: '', auto: false });
  fs.mkdirSync(path.join(base, 'mods'));
  assert.deepStrictEqual(config.resolveModsSource({ modsSource: '' }, base), { path: path.join(base, 'mods'), auto: true });
  assert.deepStrictEqual(config.resolveModsSource({ modsSource: '/x' }, base), { path: '/x', auto: false });
});

test('filter: blocks by whole word, not by substring', () => {
  const { blockedBy } = require('../src/filter');
  assert.ok(blockedBy({ name: 'pride_flags', title: 'Pride Flags' }));
  assert.ok(blockedBy({ name: 'x', description: 'A NSFW pack' }));
  assert.ok(blockedBy({ name: 'x', tags: ['LGBTQ'] }));
  assert.strictEqual(blockedBy({ name: 'sussex_castles', title: 'Transport and transforms', description: 'Proud of essex' }), '');
});

test('categories: built-in groups, assign, rename, delete', () => {
  const categories = require('../src/categories');
  const data = fs.mkdtempSync(path.join(os.tmpdir(), 'll-cat-'));
  fs.mkdirSync(path.join(data, 'mods'));
  fs.writeFileSync(path.join(data, 'mods', '.launcher-managed.json'), JSON.stringify(['ours']));
  let o = categories.overview(data, ['ours', 'theirs']);
  assert.deepStrictEqual([o.of.ours, o.of.theirs], [categories.OURS, categories.OTHER]);
  categories.add(data, 'Survival');
  assert.throws(() => categories.add(data, 'Survival'), /exists/);
  assert.throws(() => categories.add(data, categories.OTHER), /built-in/);
  categories.assign(data, 'theirs', 'Survival');
  assert.strictEqual(categories.overview(data, ['theirs']).of.theirs, 'Survival');
  categories.rename(data, 'Survival', 'Hard');
  assert.strictEqual(categories.overview(data, ['theirs']).of.theirs, 'Hard');
  categories.remove(data, 'Hard');
  assert.strictEqual(categories.overview(data, ['theirs']).of.theirs, categories.OTHER);
});
