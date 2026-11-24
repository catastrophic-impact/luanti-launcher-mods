# Luanti mods and launcher

Mods for Luanti games (built on Mineclonia) and a portable launcher to manage them.

## Layout
- `mods/` - the mods. Each folder is one mod with its own `mod.conf` and a `version` line.
  - `uikit` is the shared UI library; every other mod depends on it.
  - `hq`, `tameful`, `populations`, `identifiable`, `mobcrate`, `nosleep`, `conflictresolution`, `peaceandquiet`, `wavematrix`, `luanti_fixes`.
- `launcher/` - the Luanti Launcher (Electron): per-world mod toggles, sync, music/skin folders, an Updates tab that
  reads `mods/` of this repository, and a ContentDB tab. It only goes online when you press a button.
- `tools/`, `tests/` - developer tooling and test mods (`tools/lt`).
- `patches/` - patch sets for upstream games (currently none).
- `tui_launcher/` - an older terminal launcher, not maintained.

## Using the mods
Copy the folders from `mods/` into your Luanti `mods` folder and enable them for a world, or use the launcher.
The mods target Mineclonia on Luanti 5.10 or newer.

## Launcher
```
cd launcher
npm install
npm start
```
`npm run dist` builds a portable AppImage. Settings are kept in a `launcher-data` folder next to the program.

## License
GPL-3.0-or-later, with exceptions (music, one texture, MIT code from Twinsonian's mods). See `CREDITS.md` and `LICENSE`.
