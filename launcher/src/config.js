'use strict';
const fs = require('fs');
const path = require('path');

const DEFAULTS = { dataDir: '', command: '', modsSource: '', gameSource: '', repoUrl: 'https://github.com/catastrophic-impact/luanti-launcher-mods', repoBranch: 'main' };

function load(dir) {
  try {
    return { ...DEFAULTS, ...JSON.parse(fs.readFileSync(path.join(dir, 'launcher.json'), 'utf8')) };
  } catch {
    return { ...DEFAULTS };
  }
}

function save(dir, cfg) {
  fs.writeFileSync(path.join(dir, 'launcher.json'), JSON.stringify(cfg, null, 2));
}

// The mods folder to sync from: the configured one, else a "mods" folder next to the launcher (portable setup).
function resolveModsSource(cfg, baseDir) {
  if (cfg.modsSource) return { path: cfg.modsSource, auto: false };
  const beside = path.join(baseDir, 'mods');
  try { if (fs.statSync(beside).isDirectory()) return { path: beside, auto: true }; } catch { /* none */ }
  return { path: '', auto: false };
}

module.exports = { load, save, DEFAULTS, resolveModsSource };
