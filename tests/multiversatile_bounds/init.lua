local function log(s) core.log("action", "[MV_BOUNDS_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
core.settings:set("enable_damage", "true") -- the dev world has damage off; with it off nobody can die (see the fallback test)
local deaths = {}
core.register_on_dieplayer(function(p) deaths[#deaths + 1] = p:get_player_name() end)
local function alive(p) return p:get_hp() > 0 end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(12, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true, creative = true })
		-- pure rule
		local ow = mv.get("overworld")
		check("rule: 63 past is fine, 65 past is out", not mv.out_of_bounds(ow, ow.build_max + 63) and mv.out_of_bounds(ow, ow.build_max + 65) and not mv.out_of_bounds(ow, ow.build_min - 63) and mv.out_of_bounds(ow, ow.build_min - 65))
		local cases = {
			{ "overworld above",  function() return ow.build_max + 66 end, true },
			{ "overworld 60 above (inside margin)", function() return ow.build_max + 60 end, false },
			{ "overworld below the bottom", function() return ow.build_min - 66 end, true },
			{ "nether above the roof", function() return mv.get("nether").build_max + 66 end, true },
			{ "nether inside margin", function() return mv.get("nether").build_max + 30 end, false },
			{ "nether below the floor (in the gap)", function() return mv.get("nether").build_min - 66 end, true },
			{ "end above", function() return mv.get("end").build_max + 66 end, true },
			{ "end below (in the gap)", function() return mv.get("end").build_min - 66 end, true },
		}
		local i = 0
		local function nxt()
			i = i + 1
			local c = cases[i]
			if not c then
				log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
				log("SCENARIO_DONE"); core.request_shutdown("done"); return
			end
			player:set_hp(20)
			-- place inside the band first so the last-dimension memory is right, then jump (as a teleport does)
			local y = c[2]()
			player:set_pos({ x = 0, y = y, z = 0 })
			local n0 = #deaths
			core.after(1.2, function()
				local died = #deaths > n0 or not alive(player)
				check(c[1] .. (c[3] and ": dies" or ": survives"), died == c[3], "y=" .. math.floor(y) .. " hp=" .. player:get_hp())
				nxt()
			end)
		end
		nxt()
	end)
end)
