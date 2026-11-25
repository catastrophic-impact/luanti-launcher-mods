# Every place our mods change or depend on Mineclonia internals

Keep this file up to date: whenever a mod wraps, replaces or relies on a Mineclonia function, field or file, add or edit its line here (same commit).
Mineclonia updates often. After `git -C reference/mineclonia pull` + `lt sync`, walk this list: for each line, check that the named thing still exists and still behaves as described,
then run that mod's test (`lt test <mod>_test`). Last reviewed against upstream commit: see `patches/BASE.txt` (0.124.1).

We do NOT fork Mineclonia. There are no patch files today (`patches/mineclonia/` is empty). Everything below lives in our own mods and runs on top of stock Mineclonia.

Kinds: **wrap** = we replace a function/method and call the original; **override** = we replace it without calling the original; **field** = we change a field on a registered entity/def;
**hook** = we use an official register_* callback; **reads** = we only read its API; **asset** = a file we ship.

## luanti_fixes
- asset: `textures/mcl_poplar_poplar_shelf.png`. Upstream references it but does not ship it (red "Could not load image"). Delete ours if upstream ships it. CC BY-SA 4.0 (derived from a Mineclonia texture).
- hook: `core.register_on_newplayer` sets meta `mcl_skins:skin` to `mcl_skins.steve` so new players start as the boy (upstream picks steve/alex at random in its own on_joinplayer).
  Reads `mcl_skins.steve`. Breaks if mcl_skins renames steve/alex or changes the meta key / skin table shape.

## populations (villagers as people)
- field: `core.registered_entities["mobs_mc:villager"]` and `["mobs_mc:villager_zombie"]`: mesh, visual_size, collisionbox, animation, head/armor fields, textures, nametag settings are copied from `mobs_mc:zombie`
  (`populations.borrow_zombie_body`, list of copied fields in zombie.lua). Breaks if the zombie def changes field names.
