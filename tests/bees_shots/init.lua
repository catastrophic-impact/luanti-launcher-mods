-- Facing check: the bee is frozen in a known pose and photographed side-on. The camera looks along +z, so +x is to the right of the image.
-- Pose A: bee heads to +x  -> its head must be on the RIGHT.   Pose B: bee heads to -x -> head on the LEFT.
local function log(s) core.log("action", "[BEES_SHOTS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(16, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		player:set_physics_override({ gravity = 0 })
		local o = vector.offset(player:get_pos(), 0, 6, 8)
		player:set_pos(vector.offset(o, 0, -1.6, -2.2))
		player:set_look_horizontal(0); player:set_look_vertical(0)
		local b = core.add_entity(o, "bees:bee")
		local le = b:get_luaentity()
		le.ai_functions = {}; le.movement_goal = nil
		local function pose(name, heading_x)
			-- heading (+x) = yaw -pi/2, same convention as the AI: forward is (-sin yaw, cos yaw)
			-- object yaw y turns the model's -z (head) to (sin y, -cos y): head to +x needs y = pi/2
			b:set_yaw(heading_x > 0 and math.pi / 2 or -math.pi / 2)
			b:set_pos(o); b:set_velocity(vector.zero())
			log(name .. " yaw=" .. b:get_yaw() .. " rotate=" .. tostring(le.rotate))
		end
		pose("A_head_to_plus_x", 1)
		core.after(2, function() log("SHOT_READY bee_poseA")
			core.after(7, function()
				pose("B_head_to_minus_x", -1)
				core.after(2, function() log("SHOT_READY bee_poseB")
					core.after(7, function() log("SHOTS_DONE"); core.request_shutdown("done") end)
				end)
			end)
		end)
	end)
end)
