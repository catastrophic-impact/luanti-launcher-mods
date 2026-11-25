'use strict';
const $ = (s, el = document) => el.querySelector(s);
const view = $('#view');
const S = { tab: 'play', st: null, world: null };

function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (v === true) el.setAttribute(k, '');
    else if (v !== false && v != null) el.setAttribute(k, v);
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid.nodeType ? kid : document.createTextNode(kid));
  return el;
}

let toastTimer;
function toast(msg, err = false) {
  const t = $('#toast');
  t.textContent = msg; t.className = 'toast' + (err ? ' err' : ''); t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, err ? 7000 : 3500);
}
async function run(fn, okMsg) {
  try { const r = await fn(); if (okMsg) toast(typeof okMsg === 'function' ? okMsg(r) : okMsg); return r; }
  catch (e) { toast(e.message, true); return undefined; }
}

async function refresh() {
  S.st = await api.state();
  const inst = S.st.install;
  const pill = $('#install');
  pill.className = 'pill' + (inst ? '' : ' bad');
  pill.textContent = inst ? `${inst.kind} · ${inst.dataDir}` : 'No Luanti install found - open Settings';
  if (!S.st.worlds.find((w) => w.path === S.world)) S.world = S.st.worlds[0]?.path || null;
}

function worldSelect(onchange) {
  const sel = h('select', { onchange: (e) => { S.world = e.target.value; onchange(); } },
    S.st.worlds.map((w) => h('option', { value: w.path, selected: w.path === S.world }, w.name)));
  return h('div', { class: 'row' }, h('span', { class: 'sub', style: 'margin:0' }, 'World'), sel);
}

// ---- tabs -------------------------------------------------------------------------------------

async function renderPlay() {
  const st = S.st;
  const list = h('div', { class: 'list' });
  for (const w of st.worlds) {
    list.append(h('div', { class: 'world' + (w.path === S.world ? ' sel' : ''), ondblclick: () => launch(w.path), onclick: () => { S.world = w.path; renderPlay(); } },
      h('div', { class: 'ic' }), h('div', {}, h('div', { class: 't' }, w.name), h('div', { class: 'd' }, w.path))));
  }
  const cur = st.worlds.find((w) => w.path === S.world);
  view.replaceChildren(
    h('h2', {}, 'Your worlds'),
    h('p', { class: 'sub' }, 'Pick a world and press Play. Double-click a world to start it right away.'),
    st.worlds.length ? list : h('div', { class: 'empty' }, st.install ? 'No worlds yet. Press "New world" to create one.' : 'Luanti was not found. Open Settings to point the launcher at it.'),
    h('div', { class: 'row' },
      h('button', { class: 'btn primary big', disabled: !cur, onclick: () => launch(cur.path) }, cur ? `▶  PLAY  ${cur.name}` : '▶  PLAY'),
      h('button', { class: 'btn', disabled: !st.install, onclick: () => launch(null) }, 'Open Luanti menu'),
      h('span', { class: 'spacer' }),
      h('button', { class: 'btn', disabled: !st.install || !st.games.length, onclick: newWorldDialog }, '＋ New world'),
      h('button', { class: 'btn danger', disabled: !cur, onclick: () => deleteWorldDialog(cur) }, 'Delete world')));
}
async function launch(worldPath) {
  await run(() => api.launch(worldPath), 'Luanti is starting...');
}

// ---- dialogs ----------------------------------------------------------------------------------

function modal(title, body, buttons) {
  const back = h('div', { class: 'modal-back' });
  const close = () => back.remove();
  back.addEventListener('mousedown', (e) => { if (e.target === back) close(); });
  const card = h('div', { class: 'modal' }, h('h2', {}, title), body, h('div', { class: 'row end' }, buttons(close)));
  back.append(card);
  document.body.append(back);
  return { close, card };
}

