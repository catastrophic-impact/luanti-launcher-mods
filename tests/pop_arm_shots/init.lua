local function log(s) core.log("action", "[SHOTS_TEST] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true })
		local pos = vector.round(player:get_pos())
		player:set_look_horizontal(-math.pi / 2); player:set_look_vertical(0.05)
		local function rot(v) return { rotation = { vec = vector.apply(vector.new(v, 0, 0), math.rad), absolute = false } } end
		local function mk(dz, f)
			local obj = core.add_entity(vector.offset(pos, 2.5, 1, dz), "mobs_mc:villager")
			local e = obj:get_luaentity()
			e.on_step = function() end; e.do_custom = function() end
			obj:set_velocity(vector.zero()); obj:set_acceleration(vector.zero())
			obj:set_yaw(0)
			obj:set_animation({ x = 16, y = 16 }, 0, 0, true)
			f(obj)
		end
		core.after(3, function()
			-- A: only the LEFT leg (right leg hidden), arms plain down: direction of the left leg at frame 16 (+28 deg in the b3d)
			mk(-1.5, function(o) o:set_bone_override("leg.right", { scale = { vec = vector.zero(), absolute = true } }); o:set_bone_override("arm.left", rot(-90)); o:set_bone_override("arm.right", rot(-90)) end)
			-- B: only the LEFT arm (right arm hidden) swung exactly as the walk code does for that frame: -90 - 0.9*28
			mk(1.5, function(o) o:set_bone_override("arm.right", { scale = { vec = vector.zero(), absolute = true } }); o:set_bone_override("arm.left", rot(-90 - 25)) end)
			log("created")
		end)
		core.after(8, function() log("SHOT_READY arms") end)
		core.after(20, function()
			for _, o in ipairs(core.get_objects_inside_radius(pos, 20)) do if not o:is_player() then o:remove() end end
			log("SHOTS_DONE"); core.request_shutdown("done")
		end)
	end)
end)
