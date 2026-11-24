local function log(s) core.log("action", "[SHOTS_TEST] " .. s) end
local function freeze(ent)
	ent.on_step = function() end
	ent.object:set_velocity(vector.zero())
	ent.object:set_acceleration(vector.zero())
	ent.object:set_animation({ x = 0, y = 79 }, 30, 0, true)
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true })
		local pos = vector.round(player:get_pos())
		-- (name, entity, distance behind the head, extra eye offset)
		local cases = {
			{ "head_villager_90", "mobs_mc:villager", 0.9, 0 },
			{ "head_villager_50", "mobs_mc:villager", 0.5, 0 },
			{ "head_villager_50_low", "mobs_mc:villager", 0.5, -0.5 },
			{ "head_piglin_50", "mobs_mc:piglin", 0.5, 0 },
			{ "head_zombie_50", "mobs_mc:zombie", 0.5, 0 },
		}
		local i = 0
		local function nxt()
			i = i + 1
			local c = cases[i]
			if not c then log("SHOTS_DONE"); return core.request_shutdown("done") end
			for _, o in ipairs(core.get_objects_inside_radius(pos, 10)) do if not o:is_player() then o:remove() end end
			core.after(0.5, function()
				local spot = vector.offset(pos, 6, 1, 0)
				local obj = core.add_entity(spot, c[2])
				core.after(1.5, function() -- let it land, then freeze, face away (-pi/2), verify
					local e = obj:get_luaentity()
					freeze(e)
					obj:set_yaw(-math.pi / 2)
					local vp = obj:get_pos()
					local eye = vector.offset(vp, -c[3], 1.62 + c[4], 0)
					player:set_pos(vector.offset(eye, 0, -1.62, 0))
					player:set_look_horizontal(-math.pi / 2)
					player:set_look_vertical(c[4] < 0 and -0.6 or 0)
					core.after(1.5, function()
						log(string.format("%s: yaw=%.2f dist=%.2f mesh=%s", c[1], obj:get_yaw() % (2 * math.pi), vector.distance(eye, vector.offset(vp, 0, 1.62, 0)), obj:get_properties().mesh))
						log("SHOT_READY " .. c[1])
						core.after(2.5, nxt)
					end)
				end)
			end)
		end
		nxt()
	end)
end)