function newWorldDialog() {
  const st = S.st;
  const name = h('input', { type: 'text', placeholder: 'My world', maxlength: '64' });
  const game = h('select', {}, st.games.map((g) => h('option', { value: g.id }, g.title)));
  const type = h('select', {}, h('option', { value: 'default' }, 'Default'), h('option', { value: 'flat' }, 'Flat (for testing and building)'));
  const creative = h('input', { type: 'checkbox' });
  const cat = h('select', {}, h('option', { value: '' }, 'No mods (add them later in the Mods tab)'), st.cats.map((c) => h('option', { value: c }, `Everything in "${c}"`)));
  const field = (label, el) => h('div', { class: 'field' }, h('label', {}, label), el);
  const check = (el, text) => h('label', { class: 'check' }, el, ' ', text);
  const m = modal('New world', h('div', {},
    field('Name', name), field('Game', game), field('World type', type),
    h('div', { class: 'field' }, check(creative, 'Creative mode')),
    field('Start with mods', cat)),
  (close) => [
    h('button', { class: 'btn', onclick: close }, 'Cancel'),
    h('button', { class: 'btn primary', onclick: async () => {
      const r = await run(() => api.createWorld({ name: name.value, gameid: game.value, flat: type.value === 'flat', creative: creative.checked, category: cat.value }), (w) => `Created "${w.name}"`);
      if (r) { close(); await refresh(); S.world = r.path; renderPlay(); }
    } }, 'Create')]);
  name.focus();
  name.addEventListener('keydown', (e) => { if (e.key === 'Enter') m.card.querySelector('.btn.primary').click(); });
}

function deleteWorldDialog(w) {
  const confirm = h('input', { type: 'text', placeholder: w.name });
  const m = modal('Delete world', h('div', {},
    h('p', { class: 'sub' }, 'This permanently deletes the world and everything built in it. It cannot be undone.'),
    h('div', { class: 'paths', style: 'margin-bottom:12px' }, w.path),
    h('div', { class: 'field' }, h('label', {}, `Type the world name to confirm: ${w.name}`), confirm)),
  (close) => [
    h('button', { class: 'btn', onclick: close }, 'Cancel'),
    h('button', { class: 'btn danger', id: 'del-go', disabled: true, onclick: async () => {
      const r = await run(() => api.deleteWorld(w.path), (n) => `Deleted "${n}"`);
      if (r !== undefined) { close(); S.world = null; await refresh(); renderPlay(); }
    } }, 'Delete forever')]);
  const go = m.card.querySelector('#del-go');
  confirm.addEventListener('input', () => { go.disabled = confirm.value !== w.name; });
  confirm.focus();
}

