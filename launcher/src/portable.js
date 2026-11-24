'use strict';
// Portable paths: everything (settings, Chromium cache, logs) lives in "launcher-data" NEXT TO the launcher, never in ~/.config.
const path = require('path');
const fs = require('fs');

function launcherDir(app) {
  if (process.env.LAUNCHER_HOME) return process.env.LAUNCHER_HOME; // tests / power users
  if (process.env.APPIMAGE) return path.dirname(process.env.APPIMAGE); // the .AppImage file's folder (not the temp mount)
  return path.dirname(app.getPath('exe')); // unpacked folder build, or electron during development
}

// Must run before app 'ready'. Returns the data folder. Throws (clear message) if it cannot be written.
function setup(app) {
  const dir = path.join(launcherDir(app), 'launcher-data');
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.accessSync(dir, fs.constants.W_OK);
  } catch (e) {
    throw new Error(`The launcher keeps its settings next to itself and cannot write to:\n${dir}\n\nMove the launcher to a folder you can write to.`);
  }
  app.setPath('userData', dir);
  app.setPath('sessionData', path.join(dir, 'session'));
  app.setPath('logs', path.join(dir, 'logs'));
  app.setPath('crashDumps', path.join(dir, 'crashes'));
  app.setAppLogsPath(path.join(dir, 'logs'));
  return dir;
}

module.exports = { setup, launcherDir };
