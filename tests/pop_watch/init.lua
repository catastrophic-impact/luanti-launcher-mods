-- Probe: watch villagers of a COPY of the user's save with no client. Logs a timeline line per villager every STEP seconds.
-- Usage: world = copy of dadtester, `lt test pop_watch --keep --no-client --no-restart --timeout 200`.
local CENTER = vector.new(-3151, 205, -14034)
local STEP, TOTAL = 5, 90
local function log(s) core.log("action", "[POPW_TEST] " .. s) end

core.register_on_mods_loaded(function()
	core.register_on_joinplayer(function(player)
		if player:get_player_name() ~= "tester" then return end
		player:set_properties({ pointable = false })
		core.set_player_privs("tester", { fly = true, noclip = true, interact = true })
		core.after(2, function()
			local best = {}
			for _, v in pairs(mcl_villages.poi_heat) do if v.heat and v.heat > 0 then best[#best + 1] = v end end
			table.sort(best, function(a, b) return a.heat > b.heat end)
			for i = 1, math.min(5, #best) do log(string.format("HEAT %d section=%d,%d,%d heat=%s", i, best[i].x, best[i].y, best[i].z, tostring(best[i].heat))) end
			local c = best[1] and vector.new(best[1].x * 16 + 8, best[1].y * 16 + 8, best[1].z * 16 + 8) or CENTER
			CENTER = c
			player:set_pos(c)
			core.set_timeofday(0.40)
			core.after(3, function()
				for i = 1, 4 do
					local o = core.add_entity(vector.add(c, vector.new(i * 1.5, 1, 2)), "mobs_mc:villager", core.serialize({ child = true }))
					log("spawned kid " .. i .. " " .. tostring(o ~= nil))
				end
			end)
			log("tester placed; tod=" .. string.format("%.3f", core.get_timeofday()))
		end)
	end)
	local t = 0
	local function tick()
		t = t + STEP
		local vs, bell = {}, {}
		for _, ent in pairs(core.luaentities) do
			if ent.name == "mobs_mc:villager" and ent.object:get_pos() then vs[#vs + 1] = ent end
		end
		table.sort(vs, function(a, b) return (a._pop_custom or a.nametag or "") < (b._pop_custom or b.nametag or "") end)
		log(string.format("t=%d n=%d tod=%.3f", t, #vs, core.get_timeofday()))
		if t == STEP then
			local kinds, total = {}, 0
			for _, e in pairs(core.luaentities) do kinds[e.name] = (kinds[e.name] or 0) + 1; total = total + 1 end
			local ks = {} for k, c in pairs(kinds) do ks[#ks + 1] = k .. "=" .. c end
			local pl = core.get_player_by_name("tester")
			local pp = pl and pl:get_pos()
			log("ENTS total=" .. total .. " " .. table.concat(ks, " ") .. " tester=" .. (pp and core.pos_to_string(vector.round(pp)) or "none"))
			if pp then
				local bells = core.find_nodes_in_area(vector.subtract(pp, 60), vector.add(pp, 60), { "group:bell" })
				log("BELLS within 60: " .. #bells .. (bells[1] and (" first=" .. core.pos_to_string(bells[1])) or ""))
				local bn = core.get_node(vector.round(vector.subtract(pp, vector.new(0, 2, 0)))).name
				log("node below tester: " .. bn)
			end
		end
		for _, v in ipairs(vs) do
			local p = v.object:get_pos()
			local b = v._bell
			local nm = (v.nametag or "?"):gsub("\n.*", "")
			log(string.format("V %-18s %s pos=%d,%d,%d act=%s sch=%s dbell=%s job=%s hp=%s child=%s", nm, v.child and "kid" or "adt",
				math.floor(p.x), math.floor(p.y), math.floor(p.z), tostring(v._active_activity) .. (v._playing_tag and ("[tag" .. tostring(v._playing_tag == true and "-lead" or "-follow") .. "]") or ""), tostring(v._schedule_name or v._special_schedule),
				b and string.format("%.0f", vector.distance(p, b)) or "-", v._job_site and "y" or "-", tostring(math.floor(v.health or -1)), tostring(v.child)))
		end
		-- crowding: villager pairs closer than 1.2 blocks
		local close = 0
		for i = 1, #vs do for j = i + 1, #vs do
			if vector.distance(vs[i].object:get_pos(), vs[j].object:get_pos()) < 1.0 then close = close + 1 end
		end end
		local st = populations.spacing_stats
		local bn = {} for k, c in pairs(st.blocked_node) do bn[#bn + 1] = k .. "=" .. c end
		log("SPACING tried=" .. st.tried .. " moved=" .. st.moved .. " blocked: " .. table.concat(bn, " "))
		local nb = 0
		for _, v in ipairs(vs) do if v._bell and vector.distance(v.object:get_pos(), v._bell) <= 6 then nb = nb + 1 end end
		log("ATBELL within6=" .. nb)
		log("CROWD pairs<1.0=" .. close)
		if t >= TOTAL then log("SCENARIO_DONE"); core.request_shutdown("done") return end
		core.after(STEP, tick)
	end
	core.after(25, tick)
end)