async function renderMods() {
  const st = S.st;
  if (!st.worlds.length) return view.replaceChildren(h('div', { class: 'empty' }, 'No worlds found.'));
  const data = await run(() => api.mods(S.world)) || { categories: [], builtin: [], mods: [] };
  const mods = data.mods;
  let filter = '';
  const body = h('div', {});
  const count = h('span', { class: 'sub', style: 'margin:0' });
  const reload = async () => { const top = view.scrollTop; await renderMods(); view.scrollTop = top; };
  const setAll = (on, cat) => async () => {
    const r = await run(() => api.setAllMods(S.world, on, cat || ''));
    if (r && r.pulled.length) toast('Also switched on (needed): ' + r.pulled.join(', '));
    if (r && r.missing.length) toast('Missing mods: ' + r.missing.map((x) => `${x.dep} (needed by ${x.mod})`).join(', '), true);
    reload();
  };
  const modRow = (m) => {
    const info = h('div', { class: 'mi' }, h('span', { class: 'mn' }, m.name));
    if (m.description) info.append(h('div', { class: 'md' }, m.description));
    const tags = h('div', { class: 'tags' });
    if (m.name === 'wm_music') tags.append(h('span', { class: 'tag data' }, 'music folder (shared)'));
    if (m.depends.length) tags.append(h('span', { class: 'tag' }, 'needs ' + m.depends.join(', ')));
    if (m.missing.length) tags.append(h('span', { class: 'tag bad' }, 'missing: ' + m.missing.join(', ')));
    if (tags.childNodes.length) info.append(tags);
    const move = h('select', { class: 'catsel', title: 'Move to category', onclick: (e) => e.stopPropagation(), onchange: async (e) => { e.stopPropagation(); await run(() => api.catAssign(m.name, e.target.value)); reload(); } },
      data.categories.map((c) => h('option', { value: c, selected: c === m.category }, c)));
    info.append(move);
    const el = h('div', { class: 'mod' + (m.enabled ? ' on' : '') + (m.missing.length ? ' warn' : '') }, h('div', { class: 'sw' }), info);
    el.addEventListener('click', async () => {
      const want = !m.enabled;
      const r = await run(() => api.setMod(S.world, m.name, want));
      if (!r) return;
      if (r.changed.length) toast(`${want ? 'Also switched on' : 'Also switched off'}: ${r.changed.join(', ')}`);
      if (r.missing.length) toast('Missing mods: ' + r.missing.map((x) => `${x.dep} (needed by ${x.mod})`).join(', '), true);
      reload();
    });
    return el;
  };
  const draw = () => {
    body.replaceChildren();
    const shown = mods.filter((x) => x.name.toLowerCase().includes(filter) || (x.description || '').toLowerCase().includes(filter));
    for (const c of data.categories) {
      const all = mods.filter((m) => m.category === c);
      const list = shown.filter((m) => m.category === c);
      if (!all.length && data.builtin.includes(c)) continue; // empty built-in groups stay hidden
      if (filter && !list.length) continue;
      const own = !data.builtin.includes(c);
      const on = all.filter((m) => m.enabled).length;
      const grid = h('div', { class: 'grid' }, list.map(modRow));
      body.append(h('div', { class: 'cat' },
        h('div', { class: 'row cathead' }, h('h3', {}, c), h('span', { class: 'hint' }, `${on} of ${all.length} on`), h('span', { class: 'spacer' }),
          own ? h('button', { class: 'btn small', onclick: () => renameCatDialog(c, reload) }, 'Rename') : null,
          own ? h('button', { class: 'btn small', onclick: async () => { await run(() => api.catRemove(c)); reload(); } }, 'Delete') : null,
          h('button', { class: 'btn small', disabled: !all.length, onclick: setAll(false, c) }, 'Disable all'),
          h('button', { class: 'btn small primary', disabled: !all.length, onclick: setAll(true, c) }, 'Enable all')),
        all.length ? grid : h('div', { class: 'hint', style: 'margin:4px 0 10px' }, 'Empty. Use the menu on any mod to move it here.')));
    }
    count.textContent = `${mods.filter((x) => x.enabled).length} of ${mods.length} enabled`;
  };
  draw();
  view.replaceChildren(
    h('h2', {}, 'Mods in this world'),
    h('p', { class: 'sub' }, 'The list shows what is switched on for the selected world (new worlds start with nothing on). Group mods into categories, e.g. "Survival", and switch a whole category on with one button. Changes are saved straight away.'),
    h('div', { class: 'row' }, worldSelect(renderMods), h('input', { type: 'text', placeholder: 'Search mods...', oninput: (e) => { filter = e.target.value.toLowerCase(); draw(); } }),
      h('span', { class: 'spacer' }), count),
    h('div', { class: 'row', style: 'margin-bottom:6px' },
      h('button', { class: 'btn small', onclick: () => newCatDialog(reload) }, '＋ New category'),
      h('button', { class: 'btn small', onclick: () => run(() => api.openModsFolder()) }, 'Open mods folder'),
      h('span', { class: 'spacer' }),
      h('button', { class: 'btn small', onclick: setAll(false) }, 'Disable all'), h('button', { class: 'btn small', onclick: setAll(true) }, 'Enable all')),
    mods.length ? body : h('div', { class: 'empty', style: 'margin-top:14px' }, 'No mods installed yet. Install ours in the Updates tab, or open the mods folder to add your own.'));
}

