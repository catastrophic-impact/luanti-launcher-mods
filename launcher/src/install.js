'use strict';
// Finds how to run Luanti and where its user data lives (flatpak, native, or a custom command).
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

function which(cmd) {
  for (const d of (process.env.PATH || '').split(':')) {
    const p = path.join(d, cmd);
    try { fs.accessSync(p, fs.constants.X_OK); return p; } catch { /* next */ }
  }
  return null;
}

function splitCommand(s) {
  return s.match(/"[^"]*"|\S+/g)?.map((t) => t.replace(/^"|"$/g, '')) || [];
}

function detect(cfg) {
  const home = os.homedir();
  let inst = null;
  if (cfg.command) {
    inst = { kind: 'custom', cmd: splitCommand(cfg.command), dataDir: '' };
  } else {
    const fp = which('flatpak');
    if (fp && spawnSync(fp, ['info', 'org.luanti.luanti'], { stdio: 'ignore' }).status === 0) {
      inst = { kind: 'flatpak', cmd: [fp, 'run', 'org.luanti.luanti'], dataDir: path.join(home, '.var/app/org.luanti.luanti/.minetest') };
    }
    if (!inst) {
      for (const n of ['luanti', 'minetest']) {
        const p = which(n);
        if (p) { inst = { kind: 'native', cmd: [p], dataDir: '' }; break; }
      }
    }
  }
  if (!inst) return null;
  if (cfg.dataDir) inst.dataDir = cfg.dataDir;
  if (!inst.dataDir) {
    const cands = ['.minetest', '.luanti', '.local/share/luanti'].map((d) => path.join(home, d));
    inst.dataDir = cands.find((d) => fs.existsSync(d)) || cands[0];
  }
  return inst;
}

module.exports = { detect, splitCommand };
