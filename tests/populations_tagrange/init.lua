local function log(s) core.log("action", "[SHOTS_TEST] " .. s) end
local DIST = { 10, 20, 30, 40, 50, 64 }
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		local pos = vector.round(player:get_pos())
		player:set_look_horizontal(-math.pi / 2)
		player:set_look_vertical(0.02)
		core.emerge_area(vector.offset(pos, 0, -10, -20), vector.offset(pos, 80, 20, 20))
		local made = {}
		core.after(3, function()
			for i, d in ipairs(DIST) do
				-- fan them out a little so tags do not overlap
				made[i] = core.add_entity(vector.offset(pos, d, 1, (i - 3.5) * d * 0.12), "mobs_mc:villager")
			end
			core.after(2, function()
				for i, obj in ipairs(made) do
					local e = obj and obj:get_luaentity()
					if e then
						e.on_step = function() end
						obj:set_velocity(vector.zero())
						e._pop.first, e._pop.last = "Dist", tostring(DIST[i])
						e._pop_tag = nil
						populations.refresh_tag(e)
						log(string.format("villager %d at %.0f blocks, tag %q", i, vector.distance(player:get_pos(), obj:get_pos()), obj:get_properties().nametag:gsub("\n", " | ")))
					else
						log("villager " .. i .. " failed to spawn")
					end
				end
				core.after(1.5, function() log("SHOT_READY tagrange") end)
				core.after(5, function() log("SHOTS_DONE"); core.request_shutdown("done") end)
			end)
		end)
	end)
end)
