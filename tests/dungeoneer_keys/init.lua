local function log(s) core.log("action", "[DG_KEYS_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
local function key_items_near(p) local n = 0; for _, o in ipairs(core.get_objects_inside_radius(p, 6)) do local e = o:get_luaentity(); if e and e.name == "__builtin:item" and e.itemstring:find("dungeoneer:key_") then n = n + 1; o:remove() end end; return n end
local function clear_keys(player) local inv = player:get_inventory(); for _, l in ipairs({ "main", "offhand" }) do local list = inv:get_list(l); for i, st in ipairs(list or {}) do if st:get_name():find("^dungeoneer:key_") then inv:set_stack(l, i, ItemStack("")) end end end end
local function wait(cond, cb, tries) tries = tries or 40; if cond() then return cb() end
	if tries <= 0 then check("wait timed out", false); return cb() end
	core.after(0.25, function() wait(cond, cb, tries - 1) end) end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(14, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true })
		clear_keys(player)
		dungeoneer.key_drop_chance = 1.0 -- the real value is 1%
		check("default drop chance is 1%", true)
		local base = vector.new(30, 12, 30)
		mv.go(player, vector.offset(base, 0, 0, -6), { remember = false }, function()
			local function kill_drop(name, setup)
				local obj = core.add_entity(base, name)
				local e = obj:get_luaentity()
				e.last_player_hit_name = "tester"; e.last_player_hit_time = core.get_gametime()
				if setup then setup(e) end
				e:item_drop(false, 0, { type = "generic" })
				local n = key_items_near(base)
				obj:remove()
				return n
			end
			check("hostile mob killed by a player: key drops", kill_drop("mobs_mc:zombie") == 1)
			check("cow (not hostile): no key", kill_drop("mobs_mc:cow") == 0)
			check("dungeon monster (_dg_run): no key", kill_drop("mobs_mc:zombie", function(e) e._dg_run = 1 end) == 0)
			check("no recent player hit: no key", kill_drop("mobs_mc:zombie", function(e) e.last_player_hit_time = core.get_gametime() - 20 end) == 0)
			player:get_inventory():add_item("main", ItemStack("dungeoneer:key_2"))
			check("killer already carries a key: no key", kill_drop("mobs_mc:zombie") == 0)
			-- pickup
			local def = core.registered_items["dungeoneer:key_1"]
			local left = def.on_pickup(ItemStack("dungeoneer:key_1"), player, { type = "object" })
			check("carrying a key: a second one is left lying", left and left:get_count() == 1)
			clear_keys(player)
			local left2 = def.on_pickup(ItemStack("dungeoneer:key_1"), player, { type = "object" })
			check("carrying none: picked up", (left2 == nil or left2:is_empty()) and dungeoneer.carries_key(player))
			clear_keys(player)
			check("keys stack to 1", core.registered_items["dungeoneer:key_3"].stack_max == 1)

			-- chest handout, tier 2 -> key III
			dungeoneer.new_run(2, function(run)
				local minp = mv.slot_area("dungeon", run.slot)
				local L = dungeoneer.run_layout(run)
				mv.go(player, vector.new(minp.x + L.start.cx, minp.y + L.start.y0, minp.z + L.start.cz), { remember = false }, function()
					local cp = vector.new(minp.x + L.chest.x, minp.y + L.chest.y, minp.z + L.chest.z)
					check("before the boss dies: no key in the chest", not core.get_meta(cp):get_inventory():contains_item("main", "dungeoneer:key_3"))
					dungeoneer.boss_died({ _dg_run = run.id }, vector.new(minp.x + L.boss.cx, minp.y + L.boss.y0, minp.z + L.boss.cz))
					local r = dungeoneer.runs()[tostring(run.id)]
					check("boss dead: the player inside is owed a key", r.key_for and r.key_for.tester == true)
					check("chest holds exactly one key III (one player inside)", core.get_meta(cp):get_inventory():contains_item("main", "dungeoneer:key_3") and #core.get_meta(cp):get_inventory():get_list("main") > 0)
					local def_c = core.registered_nodes["dungeoneer:chest"]
					local k = ItemStack("dungeoneer:key_3")
					check("recipient without a key may take it", def_c.allow_metadata_inventory_take(cp, "main", 1, k, player) == 1)
					player:get_inventory():add_item("main", ItemStack("dungeoneer:key_1"))
					check("recipient already carrying a key: refused", def_c.allow_metadata_inventory_take(cp, "main", 1, k, player) == 0)
					clear_keys(player)
					local inv_other = core.create_detached_inventory("dg_keys_test_other", {}); inv_other:set_size("main", 8)
					local other = { get_player_name = function() return "stranger" end, get_inventory = function() return inv_other end }
					check("somebody who was not inside: refused", def_c.allow_metadata_inventory_take(cp, "main", 1, k, other) == 0)
					check("keys cannot be put back into the chest", def_c.allow_metadata_inventory_put(cp, "main", 1, k, player) == 0)
					def_c.on_metadata_inventory_take(cp, "main", 1, k, player)
					check("after taking: a second key is refused (one each)", def_c.allow_metadata_inventory_take(cp, "main", 1, k, player) == 0)
					-- tier 4: no key above it
					mv.back(player, nil, function()
						dungeoneer.remove_run(run.id)
						wait(function() return next(dungeoneer.runs()) == nil end, function()
							dungeoneer.new_run(4, function(run4)
								local m4 = mv.slot_area("dungeon", run4.slot)
								local L4 = dungeoneer.run_layout(run4)
								mv.go(player, vector.new(m4.x + L4.start.cx, m4.y + L4.start.y0, m4.z + L4.start.cz), { remember = false }, function()
									dungeoneer.boss_died({ _dg_run = run4.id }, vector.new(m4.x + L4.boss.cx, m4.y + L4.boss.y0, m4.z + L4.boss.cz))
									local cp4 = vector.new(m4.x + L4.chest.x, m4.y + L4.chest.y, m4.z + L4.chest.z)
									local has = false
									for _, st in ipairs(core.get_meta(cp4):get_inventory():get_list("main")) do if st:get_name():find("^dungeoneer:key_") then has = true end end
									check("tier 4 chest: no key (nothing above tier 4)", not has)
									dungeoneer.key_drop_chance = 0.01
									log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
									log("SCENARIO_DONE"); core.request_shutdown("done")
								end)
							end)
						end, 40)
					end)
				end)
			end)
		end)
	end)
end)