function newCatDialog(after) {
  const name = h('input', { type: 'text', placeholder: 'Survival', maxlength: '40' });
  const m = modal('New category', h('div', { class: 'field' }, h('label', {}, 'Name'), name),
    (close) => [h('button', { class: 'btn', onclick: close }, 'Cancel'),
      h('button', { class: 'btn primary', onclick: async () => { const r = await run(() => api.catAdd(name.value)); if (r) { close(); after(); } } }, 'Create')]);
  name.focus();
  name.addEventListener('keydown', (e) => { if (e.key === 'Enter') m.card.querySelector('.btn.primary').click(); });
}
function renameCatDialog(old, after) {
  const name = h('input', { type: 'text', value: old, maxlength: '40' });
  const m = modal('Rename category', h('div', { class: 'field' }, h('label', {}, 'Name'), name),
    (close) => [h('button', { class: 'btn', onclick: close }, 'Cancel'),
      h('button', { class: 'btn primary', onclick: async () => { const r = await run(() => api.catRename(old, name.value)); if (r !== undefined) { close(); after(); } } }, 'Rename')]);
  name.focus();
  name.addEventListener('keydown', (e) => { if (e.key === 'Enter') m.card.querySelector('.btn.primary').click(); });
}

// ---- Updates (our repo) -----------------------------------------------------------------------

const STATE_TEXT = { new: 'not installed', current: 'up to date', update: 'update available', modified: 'modified locally' };
const ago = (iso) => (iso ? new Date(iso).toLocaleString() : 'never');

async function renderUpdates() {
  const st = S.st;
  const info = await run(() => api.updatesStatus()) || { items: [], checked: '' };
  const placeholder = !st.cfg.repoUrl || st.cfg.repoUrl.includes('OWNER/REPO');
  const list = h('div', { class: 'grid wide' });
  const reload = async () => { await refresh(); renderUpdates(); };
  const install = async (names, force) => {
    const r = await run(() => api.updatesInstall(names, force), (x) => (x.done.length ? `Installed: ${x.done.join(', ')}` : 'Nothing to install') + (x.skipped.length ? `. Skipped (modified locally): ${x.skipped.join(', ')}` : ''));
    if (r) renderUpdates();
  };
  for (const i of info.items) {
    const ver = i.state === 'update' ? `${i.installedVersion || '?'} → ${i.version || '?'}` : (i.version || '');
    const tags = h('div', { class: 'tags' }, h('span', { class: 'tag ' + (i.state === 'current' ? 'data' : i.state === 'modified' ? 'bad' : '') }, STATE_TEXT[i.state]),
      ver ? h('span', { class: 'tag' }, 'v ' + ver) : null, i.why ? h('span', { class: 'tag bad' }, i.why) : null);
    let btn = null;
    if (i.state === 'new') btn = h('button', { class: 'btn small primary', onclick: () => install([i.name], false) }, 'Install');
    else if (i.state === 'update') btn = h('button', { class: 'btn small primary', onclick: () => install([i.name], false) }, 'Update');
    else if (i.state === 'modified') btn = h('button', { class: 'btn small danger', onclick: () => overwriteDialog(i, () => install([i.name], true)) }, 'Overwrite...');
    const rm = i.state !== 'new' && i.tracked ? h('button', { class: 'btn small', onclick: () => removeDialog(`mods/${i.name}`, i.name, i.state === 'modified', renderUpdates) }, 'Remove') : null;
    list.append(h('div', { class: 'mod' }, h('div', { class: 'mi' }, h('span', { class: 'mn' }, i.name), i.description ? h('div', { class: 'md' }, i.description) : null, tags), h('div', { class: 'btns' }, btn, rm)));
  }
  const todo = info.items.filter((i) => i.state === 'new' || i.state === 'update').length;
  view.replaceChildren(
    h('h2', {}, 'Updates'),
    h('p', { class: 'sub' }, 'Our mods from the project repository. The launcher only goes online when you press "Check for updates". Mods you changed yourself are never overwritten without asking.'),
    h('div', { class: 'card' },
      h('div', { class: 'hint' }, 'Repository'),
      h('div', { class: 'paths' }, placeholder ? '(not set - enter your GitHub repository in Settings)' : `${st.cfg.repoUrl}  ·  branch ${st.cfg.repoBranch || 'main'}`),
      h('div', { class: 'hint', style: 'margin-top:8px' }, `Last checked: ${ago(info.checked)}`)),
    h('div', { class: 'row' },
      h('button', { class: 'btn primary', disabled: placeholder || !st.install, onclick: async (e) => {
        e.target.disabled = true; toast('Checking...');
        const r = await run(() => api.updatesCheck(), 'Check finished');
        if (r) renderUpdates(); else e.target.disabled = false;
      } }, 'Check for updates'),
      h('button', { class: 'btn', disabled: !todo, onclick: () => install(null, false) }, todo ? `Install / update all (${todo})` : 'Nothing to update'),
      h('span', { class: 'spacer' })),
    info.items.length ? list : h('div', { class: 'empty', style: 'margin-top:14px' }, info.checked ? 'The repository has no mods.' : 'Press "Check for updates" to look at the repository.'));
}

