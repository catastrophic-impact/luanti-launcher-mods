local function log(s) core.log("action", "[TAMEFUL_ADOPT_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		tameful.cfg.set("max_tames", 0)
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local function mk(kind, dx, tamed, child)
			local o = core.add_entity(vector.offset(base, dx, 0, 0), "mobs_mc:" .. kind)
			local e = o:get_luaentity()
			if tamed then e.tamed = true; e.owner = "tester" end
			if child then e.child = true end
			return o, e
		end
		local _, wolf = mk("wolf", 3, true)
		local _, cat = mk("cat", 5, true)
		local _, baby = mk("wolf", 7, true, true)
		local _, wild = mk("cow", 9, false)
		core.after(5, function()
			check("vanilla-tamed wolf adopted", wolf._tameful_id ~= nil and tameful.roster.tester[wolf._tameful_id] ~= nil)
			check("vanilla-tamed cat adopted", cat._tameful_id ~= nil)
			check("baby not adopted", baby._tameful_id == nil)
			check("wild cow not adopted", wild._tameful_id == nil)
			check("adopted wolf has stats", wolf._tameful_stats and wolf.damage == 6 and wolf.object:get_properties().hp_max == 30)
			local n = 0
			for _ in pairs(tameful.roster.tester) do n = n + 1 end
			check("exactly two records", n == 2, tostring(n))
			-- limit: max_tames 2 reached -> a third vanilla pet stays vanilla
			tameful.cfg.set("max_tames", 2)
			local _, horse = mk("horse", 11, true)
			core.after(5, function()
				check("max_tames stops adoption", horse._tameful_id == nil)
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end)
		end)
	end)
end)
