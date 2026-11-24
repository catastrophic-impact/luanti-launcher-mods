local function log(s) core.log("action", "[SHOTS_TEST] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		local pos = vector.round(player:get_pos())
		player:set_look_horizontal(-math.pi / 2)
		player:set_look_vertical(0.12)
		local jobs = { "armorer", nil, "cartographer", "butcher" }
		local made = {}
		for i, dz in ipairs({ -3, -1, 1, 3 }) do
			local obj = core.add_entity(vector.offset(pos, 4, 1, dz * 1.1), "mobs_mc:villager")
			made[i] = obj
		end
		core.after(1.5, function()
			for i, obj in ipairs(made) do
				local e = obj:get_luaentity()
				if jobs[i] then e:set_profession(jobs[i]) end
				if i == 2 then e._pop.first, e._pop.last = "Al", "Wu" end
				if i == 4 then e.health = 7 end
				e.on_step = function() end
				obj:set_velocity(vector.zero()); obj:set_yaw(math.pi / 2)
				e._pop_tag = nil
				populations.refresh_tag(e)
				log(string.format("tag %d: %q", i, obj:get_properties().nametag))
			end
			core.after(1, function() log("SHOT_READY tags") end)
			core.after(4, function() log("SHOTS_DONE"); core.request_shutdown("done") end)
		end)
	end)
end)
