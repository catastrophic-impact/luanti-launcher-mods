# Every place our mods change or depend on Mineclonia internals

Keep this file up to date: whenever a mod wraps, replaces or relies on a Mineclonia function, field or file, add or edit its line here (same commit).
Mineclonia updates often. After `git -C reference/mineclonia pull` + `lt sync`, walk this list: for each line, check that the named thing still exists and still behaves as described,
then run that mod's test (`lt test <mod>_test`). Last reviewed against upstream commit: see `patches/BASE.txt` (upstream 15575d0, 2026-11-26).

We do NOT fork Mineclonia. There are no patch files today (`patches/mineclonia/` is empty). Everything below lives in our own mods and runs on top of stock Mineclonia.

Kinds: **wrap** = we replace a function/method and call the original; **override** = we replace it without calling the original; **field** = we change a field on a registered entity/def;
**hook** = we use an official register_* callback; **reads** = we only read its API; **asset** = a file we ship.

## luanti_fixes
- wrap: `mcl_core.basic_flood` and every node `on_flood` that equals it (no drops from water flooding young or unattended blocks). Reads `mcl_core.basic_flood`. Details under "Upstream bugs" below.
- (removed 2026-11-26) asset `textures/mcl_poplar_poplar_shelf.png`: upstream ships it since 15575d0.
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