function overwriteDialog(i, go) {
  modal(`Overwrite ${i.name}?`, h('p', { class: 'sub' }, `${i.name} was changed on this computer (${i.why}). Overwriting replaces your copy with the repository version. This cannot be undone.`),
    (close) => [h('button', { class: 'btn', onclick: close }, 'Cancel'), h('button', { class: 'btn danger', onclick: () => { close(); go(); } }, 'Overwrite')]);
}

// Removal of something the launcher installed; lists installed mods that need it.
async function removeDialog(key, name, modified, after) {
  const deps = key.startsWith('mods/') ? (await run(() => api.dependents(name))) || [] : [];
  modal(`Remove ${name}?`, h('div', {},
    h('p', { class: 'sub' }, `This deletes the ${name} folder from Luanti. Worlds that use it will no longer find it.`),
    modified ? h('p', { class: 'sub', style: 'color:var(--red)' }, 'It was changed on this computer since it was installed; those changes are lost.') : null,
    deps.length ? h('p', { class: 'sub', style: 'color:var(--red)' }, 'Installed mods that need it: ' + deps.join(', ')) : null),
  (close) => [h('button', { class: 'btn', onclick: close }, 'Cancel'),
    h('button', { class: 'btn danger', onclick: async () => { close(); const r = await run(() => api.uninstall(key, modified), `Removed ${name}`); if (r !== undefined) after(); } }, 'Remove')]);
}

// ---- ContentDB --------------------------------------------------------------------------------

const CDB = { q: '', type: 'mod', results: null, installed: [], checks: {}, missing: null };
const TYPE_DIR = { mod: 'mods', game: 'games', txp: 'textures' };
const TYPE_LABEL = { mod: 'Mods', game: 'Games', txp: 'Texture packs' };

