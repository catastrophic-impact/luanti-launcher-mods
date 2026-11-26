local function log(s) core.log("action", "[BEES_HOME_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
-- record how far from the hive centre each bee was when it went in
local entered = {}
local orig_enter = bees.enter_hive
bees.enter_hive = function(obj, pos)
	local p = obj:get_pos(); local d = p and vector.distance(p, pos)
	local ok = orig_enter(obj, pos)
	if ok then entered[#entered + 1] = d end
	return ok
end
local function open_air(c, r, h) for x = -r, r do for y = 0, h do for z = -r, r do core.set_node(vector.offset(c, x, y, z), { name = y == 0 and "mcl_core:stone" or "air" }) end end end end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		local base = vector.offset(vector.round(player:get_pos()), 0, 30, 0)
		player:set_pos(vector.offset(base, 0, 3, 0)) -- keep blocks loaded
		core.after(1, function()
			local arena = vector.offset(base, 0, 0, 0)
			open_air(arena, 20, 14)
			local function release_to_go_home(o, hive, forced)
				local le = o:get_luaentity()
				le._hive = hive; le._out_since = core.get_gametime() - 1000; le._forage_for = 1 -- long overdue: heads home at once
				return le
			end

			-- A. open air, hive 9 nodes away: bee flies home and goes in at the hive face
			local hA = vector.offset(arena, 8, 2, 0); core.set_node(hA, { name = "mcl_beehives:beehive" })
			local bA = core.add_entity(vector.offset(arena, -1, 2, 0), "bees:bee"); release_to_go_home(bA, hA)

			-- B. bee in a closed stone box (no way out), hive outside: no path home -> backtracks, then gives up the hive, stays alive
			local boxc = vector.offset(arena, -12, 5, 12)
			for x = -3, 3 do for y = -3, 3 do for z = -3, 3 do
				local edge = math.abs(x) == 3 or math.abs(y) == 3 or math.abs(z) == 3
				core.set_node(vector.offset(boxc, x, y, z), { name = edge and "mcl_core:stone" or "air" })
			end end end
			local hB = vector.offset(arena, 12, 2, 12); core.set_node(hB, { name = "mcl_beehives:beehive" })
			local bB = core.add_entity(boxc, "bees:bee"); release_to_go_home(bB, hB)
			bB:get_luaentity()._crumbs = { vector.offset(boxc, 1, 0, 0), vector.offset(boxc, -1, 1, 0) } -- crumbs inside the box

			-- C. hive vanishes while the bee is heading home -> bee drops it (no error), stays alive
			local hC = vector.offset(arena, 10, 2, -12); core.set_node(hC, { name = "mcl_beehives:beehive" })
			local bC = core.add_entity(vector.offset(arena, -2, 2, -12), "bees:bee"); release_to_go_home(bC, hC)

			-- D. tamed bee: forgets its hive, does not go home, does not enter
			local hD = vector.offset(arena, 10, 2, -6); core.set_node(hD, { name = "mcl_beehives:beehive" })
			local bD = core.add_entity(vector.offset(arena, 4, 2, -6), "bees:bee"); local ld = release_to_go_home(bD, hD); ld.tamed = true

			-- E. homeless bee near a hive with room adopts it; a full hive is not adopted
			local hE = vector.offset(arena, -14, 2, -14); core.set_node(hE, { name = "mcl_beehives:beehive" })
			local bE = core.add_entity(vector.offset(arena, -10, 2, -14), "bees:bee")
			local hF = vector.offset(arena, -14, 2, -10); core.set_node(hF, { name = "mcl_beehives:beehive" }); for _ = 1, 5 do bees.hive_add(hF) end
			local bF = core.add_entity(vector.offset(arena, -14, 4, -9), "bees:bee") -- sits right next to the FULL hive

			-- F. leash: a bee 30 nodes from its hive heads home
			local hG = vector.offset(arena, 18, 2, 18); core.set_node(hG, { name = "mcl_beehives:beehive" })
			local bG = core.add_entity(vector.offset(arena, -18, 2, 18), "bees:bee"); local lg = bG:get_luaentity()
			lg._hive = hG; lg._out_since = core.get_gametime(); lg._forage_for = 9999 -- not overdue; only the leash can send it home

			local function probe(tag, o, hive)
				local le = o:get_luaentity(); local pos = o:get_pos()
				if not le or not pos then log("PROBE " .. tag .. " gone"); return end
				log(string.format("PROBE %s pos=%s dist=%.1f hive=%s home=%s tries=%s back=%s act=%s nav=%s crumbs=%s", tag, core.pos_to_string(pos, 0), vector.distance(pos, hive),
					tostring(le._hive and "set"), tostring(le.heading_home), tostring(le._home_tries), tostring(le._backtrack and "y"), tostring(le._active_activity), tostring(le:is_navigating() and "y"), tostring(le._crumbs and #le._crumbs)))
			end
			for i = 1, 6 do core.after(i * 10, function() probe("B", bB, hB); probe("C", bC, hC); probe("G", bG, hG); log("--") end) end
			core.after(6, function() core.set_node(hC, { name = "air" }) end)
			core.after(1, function() ld.tamed = true end)

			core.after(70, function()
				check("A: bee entered the hive (count 1, entity gone)", bees.hive_count(hA) == 1 and bA:get_pos() == nil, tostring(bees.hive_count(hA)))
				check("A: entered at the hive face (<= 1.4 from the centre)", entered[1] ~= nil and entered[1] <= 1.4, tostring(entered[1]))
				local le = bB:get_luaentity()
				check("B: trapped bee gave up hive B and does not re-adopt it", le and not (le._hive and vector.equals(le._hive, hB)) and not le.heading_home)
				check("B: trapped bee still alive, hive count unchanged", bB:get_pos() ~= nil and bees.hive_count(hB) == 0)
				local lc = bC:get_luaentity()
				check("C: bee dropped the vanished hive (did not keep it), lives", lc and not (lc._hive and vector.equals(lc._hive, hC)) and bC:get_pos() ~= nil)
				local ldd = bD:get_luaentity()
				check("D: tamed bee forgot its hive, did not enter", ldd and ldd._hive == nil and bees.hive_count(hD) == 0 and bD:get_pos() ~= nil)
				local lE = bE:get_luaentity()
				check("E: homeless bee adopted the nearby hive", lE and lE._hive and vector.equals(lE._hive, hE), lE and lE._hive and core.pos_to_string(lE._hive) or "nil")
				local lF = bF:get_luaentity()
				check("E: full hive not adopted", lF and not (lF._hive and vector.equals(lF._hive, hF)))
				local gp = bG:get_pos()
				check("G: leash: bee 36 nodes out got much closer to its hive or went in", gp == nil or vector.distance(gp, hG) < 24, gp and string.format("%.1f", vector.distance(gp, hG)) or "entered")
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end)
		end)
	end)
end)
