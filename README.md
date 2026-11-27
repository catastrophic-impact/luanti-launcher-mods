# Luanti mods and launcher

A set of mods for Luanti games (built on Mineclonia) and a portable launcher to install and manage them.
Fan project; not affiliated with Mojang AB or Microsoft, and it contains no Minecraft assets.

## What is in here

### Mods (`mods/`)
Each folder is one mod with its own `mod.conf` and a `version` line. `uikit` is the shared UI library; every other mod depends on it.

| Mod | What it does |
| --- | --- |
| `uikit` | Shared dark UI theme and helpers for our screens. Players pick background, panels, text colour and size in `/uikit`, and can also style other mods' screens (including Mineclonia's inventory) with the same look. |
| `hq` | One place for mod screens (`/hq`): your own command shortcuts, quick time/weather buttons, a Creative on/off toggle (game mode plus fly and fast), village finder, and mini buttons in the inventory. |
| `tameful` | Tame almost any animal with a lead. Pets follow, stay, can be ridden, and are kept in a roster. |
| `populations` | Villagers become named men and women with skins, families, health and the will to fight back. At most six villagers crowd a bell at once and villagers keep some personal space. Skins are generated from Mineclonia's skin layers. |
| `identifiable` | A small panel naming the block, creature, player or item you look at, with health, harvest info, light level and more. Starts centred at the top of the screen. Hold Z to zoom. |
| `mobcrate` | Pack a mob into an item and let the same mob out somewhere else. |
| `nosleep` | Beds set your respawn point but you never sleep; the night has to be survived. |
| `conflictresolution` | PvP on/off and protection for tamed animals. |
| `peaceandquiet` | Hides advancement popups. |
| `wavematrix` | Your own music player: bundled tracks plus your own `.ogg` files, with a progress bar that also fills during the pause between songs. |
| `multiversatile` | Dimensions for Mineclonia: its Overworld, Nether and End plus new ones as bands of heights in the one map, with Minecraft-style height limits (no building past the top, death far out of bounds), per-player sky and light, travel with return points, and reusable areas for throwaway worlds. A library for other mods. |
| `dungeoneer` | Random castle dungeons built on demand in their own dimension: a portal and keys (tiers I-IV), monsters placed by hand, a boss with abilities, a sealed loot chest, and automatic clean-up. |
| `luanti_fixes` | Small fixes for upstream Mineclonia problems: a missing texture, and new players always start as the boy character. |

One plain-text wiki page per mod (features, commands, settings) is in `wiki/`.

### Launcher (`launcher/`)
The Luanti Launcher (Electron), portable: settings live in a `launcher-data` folder next to the program, never in your home folder.
- **Play**: start Luanti or a world; create (Default or Flat) and delete worlds. New worlds start with no mods on; you can start from one of your categories. A Creative mode checkbox next to Play is chosen at every start (saved in the world, and copied into Luanti's settings the way its own menu does, so it really takes effect).
- **Mods**: shows what is switched on for the selected world. Mods are grouped into categories (ours go into a built-in group, others into "Other"; make your own such as "Survival"). Each category has Enable all / Disable all. Switching a mod on also switches on what it needs. "Open mods folder" opens the folder where mods live.
- **Updates**: installs and updates our mods from this repository. Mods you changed yourself are never overwritten without asking.
- **ContentDB**: search, install, update and remove packages from content.luanti.org. The tab only appears if ContentDB answers a single small request at start. An always-on content filter hides and blocks packages with sexual or gender-ideology themes (the word list is in `launcher/src/filter.js`); there is no setting to turn it off.
- **Folders**: music for Wave Matrix (drag and drop) and per-world skin and cape folders.
- **Settings**: Luanti data folder, launch command, project repository and branch.

The launcher only goes online when you press a button (Check for updates, Search, Install), plus the one start-up check that decides whether the ContentDB tab is shown.

### Developer tooling
- `tools/lt`: the dev tool (sync into the Luanti data folder, run test mods against a real server and client, screenshots).
- `tools/make_villager_skins.py`: generates the villager skins (`generate`, or `preview OUT.png [boy|girl]`).
- `tests/`: test and probe mods.
- `patches/`: patch sets for upstream games (none today) and **`patches/MINECLONIA_CHANGES.md`**, the list of every place our mods wrap, override or depend on Mineclonia internals, with a checklist for after each upstream update. Keep it current.
- `tui_launcher/`: an older terminal launcher, not maintained.

## Using the mods
Copy the folders from `mods/` into your Luanti `mods` folder and enable them for a world, or use the launcher. The mods target Mineclonia on Luanti 5.10 or newer.

## Building: `install.sh`
`./install.sh` sets up the build environment and builds everything. It needs `distrobox` and `podman` (or docker) on the host.

```
./install.sh            # everything below
./install.sh setup      # only the box, tools and npm install
./install.sh build      # only tests + AppImage
./install.sh release    # only collect release/ from the last build
```

What it does:
1. **Box**: creates a distrobox called `luanti-box` (Ubuntu 22.04) with its **own home folder** `~/boxes/luanti-box`, so nothing is written to your real home. An existing box is reused. Override with `LUANTI_BOX=<name>` and `LUANTI_BOX_HOME=<dir>`.
2. **Tools**: installs the build libraries with apt inside the box and Node 20.18.1 into the box home (checked against the published sha256), then runs `npm install` in `launcher/`.
3. **Build**: runs the launcher tests and `npm run dist`, producing `launcher/dist/LuantiLauncher-<version>-x86_64.AppImage`.
4. **Release**: collects a portable `release/` folder with the AppImage, `mods/` (each mod in its own folder), `LICENSE`, `CREDITS.md` and a short `README.txt`. `release/` and `launcher/dist/` are not committed.

It is safe to run again. The AppImage is x86_64 Linux and needs libfuse2 on systems other than SteamOS.

Run the launcher from source instead: `cd launcher && npm install && npm start`.

## License
GPL-3.0-or-later, with exceptions: the music (all rights reserved, project-only), the villager skins and one texture (CC BY-SA, derived from Mineclonia's skin layers and textures) and MIT-licensed code from Twinsonian's mods. See `CREDITS.md` and `LICENSE`.
