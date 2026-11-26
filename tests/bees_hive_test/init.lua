local function log(s) core.log("action", "[BEES_HIVE_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function bees_near(p) local n = 0; for _, o in ipairs(core.get_objects_inside_radius(p, 6)) do local le = o:get_luaentity(); if le and le.name == "bees:bee" then n = n + 1 end end; return n end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		local base = vector.offset(vector.round(player:get_pos()), 0, 20, 0)
		-- clear a platform of air with a stone floor so bees have somewhere to exist
		for x = -8, 8 do for y = 0, 6 do for z = -8, 8 do core.set_node(vector.offset(base, x, y, z), { name = y == 0 and "mcl_core:stone" or "air" }) end end end
		local hp, np = vector.offset(base, 0, 1, 0), vector.offset(base, 4, 1, 0)
		core.set_node(hp, { name = "mcl_beehives:beehive" }); core.set_node(np, { name = "mcl_beehives:bee_nest" })

		-- 1. kinds
		check("kind beehive", bees.hive_kind(hp) == "beehive")
		check("kind nest", bees.hive_kind(np) == "nest")
		check("not a hive -> nil", bees.hive_kind(vector.offset(base, 0, 0, 0)) == nil and bees.hive_count(vector.offset(base, 0, 0, 0)) == nil)
		-- 2. starting population: player hive empty, natural nest 1-3 (several nests to see the range)
		check("crafted beehive starts empty", bees.hive_count(hp) == 0)
		local lo, hi = 99, 0
		for i = 1, 40 do
			local p = vector.offset(base, 6, 1, i % 7 - 3); core.set_node(p, { name = "mcl_beehives:bee_nest" })
			local n = bees.hive_count(p); lo, hi = math.min(lo, n), math.max(hi, n)
		end
		check("natural nests start with 1..3", lo >= 1 and hi <= 3, lo .. ".." .. hi)
		-- 3. add / take, cap 5
		local added = 0; for _ = 1, 8 do if bees.hive_add(hp) then added = added + 1 end end
		check("cap: 8 adds -> 5 succeed", added == 5 and bees.hive_count(hp) == 5, added .. " / " .. bees.hive_count(hp))
		local taken = 0; for _ = 1, 8 do if bees.hive_take(hp) then taken = taken + 1 end end
		check("empty: 8 takes -> 5 succeed, count 0", taken == 5 and bees.hive_count(hp) == 0)
		-- 4. leave: count down + exactly one entity
		bees.hive_add(hp); bees.hive_add(hp); bees.hive_add(hp)
		local before = bees_near(hp)
		local o = bees.leave_hive(hp)
		check("leave: returns a bee, count 3 -> 2, one new entity", o and bees.hive_count(hp) == 2 and bees_near(hp) == before + 1, tostring(bees.hive_count(hp)))
		-- 5. enter: count up + entity gone
		check("enter: true, count 2 -> 3, entity removed", bees.enter_hive(o, hp) == true and bees.hive_count(hp) == 3 and bees_near(hp) == before)
		check("entering twice does nothing (entity gone)", bees.enter_hive(o, hp) == false and bees.hive_count(hp) == 3)
		-- 6. full hive refuses; bee stays
		bees.hive_add(hp); bees.hive_add(hp)
		local b2 = core.add_entity(vector.offset(hp, 2, 0, 0), "bees:bee")
		check("full hive refuses, bee stays", bees.enter_hive(b2, hp) == false and bees.hive_count(hp) == 5 and b2:get_pos() ~= nil)
		-- 7. tamed bee ignores hives
		bees.hive_take(hp)
		b2:get_luaentity().tamed = true
		check("tamed bee does not enter", bees.enter_hive(b2, hp) == false and bees.hive_count(hp) == 4)
		b2:get_luaentity().tamed = false
		check("released bee enters again", bees.enter_hive(b2, hp) == true and bees.hive_count(hp) == 5)
		-- 8. leave from empty: nothing, no entity
		local ep = vector.offset(base, -4, 1, 0); core.set_node(ep, { name = "mcl_beehives:beehive" })
		check("leave from empty: nil, count 0", bees.leave_hive(ep) == nil and bees.hive_count(ep) == 0)
		-- 9. leave with no free space: count restored
		local sp = vector.offset(base, -4, 3, 0); core.set_node(sp, { name = "mcl_beehives:beehive" }); bees.hive_add(sp)
		for _, d in ipairs({ {1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0},{0,-1,0} }) do core.set_node(vector.offset(sp, d[1], d[2], d[3]), { name = "mcl_core:stone" }) end
		check("leave with no free space: nil, count unchanged", bees.leave_hive(sp) == nil and bees.hive_count(sp) == 1)
		-- 10. honey level change (node swap) keeps the count, both kinds
		core.swap_node(hp, { name = "mcl_beehives:beehive_3" })
		check("honey level swap keeps count (beehive)", bees.hive_count(hp) == 5 and bees.hive_kind(hp) == "beehive")
		bees.hive_add(np); local nc = bees.hive_count(np)
		core.swap_node(np, { name = "mcl_beehives:bee_nest_5" })
		check("honey level swap keeps count (nest)", bees.hive_count(np) == nc and bees.hive_kind(np) == "nest")
		-- 11. infotext shows the count
		check("infotext shows count", core.get_meta(hp):get_string("infotext"):find("5") ~= nil, core.get_meta(hp):get_string("infotext"))
		-- 12. /bees_why runs without error next to a bee that is heading home
		local wb = core.add_entity(vector.offset(hp, 2, 0, 0), "bees:bee"); local wl = wb:get_luaentity(); wl._hive = hp; wl._out_since = 0; wl._forage_for = 1
		player:set_pos(vector.offset(hp, 3, 0, 0))
		local ok, res, msg = pcall(core.registered_chatcommands["bees_why"].func, "tester", "")
		check("/bees_why runs and describes bee and hive", ok and res == true and msg:find("Hive beehive") ~= nil and msg:find("entrance node") ~= nil, ok and msg or tostring(res))
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