## bees (step 1 mob, 2a hive counts, 2b homing, 2c angry bees / breaking / harvesting)
- reads: `mcl_mobs.register_mob` / `register_egg`, `mcl_mobs.mob_class` (`check_frightened`, `check_pace`), airborne mob fields (as in mobs_mc parrot). Later steps will read `mcl_beehives` (node names `beehive[_N]`, `bee_nest[_N]`, group `honey_level`) and `mcl_honey`, and will wrap `mcl_beehives` `dig_hive`/`honey_harvest` (bees on harvest, silk-touch carrying the count).
- reads (hive.lua): `mcl_beehives` node groups `beehive` (player-placed, starts empty) and `bee_nest` (natural, starts with 1-3 bees); both have levels 0-5 as separate node names (`mcl_beehives:beehive[_N]`, `bee_nest[_N]`), which the honey ABM swaps with `mcl_redstone.swap_node`. We store the bee count in node meta `bees:count` (+ `bees:init`); a node swap must keep meta (tested). Uses an LBM on `group:beehive`/`group:bee_nest` to set the start population, so trees that grow a nest (`mcl_trees.sapling_add_bee_nest`) and mapgen nests are covered. Breaks if upstream renames the groups or starts storing its own bee data.
- reads (brain.lua, 2b): `mob_class` navigation: `gopath` (false = no route), `go_to_stupidly`, `navigation_finished`, `is_navigating`, `cancel_navigation`, `check_timer`, and the AI-activity convention (an `ai_functions` entry returns an activity name; the field of that name holds its state, `run_ai_1`/`run_ai` in movement.lua). `mcl_weather.get_weather()` ("none" = fair) and `core.get_timeofday()` for the active hours (same 6000-18000 window as mcl_beehives' honey ABM). Bee state fields (`_hive`, `_out_since`, `_forage_for`, `_crumbs`, `heading_home`, `_avoid`) rely on mcl_mobs saving non-function fields. Tame check = `self.tamed` (set by mcl_mobs / tameful).
- override (hive.lua, 2c): `after_dig_node` of every node in group `beehive` / `bee_nest` is REPLACED by `bees.dig_hive` (upstream `dig_hive` in mcl_beehives/init.lua dealt a flat 10 \"sting\" damage and had a TODO for real bees). We keep its drops (beehive -> beehive item; nest -> nothing; silk touch -> the node, now with item meta `bees:count`; creative -> item to inventory) and release the bees angry instead. Breaks if upstream changes those drops or the nodes' groups.
- wrap (hive.lua, 2c): `on_rightclick` (`honey_harvest`) of the level-5 hive nodes. While it runs, `mcl_util.deal_damage` is swapped for a version that swallows reason type `sting` (upstream's flat 10 damage when no lit campfire is within 5 nodes below); if it fired, all bees come out angry. Restored in a pcall. Breaks if upstream stops using `deal_damage(..., {type = \"sting\"})` there or starts handling bees itself.
- wrap (anger.lua): `mob_class.receive_damage` for the bee only (hurt by a player -> the bee and bees within 16 nodes get angry). Reads `mcl_util.deal_damage`, `mcl_potions.give_effect_by_level(\"poison\", ...)`, `mcl_damage.finish_reason`, `mcl_enchanting.has_enchantment`, `awards.unlock(\"mcl:total_beelocation\")`, group `lit_campfire`.
- field: bees set `can_despawn = false` and `persistent = true` (mcl_mobs `despawn_allowed` in spawning.lua) so a beekeeper's bees never despawn.
- asset: bee model and textures from SaKeL's X Farming (CC BY-SA 4.0).

## multiversatile (dimensions)
- wrap: `mcl_worlds.y_to_layer` (and so `pos_to_dimension`): dimensions registered by our mods answer first (layer = y - ymin, own name); Mineclonia's three keep Mineclonia's own result.
  Breaks if mcl_worlds changes the signature.
- wrap: `mcl_worlds.is_in_void` (positions inside our own dimensions are not void: otherwise mcl_void_damage respawns/hurts players and removes entities there; mcl_death_drop uses it too).
- hook: `core.register_on_placenode` (limits.lua) reverts a player-placed node outside the dimension's build limits and shows the message via `mcl_title.set` (actionbar).
- reads/calls: `mcl_util.deal_damage` with damage type `out_of_world` (outofbounds.lua; bypasses invulnerability, so creative players die too). Mineclonia's own `mcl_void_damage` also acts below the three bands.
- reads: meta `night_vision` (set by mcl_potions night vision effect) in multiversatile look.lua.
- calls: `mcl_spawn.get_player_spawn_pos` / `get_world_spawn_pos` (travel.lua: where a player goes with no return point).
- calls: `mcl_weather.skycolor.update_sky_color` (look.lua, after leaving one of our dimensions so Mineclonia redraws sky/fog/sun/moon) and registers `mcl_worlds.register_on_dimension_change`.
- reads: `mcl_vars.mg_overworld_min`, `mapgen_edge_max`, `mg_overworld_max_official`, `mg_nether_min/max`, `mg_end_min/max/max_official` (the three registered bands use the same extents as `y_to_layer`).

## dungeoneer
- wrap: `mcl_mobs.mob_class.receive_damage` (mobs.lua): monsters of a dungeon (`_dg_run`) take no damage from other dungeon monsters (source, direct hit, or an arrow's `_source_object`) and damage is divided by the tier's toughness `_dg_hp`. Breaks if `receive_damage` changes signature or the reason fields (`source`, `direct`) change.
- reads/uses: mobs `mobs_mc:zombie|skeleton|husk|spider|stray|vindicator|witherskeleton`; sets entity fields `_dg_run`, `_dg_hp`, `persistent` (serialized by `get_staticdata`); relies on Mineclonia spawning only in its own dimension names (`mcl_worlds.pos_to_dimension` == level), so nothing spawns in the dungeon band by itself.
- reads: `mcl_core:stonebrick|obsidian|iron_ingot|gold_ingot|diamond|emerald`, `mcl_nether:netherite_ingot` (recipes), `mcl_sounds`, `mcl_title` (action bar).

## Upstream bugs and quirks we work around (the Mineclonia fixes list; keep new ones here, not in DEVNOTES)
Format: symptom, cause (as far as proven), our fix, where, how to check after an upstream update.
- **Water destroys generated plants and each drops an item; "Found duplicate GUID ... __builtin:item" (red chat, 2026-11-25).** Symptom: in a freshly generated lush cave ~35 plant items (azalea, big dripleaf, moss carpet, seeds) were stored in one mapblock of the dad_survival world; the engine later activated two of them twice (both GUIDs from the error were in the saved block) and Mineclonia deleted the copies. Cause (measured, tests/lush_probe: 21 000 lush nodes generated around that spot gave 560 item entities and ~1976 `add_item` calls, all from `mcl_core` `basic_flood` -> `drop_attached_node`): `_mcl_autogroup` gives nodes `on_flood = mcl_core.basic_flood`, which drops the node's items when liquid flows in; liquid settling after mapgen floods the plants the generator placed in/next to pools, with nobody around. Fix (wrap): `mods/luanti_fixes/init.lua` replaces `mcl_core.basic_flood` and every node's `on_flood` that pointed to it (at mods loaded): while the mapblock is < 120 s old, or no player is within 48 nodes, a flooding water node removes the plant without a drop. Result in the probe: 560 -> 44 items (the rest are within 48 nodes of the player = normal flooding); no duplicate-GUID line. Check upstream: `grep -n "basic_flood\|on_flood" reference/mineclonia/mods/CORE/_mcl_autogroup/init.lua reference/mineclonia/mods/ITEMS/mcl_core/functions.lua`. Test: `lt test lush_probe` (needs dev.conf with fixed_map_seed = 1174334992900360481 and mg_name = v7 temporarily; add `lush_probe_nofix = true` to compare). Not proven: that the engine double-activation is only triggered by these drops; `register_on_generated` does not seem to fire for Mineclonia's own generator, so the "young" part is only partly effective and the player-distance rule does most of the work.
- **Red client error "Could not load image mcl_poplar_poplar_shelf.png".** Fixed upstream in 15575d0; our texture was removed.
- **New players get a random skin.** Fix (hook): luanti_fixes `register_on_newplayer` sets the boy skin. See above.
- **Villagers walk onto each other at the bell; `hp_max` property does not read back.** Workarounds in populations (spacing.lua; `_pop_hp_max`). See the populations section above.
- **Chicken head folded into the body in a formspec `model[]` preview** (Mineclonia rotates the head bone in the world; a formspec cannot set bones). NOT fixed in Tameful's window; options are a 2D picture or a preview mesh with an upright head.
- Formspec quirk (engine, found while theming Mineclonia screens): closing one formspec and opening another in the same tick loses the second; close, then show 0.1 s later (HQ).

## Quick check after an upstream update
    grep -n "steve\|alex" reference/mineclonia/mods/PLAYER/mcl_skins/edit_skin.lua | head
    grep -n "function villager:\(schedule\|do_navigate\|socialize_at_bell\|gossip_and_trade\)" reference/mineclonia/mods/ENTITIES/mobs_mc/villager.lua
    grep -n "mob_class:\(replace_with\|is_valid_target\|driver_detached\|apply_driver_input\)" -r reference/mineclonia/mods/ENTITIES/mcl_mobs
    grep -n "function mcl_beds.on_rightclick\|mcl_beds.get_bed_top" -r reference/mineclonia/mods/ITEMS
    lt test lush_probe                               # luanti_fixes flood guard (see the note in the Upstream bugs entry)
    lt test populations_test --no-restart ; lt test tameful_test --no-restart ; lt test hq_test --no-restart   # one at a time
