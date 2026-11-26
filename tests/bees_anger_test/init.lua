local function log(s) core.log("action", "[BEES_ANGER_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function all_bees() local t = {}; for _, o in pairs(core.luaentities) do if o.name == "bees:bee" and o.object:get_pos() then t[#t + 1] = o end end; return t end
local function clear_bees() for _, le in ipairs(all_bees()) do le.object:remove() end end
local function angry_count(name) local n = 0; for _, le in ipairs(all_bees()) do if le._anger_target == name then n = n + 1 end end; return n end
local function items_near(p, name) local n = 0; for _, o in ipairs(core.get_objects_inside_radius(p, 3)) do local le = o:get_luaentity(); if le and le.name == "__builtin:item" and ItemStack(le.itemstring):get_name() == name then n = n + 1 end end; return n end
local stings, poisons = {}, {}
local od = mcl_util.deal_damage
mcl_util.deal_damage = function(t, d, r) if r and r.type == "mob" then stings[#stings + 1] = d end return od(t, d, r) end
local og = mcl_potions.give_effect_by_level
mcl_potions.give_effect_by_level = function(n, o, l, dur, ...) if n == "poison" then poisons[#poisons + 1] = dur end return og(n, o, l, dur, ...) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		local me = "tester"
		core.set_player_privs(me, { interact = true, shout = true, server = true })
		mcl_gamemode.set_gamemode(player, "survival"); player:set_hp(20)
		local base = vector.offset(vector.round(player:get_pos()), 0, 30, 0)
		player:set_pos(vector.offset(base, 0, 2, 0))
		core.after(1, function()
			for x = -14, 14 do for y = 0, 10 do for z = -14, 14 do core.set_node(vector.offset(base, x, y, z), { name = y == 0 and "mcl_core:stone" or "air" }) end end end
			player:set_physics_override({ gravity = 0 }); player:set_pos(vector.offset(base, 0, 1.5, 0)) -- hold the player in place
			local function hive(p, name, n) core.set_node(p, { name = name }); core.get_meta(p):set_int("bees:init", 1); core.get_meta(p):set_int("bees:count", n or 0); core.get_meta(p):set_string("infotext", "") end
			local hp = vector.offset(base, 8, 1, 0)

			-- 1. creative players are never targeted
			mcl_gamemode.set_gamemode(player, "creative")
			local b0 = core.add_entity(vector.offset(base, 3, 2, 0), "bees:bee")
			check("1: creative player cannot be angered at", bees.anger(b0:get_luaentity(), player) == false)
			mcl_gamemode.set_gamemode(player, "survival"); player:set_hp(20); clear_bees()

			-- 2. hurting one bee angers it and its neighbours (not tamed, not far ones)
			local b1 = core.add_entity(vector.offset(base, -6, 2, 0), "bees:bee")
			local b2 = core.add_entity(vector.offset(base, -8, 2, 3), "bees:bee")
			local b3 = core.add_entity(vector.offset(base, 12, 2, 12), "bees:bee") -- ~30 away
			local reason = { type = "player", source = player, direct = player }; mcl_damage.finish_reason(reason)
			b1:get_luaentity():receive_damage(reason, 1)
			check("2: hurt bee and neighbour angry, far bee not", angry_count(me) == 2 and b3:get_luaentity()._angry_until == nil, tostring(angry_count(me)))
			clear_bees(); player:set_hp(20)

			-- 3. a sting: 2 damage + poison, then the bee dies. Wait first: the client may still be falling to the real ground, so spawn the bee next to where it ends up.
			bees.STING_DIE_AFTER = 3
			core.after(6, function()
			log("SETUP base=" .. core.pos_to_string(base) .. " player=" .. core.pos_to_string(player:get_pos(), 1) .. " node_below=" .. core.get_node(vector.offset(player:get_pos(), 0, -1, 0)).name .. " floor_at_base=" .. core.get_node(base).name)
			local b4 = core.add_entity(vector.offset(player:get_pos(), 10, 1, 0), "bees:bee"); bees.anger(b4:get_luaentity(), player)
			for i = 1, 8 do core.after(i * 3, function()
				local le, p = b4:get_luaentity(), b4:get_pos()
				if not le or not p then log("PROBE bee gone"); return end
				log(string.format("PROBE bee=%s player=%s t=%d dist=%.1f angry=%s target=%s act=%s nav=%s hp=%s die=%s", core.pos_to_string(p, 0), core.pos_to_string(player:get_pos(), 0), i * 3, vector.distance(p, player:get_pos()), tostring(le._angry_until), tostring(le._anger_target), tostring(le._active_activity), tostring(le:is_navigating()), player:get_hp(), tostring(le._sting_die_at)))
			end) end
			local ang_p0
			core.after(1.5, function() ang_p0 = b4:get_pos() end)
			core.after(2.5, function()
				local p1 = b4:get_pos(); local sp = p1 and ang_p0 and vector.distance(p1, ang_p0) or 0
				check("3: angry bee flies about twice as fast (~2 nodes/s)", sp > 1.7, string.format("%.2f nodes/s", sp))
				check("3: angry bee has red eyes", b4:get_properties().textures[2] == "bees_bee_features_angry.png", tostring(b4:get_properties().textures[2]))
			end)
			core.after(25, function()
				check("3: sting deals 2 damage (dev world has damage off, so HP itself cannot change)", #stings == 1 and stings[1] == 2, tostring(stings[1]))
				check("3: sting poisons for 10 s", #poisons == 1 and poisons[1] == 10, tostring(poisons[1]))
				check("3: stinging bee is gone a few seconds later", b4:get_pos() == nil)
				player:set_hp(20); clear_bees(); if mcl_potions.clear_effect then mcl_potions.clear_effect(player, "poison") end

				-- 4. break a hive (no smoke): all 4 bees out and angry, no flat 10 damage, beehive item dropped
				hive(hp, "mcl_beehives:beehive", 4)
				local def = core.registered_nodes["mcl_beehives:beehive"]
				def.after_dig_node(hp, { name = "mcl_beehives:beehive" }, { fields = { ["bees:count"] = "4" } }, player)
				core.set_node(hp, { name = "air" })
				check("4: broken hive: 4 bees angry at the digger", angry_count(me) == 4, tostring(angry_count(me)))
				check("4: no flat sting damage on break", player:get_hp() == 20, tostring(player:get_hp()))
				check("4: beehive item dropped", items_near(hp, "mcl_beehives:beehive") == 1)
				clear_bees()

				-- 5. break with a lit campfire below: bees out but calm
				local camp; for n, d in pairs(core.registered_nodes) do if (d.groups.lit_campfire or 0) > 0 then camp = n; break end end
				hive(hp, "mcl_beehives:beehive", 3); core.set_node(vector.offset(hp, 0, -1, 0), { name = camp })
				def.after_dig_node(hp, { name = "mcl_beehives:beehive" }, { fields = { ["bees:count"] = "3" } }, player)
				check("5: smoke: 3 bees out, none angry", #all_bees() == 3 and angry_count(me) == 0, #all_bees() .. "/" .. angry_count(me))
				clear_bees(); core.set_node(vector.offset(hp, 0, -1, 0), { name = "mcl_core:stone" }); core.set_node(hp, { name = "air" })

				-- 6. silk touch on a nest: bees stay in the item; placing restores the count
				local pick = ItemStack("mcl_tools:pick_iron"); mcl_enchanting.enchant(pick, "silk_touch", 1); player:set_wielded_item(pick)
				hive(hp, "mcl_beehives:bee_nest", 3)
				core.registered_nodes["mcl_beehives:bee_nest"].after_dig_node(hp, { name = "mcl_beehives:bee_nest" }, { fields = { ["bees:count"] = "3" } }, player)
				core.set_node(hp, { name = "air" })
				check("6: silk touch: no bees released", #all_bees() == 0)
				local dropped
				for _, o in ipairs(core.get_objects_inside_radius(hp, 3)) do local le = o:get_luaentity(); if le and le.name == "__builtin:item" and ItemStack(le.itemstring):get_name() == "mcl_beehives:bee_nest" then dropped = ItemStack(le.itemstring) end end
				check("6: nest item carries 3 bees", dropped and dropped:get_name() == "mcl_beehives:bee_nest" and dropped:get_meta():get_int("bees:count") == 3)
				if dropped then
					local p2 = vector.offset(hp, 0, 0, 3); core.set_node(p2, { name = "mcl_beehives:bee_nest" })
					for _, f in ipairs(core.registered_on_placenodes) do f(p2, { name = "mcl_beehives:bee_nest" }, player, { name = "air" }, dropped, {}) end
					check("6: placed nest has 3 bees again", bees.hive_count(p2) == 3, tostring(bees.hive_count(p2)))
				end
				player:set_wielded_item(ItemStack(""))

				-- 7. harvest honey without smoke: all bees out angry, bottle filled, no flat 10 damage
				local h5 = vector.offset(hp, 0, 0, -3)
				hive(h5, "mcl_beehives:beehive_5", 3)
				player:get_inventory():set_list("main", {}); local bottle = ItemStack("mcl_potions:glass_bottle"); player:set_wielded_item(bottle)
				local hdef = core.registered_nodes["mcl_beehives:beehive_5"]
				hdef.on_rightclick(h5, core.get_node(h5), player, player:get_wielded_item(), {})
				check("7: harvest: 3 bees out angry, hive empty", angry_count(me) == 3 and bees.hive_count(h5) == 0, angry_count(me) .. "/" .. tostring(bees.hive_count(h5)))
				check("7: got honey, no flat 10 damage", player:get_inventory():contains_item("main", "mcl_honey:honey_bottle") and player:get_hp() == 20, tostring(player:get_hp()))
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end)
			end) -- 6 s wait
		end)
	end)
end)
