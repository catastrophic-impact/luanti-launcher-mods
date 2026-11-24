'use strict';
const { contextBridge, ipcRenderer, webUtils } = require('electron');

const call = (name) => (...args) => ipcRenderer.invoke(name, ...args).then((r) => { if (!r.ok) throw new Error(r.error); return r.value; });

contextBridge.exposeInMainWorld('api', {
  state: call('state'),
  mods: call('mods'),
  setMod: call('setMod'),
  setAllMods: call('setAllMods'),
  folder: call('folder'),
  addFiles: call('addFiles'),
  removeFile: call('removeFile'),
  pickFiles: call('pickFiles'),
  pickFolder: call('pickFolder'),
  openFolder: call('openFolder'),
  sync: call('sync'),
  createWorld: call('createWorld'),
  deleteWorld: call('deleteWorld'),
  saveSettings: call('saveSettings'),
  launch: call('launch'),
  updatesStatus: call('updatesStatus'),
  updatesCheck: call('updatesCheck'),
  updatesInstall: call('updatesInstall'),
  cdbSearch: call('cdbSearch'),
  cdbInstalled: call('cdbInstalled'),
  cdbCheck: call('cdbCheck'),
  cdbInstall: call('cdbInstall'),
  uninstall: call('uninstall'),
  dependents: call('dependents'),
  pathOf: (file) => webUtils.getPathForFile(file), // dropped files
});
