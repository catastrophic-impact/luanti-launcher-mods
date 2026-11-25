# Patches (Mineclonia and Luanti)

Two patch sets use the same workflow: `patches/mineclonia/` and `patches/luanti/`, each against its pristine clone in `reference/<project>`.
Add the project name to the commands below (default mineclonia): `lt patchwork luanti`, `lt mkpatch <name> luanti`, `lt upstream luanti`.
BASE: `patches/BASE.txt` (mineclonia), `patches/luanti/BASE.txt` (luanti). After pulling upstream run `lt upstream <project>`: it lists changed upstream files and the ones our patches touch (conflict candidates).
Luanti rules: new code in NEW files, hooks in existing files stay tiny, every feature behind a setting that defaults to off. Reference clone: tag 5.18.0.

## Mineclonia

Rule of thumb, in order of preference:
1. **Wrap it from our own mod** (as Tameful/Populations do). Survives upstream updates.
2. **Ship a missing asset in `mods/luanti_fixes`** (textures are global; no patch needed).
3. **Patch Mineclonia** only when 1 and 2 cannot work. Patches live here as plain `-p1` diffs.

`reference/mineclonia` is a pristine git clone: never edit it. `lt sync` copies it and applies `patches/mineclonia/*.patch` in name order.
`patches/BASE.txt` = the upstream commit the patches were last checked against; `lt sync` warns when `reference/mineclonia` moved.

## Make a patch
    lt patchwork            # tmp/mc_work = pristine + existing patches (tmp/mc_base = untouched copy)
    ...edit files under tmp/mc_work...
    lt mkpatch short-name   # writes patches/mineclonia/NNNN-short-name.patch
Each patch file starts with a comment-free diff; describe WHY in the list below.

## Update Mineclonia upstream
    git -C reference/mineclonia pull
    lt sync                 # a failing patch is named; fix it with lt patchwork (apply the others, redo the failed change), delete the old one, lt mkpatch again
When all patches apply and tests pass, `BASE.txt` is refreshed by the next `lt mkpatch` (or write the new HEAD by hand).

The complete list of everything our mods wrap, override or depend on in Mineclonia (and what to re-check after an upstream update) is **MINECLONIA_CHANGES.md** in this folder: keep it current.

## Patch list (why each exists)
(none yet)

## Fixes that are NOT patches (live in our own mods, so a Mineclonia update does not undo them)
- `mods/luanti_fixes/textures/mcl_poplar_poplar_shelf.png`: upstream (checked at BASE 238f5bc) references this texture but does not ship it, which prints a red
  "Could not load image" error at the top of the client. After every upstream update: `grep -rn poplar_shelf reference/mineclonia/mods` and look for the file; if upstream ships it,
  delete ours. If upstream ever ships the same file name, nothing breaks (same global name); just remove ours to avoid the duplicate.
  Any new red "Could not load image" line after an update = a new missing texture: add it to luanti_fixes the same way (tools/pnglib.py can recolor a similar texture).