- field: `ent.set_animation_speed` taken from `mobs_mc:piglin`; `ent.animation.*` frame ranges edited.
- wrap: `ent.get_nametag` (name tag text), `ent.receive_damage`, `golem.receive_damage` / `on_activate`, villager `on_activate`, `ent.schedule` (inserts our `defend` AI function first).
- wrap: `mcl_util.get_object_name` (death messages and trade windows use the person's name).
- reads: villager fields `_active_activity`, `_schedule_name`, `child`, `health`, `_villager_sleeping`, `driver`; `mcl_mobs.mob_class` methods `heal_mob`, `get_properties` data. Relies on `mcl_mobs` serializing every non-function entity field.
- wrap (spacing.lua): `ent.wander_to_bell` (a bell takes at most 6 villagers; others are not sent) and `ent.schedule` (adds `ent.pace_around_village` to the SOCIALIZE schedule so the rest walk around the village). Relies on the schedule building its AI list from `self.<activity>` at schedule time, and on the fields `_bell`, `_wander_to_bell`, `_socializing_at_bell`, `_gossiping`, `_schedule_name`.
- uses `core.luaentities` scans every 0.5-1 s (spacing.lua, combat.lua) to nudge villagers apart (`set_pos`) and to apply health.
- gear: writes `self.armor_list` slots and wielded item fields on villagers.
- asset (generated, dev-time): `tools/make_villager_skins.py` reads Mineclonia's `mcl_skins/textures/*` layers + masks and `mcl_dyes` colour table and writes `mods/populations/textures/`. Re-run it only if the layers are renamed/removed upstream; it uses Mineclonia's default boy/girl layers (top_1, hair_1/2, eye_1/2, mouth_1, footwear_1, bottom_1, base_1); credit text lives in `mods/populations/textures/LICENSE.txt` (check `media_credits.txt` after updates).
- Known upstream behaviours we work around (see devnotes if present): villagers walk onto each other at the bell (no mob collision); `hp_max` property does not read back (we keep `_pop_hp_max`).

## tameful (pets)
- wrap: `mob_class.replace_with` (keeps the pet record when an animal turns into another kind), `mob_class.is_valid_target` (wild cats/ocelots ignore pets), `mob_class.driver_detached` (riding cleanup).
- override on tamable animal defs (riding.lua): `ent.should_drive` (back to `mob_class.should_drive`), `ent.post_apply_driver_input`, `ent.expel_underwater_drivers` (no-ops), `ent.apply_driver_input` (1-block step jump via `check_jump`), `ent.driver_attach_at`, `ent.drive_bonus`.
- field: `ent.ai_functions` rebuilt from `mob_class.sit_if_ordered`, `check_attack`, `follow_herd` + our `relax_home` and follow-owner; `ent.set_animation_speed` wrapped; `_targeting_rules` read.
- hook: `mcl_damage.register_on_damage`, `mcl_damage.register_modifier` (pet armor/attitude, damage rules); calls `mob_class.custom_attack`.
- reads: `mcl_mobs.registered_mobs`, entity fields `tamed`, `owner`, `order`, `acc_dir`, `acc_speed`, `_jump`, `movement_speed`; tame/owner fields are serialized by Mineclonia's get_staticdata.

## conflictresolution
- wrap: `mcl_tnt.ignite` (remember who lit TNT: `_cr_igniter` on the TNT entity).
- hook: `mcl_damage.register_modifier` (PvP / protect pets / protect own).

## nosleep (Wide Awake)
- wrap: `mcl_beds.on_rightclick` (set respawn instead of sleeping, except Nether/End and straw beds). Reads `mcl_beds.get_bed_top/get_bed_bottom`, `mcl_worlds.pos_to_dimension`, meta `mcl_beds:sleeping`, and the translated string "New respawn position set!" of mcl_beds (used as a chat filter: a changed upstream wording needs the new text).

## peaceandquiet
- hook: `awards.register_on_unlock` returning true to skip the popup/sound (relies on awards running these after prizes are given).

## hq
- wrap: `mcl_player.set_inventory_formspec` (appends the HQ button and mini buttons to priority-0 inventory formspecs; survival formspec is detected by its size, creative ends with a stray `p<page>`, so the first appended element is a throwaway box).
- reads: `mcl_inventory.update_inventory_formspec`, `mcl_gamemode.get_gamemode/set_gamemode` (creative toggle uses Mineclonia's per-player game mode = player meta `gamemode`, plus the fly and fast privs; NOT the `creative` priv), `mcl_potions.has_effect`, `mcl_biome_dispatch.locate_structure_near` and the village structure ids `mcl_villages:village_plains|desert|savannah|snowy|taiga`.

## identifiable
- reads: `mcl_gamemode.get_gamemode`, `mcl_mobs.registered_mobs[...].description`, `core.registered_entities`, mob spawner data. Also wraps nothing in Mineclonia.

## mobcrate
- reads: `core.registered_entities`, `mcl_mobs.registered_mobs[...]` (staticdata of a mob is stored in the crate item and restored with `core.add_entity`).

## wavematrix
- reads: `mcl_jukebox.registered_records` (music discs become the "Mineclonia discs" group). Plays with `core.sound_play` / `core.dynamic_add_media` (engine, not Mineclonia).

## uikit
- wrap (player formspec prepend): after `mcl_formspec_prepend` sets the game's prepend on join (we wait 0.5 s), uikit appends a full-window dark panel `background9` + button/field/label styles via `player:set_formspec_prepend`, so every formspec without `no_prepend[]` (Mineclonia's inventory, other mods) gets our look. Option "Other mods' screens" turns it off. Breaks if mcl_formspec_prepend sets the prepend again later or changes its elements (`gui_nonbg`, `gui_bg_img`).

## Quick check after an upstream update
    grep -rn "poplar_shelf" reference/mineclonia/mods                     # luanti_fixes asset still needed?
    grep -n "steve\|alex" reference/mineclonia/mods/PLAYER/mcl_skins/edit_skin.lua | head
    grep -n "function villager:\(schedule\|do_navigate\|socialize_at_bell\|gossip_and_trade\)" reference/mineclonia/mods/ENTITIES/mobs_mc/villager.lua
    grep -n "mob_class:\(replace_with\|is_valid_target\|driver_detached\|apply_driver_input\)" -r reference/mineclonia/mods/ENTITIES/mcl_mobs
    grep -n "function mcl_beds.on_rightclick\|mcl_beds.get_bed_top" -r reference/mineclonia/mods/ITEMS
    lt test populations_test --no-restart ; lt test tameful_test --no-restart ; lt test hq_test --no-restart   # one at a time