async function renderContentDB() {
  const st = S.st;
  CDB.installed = st.install ? (await run(() => api.cdbInstalled())) || [] : [];
  const key = (p) => `${p.type}/${p.name}`;
  const have = new Map(CDB.installed.map((p) => [key(p), p]));
  const doInstall = async (p, force) => {
    const r = await run(() => api.cdbInstall({ author: p.author, name: p.name, type: p.type }, force), (x) => `Installed ${x.name} ${x.version}. Switch it on in the Mods tab.`);
    if (r) { delete CDB.checks[key(p)]; CDB.missing = r.missing.length ? { name: r.name, deps: r.missing } : null; renderContentDB(); }
  };
  const results = h('div', { class: 'grid wide' });
  for (const p of CDB.results || []) {
    const mine = have.get(key(p));
    results.append(h('div', { class: 'mod pkg' }, p.thumb ? h('img', { class: 'thumb', src: p.thumb, alt: '' }) : h('div', { class: 'thumb none' }),
      h('div', { class: 'mi' }, h('div', { class: 'mn' }, p.title), h('div', { class: 'by' }, `${p.author}/${p.name}`), p.description ? h('div', { class: 'md' }, p.description) : null),
      mine ? h('span', { class: 'tag data' }, 'installed') : h('button', { class: 'btn small primary', disabled: !st.install, onclick: () => doInstall(p, false) }, 'Install')));
  }
  const inst = h('div', { class: 'grid wide' });
  for (const p of CDB.installed) {
    const c = CDB.checks[key(p)];
    inst.append(h('div', { class: 'mod' }, h('div', { class: 'mi' }, h('div', { class: 'mn' }, p.name), h('div', { class: 'by' }, `${p.author} · ${p.version}`),
      h('div', { class: 'tags' }, p.modified ? h('span', { class: 'tag bad' }, 'modified locally') : null,
        c ? (c.error ? h('span', { class: 'tag bad' }, c.error) : h('span', { class: 'tag ' + (c.update ? '' : 'data') }, c.update ? `update: ${c.latest}` : 'up to date')) : null)),
      c && c.update ? (p.modified ? h('button', { class: 'btn small danger', onclick: () => overwriteDialog({ name: p.name, why: 'changed on disk since the launcher installed it' }, () => doInstall(p, true)) }, 'Overwrite...')
        : h('button', { class: 'btn small primary', onclick: () => doInstall(p, false) }, 'Update')) : null,
      h('button', { class: 'btn small', onclick: () => removeDialog(`${TYPE_DIR[p.type]}/${p.name}`, p.name, p.modified, renderContentDB) }, 'Remove')));
  }
  const q = h('input', { type: 'text', placeholder: 'Search ContentDB...', value: CDB.q, oninput: (e) => { CDB.q = e.target.value; } });
  const type = h('select', { onchange: (e) => { CDB.type = e.target.value; } }, Object.entries(TYPE_LABEL).map(([v, t]) => h('option', { value: v, selected: v === CDB.type }, t)));
  const doSearch = async () => { toast('Searching...'); const r = await run(() => api.cdbSearch(CDB.q, CDB.type)); if (r) { CDB.results = r; renderContentDB(); } };
  q.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSearch(); });
  view.replaceChildren(
    h('h2', {}, 'ContentDB'),
    h('p', { class: 'sub' }, 'Find and install mods, games and texture packs from content.luanti.org. The launcher only goes online when you press Search, Install or Check. Needed mods are not installed automatically: after an install the launcher lists what is missing and lets you search for each one.'),
    h('div', { class: 'row' }, q, type, h('button', { class: 'btn primary', disabled: !st.install, onclick: doSearch }, 'Search')),
    CDB.missing ? h('div', { class: 'card', style: 'margin-top:12px' }, h('div', { class: 'hint' }, `${CDB.missing.name} needs mods that are not installed. Search for each one:`),
      h('div', { class: 'row', style: 'margin-top:8px' }, CDB.missing.deps.map((d) => h('button', { class: 'btn small', onclick: () => { CDB.q = d; CDB.type = 'mod'; doSearch(); } }, d)))) : null,
    CDB.results ? (CDB.results.length ? results : h('div', { class: 'empty' }, 'Nothing found.')) : h('span'),
    h('h3', { style: 'margin:22px 0 8px' }, 'Installed from ContentDB'),
    h('div', { class: 'row' }, h('button', { class: 'btn small', disabled: !CDB.installed.length, onclick: async () => {
      toast('Checking...'); const r = await run(() => api.cdbCheck(), 'Check finished');
      if (r) { CDB.checks = Object.fromEntries(r.map((x) => [key(x), x])); renderContentDB(); } } }, 'Check for updates')),
    CDB.installed.length ? inst : h('div', { class: 'empty', style: 'margin-top:10px' }, 'Nothing installed from ContentDB yet.'));
}

async function renderFolders() {
  const st = S.st;
  if (!st.worlds.length && !st.install) return view.replaceChildren(h('div', { class: 'empty' }, 'No Luanti install found.'));
  const cards = [];
  for (const f of st.folders) {
    const files = await run(() => api.folder(S.world, f.id)) || [];
    const chips = h('div', { class: 'files' }, files.length ? files.map((n) => h('div', { class: 'chip' }, n,
      h('button', { title: 'Remove', onclick: async () => { await run(() => api.removeFile(S.world, f.id, n)); renderFolders(); } }, '✕'))) : h('span', { class: 'hint' }, 'Empty'));
    const add = async (paths) => {
      if (!paths.length) return;
      await run(() => api.addFiles(S.world, f.id, paths), (r) => `${r.copied} file(s) added${r.skipped ? `, ${r.skipped} skipped (wrong type; Wave Matrix plays .ogg only, convert MP3s first)` : ''}`);
      renderFolders();
    };
    const drop = h('div', { class: 'drop' }, `Drop ${f.hint} here`);
    drop.addEventListener('dragover', (e) => { e.preventDefault(); drop.classList.add('over'); });
    drop.addEventListener('dragleave', () => drop.classList.remove('over'));
    drop.addEventListener('drop', (e) => { e.preventDefault(); drop.classList.remove('over'); add([...e.dataTransfer.files].map((x) => api.pathOf(x))); });
    cards.push(h('div', { class: 'card' },
      h('div', { class: 'row' }, h('div', {}, h('h3', {}, f.label), h('div', { class: 'hint' }, `${files.length} file(s) · ${f.hint}`)), h('span', { class: 'spacer' }),
        h('button', { class: 'btn small', onclick: () => run(() => api.openFolder(S.world, f.id)) }, 'Open folder'),
        h('button', { class: 'btn small', onclick: async () => add(await run(() => api.pickFiles(f.id)) || []) }, 'Add files...')),
      drop, chips));
  }
  view.replaceChildren(h('h2', {}, 'Folders'),
    h('p', { class: 'sub' }, 'Music for Wave Matrix is shared by all worlds (a folder you add becomes a group); skins and capes belong to the selected world. Drag files in, or use Add files.'),
    worldSelect(renderFolders), h('div', { style: 'height:14px' }), ...cards);
}

async function renderSettings() {
  const st = S.st;
  const vals = { ...st.cfg };
  const field = (key, label, hint, browse) => {
    const input = h('input', { type: 'text', value: vals[key] || '', oninput: (e) => { vals[key] = e.target.value; } });
    return h('div', { class: 'field' }, h('label', {}, label), h('div', { class: 'hint' }, hint),
      h('div', { class: 'row' }, input, browse ? h('button', { class: 'btn small', onclick: async () => {
        const p = await run(() => api.pickFolder(label)); if (p) { vals[key] = p; input.value = p; } } }, 'Browse...') : null));
  };
  const inst = st.install;
  view.replaceChildren(h('h2', {}, 'Settings'),
    h('p', { class: 'sub' }, inst ? `Detected: ${inst.kind} (${inst.cmd.join(' ')})` : 'Luanti was not detected. Set the launch command or data folder below.'),
    field('dataDir', 'Luanti data folder', 'Leave empty to detect automatically.', true),
    field('command', 'Launch command', 'Leave empty to detect automatically (flatpak or luanti in PATH).', false),
    field('repoUrl', 'Project repository (GitHub)', 'Where the Updates tab looks for our mods: https://github.com/<owner>/<repo> (mods in its mods/ folder). Nothing is contacted until you press Check for updates.', false),
    field('repoBranch', 'Repository branch', 'Usually main.', false),
    h('div', { class: 'row', style: 'margin-bottom:14px' }, h('button', { class: 'btn small', onclick: () => run(() => api.openModsFolder()) }, 'Open mods folder')),
    h('div', { class: 'row' }, h('button', { class: 'btn primary', onclick: async () => {
      const ns = await run(() => api.saveSettings(vals), 'Saved'); if (ns) { S.st = ns; await refresh(); renderSettings(); } } }, 'Save settings'),
      h('span', { class: 'hint' }, 'Stored in ', h('span', { class: 'paths' }, st.configDir), ' (next to the launcher; nothing is written anywhere else).')));
}

const RENDER = { play: renderPlay, mods: renderMods, updates: renderUpdates, contentdb: renderContentDB, folders: renderFolders, settings: renderSettings };
async function show(tab) {
  S.tab = tab;
  for (const b of document.querySelectorAll('.tab')) b.classList.toggle('active', b.dataset.tab === tab);
  await refresh();
  await RENDER[tab]();
}
$('#tabs').addEventListener('click', (e) => { const b = e.target.closest('.tab'); if (b) show(b.dataset.tab); });
show('play');
// "Hello, are you there?": the ContentDB tab only appears when content.luanti.org answers (one tiny request at start).
api.cdbReachable().then((ok) => { if (ok) document.querySelector('[data-tab="contentdb"]').hidden = false; }).catch(() => {});
