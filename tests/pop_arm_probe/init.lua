local function log(s) core.log("action", "[POP_ARM_PROBE_TEST] NOTE " .. s) end
local function dump(tag, obj, ent)
	local w = ent.get_wielditem and ent:get_wielditem()
	local function bo(b) local o = obj:get_bone_override(b); return o and o.rotation and o.rotation.vec and string.format("%.0f,%.0f,%.0f abs=%s", math.deg(o.rotation.vec.x), math.deg(o.rotation.vec.y), math.deg(o.rotation.vec.z), tostring(o.rotation.absolute)) or "none" end
	local r, sp = obj:get_animation()
	log(string.format("%s: _pop=%s arms_down=%s wield=%s anim=%s frames=%s-%s | arm.left=%s arm.right=%s arm.left.001=%s arm.right.001=%s | pose=%s",
		tag, tostring(ent._pop), tostring(ent._pop_arms_down), w and w:to_string() or "nil", tostring(ent._current_animation),
		r and r.x or "?", r and r.y or "?", bo("arm.left"), bo("arm.right"), bo("arm.left.001"), bo("arm.right.001"), tostring(ent._arm_pose)))
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local obj = core.add_entity(vector.offset(base, 4, 0, 0), "mobs_mc:villager")
		local ent = obj:get_luaentity()
		local n = 0
		local function tick()
			n = n + 1
			dump("t" .. n * 3, obj, ent)
			if n < 6 then return core.after(3, tick) end
			-- reload from staticdata
			local sd = ent:get_staticdata()
			local pos = obj:get_pos(); obj:remove()
			local o2 = core.add_entity(pos, "mobs_mc:villager", sd)
			core.after(3, function()
				dump("RELOADED", o2, o2:get_luaentity())
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end)
		end
		core.after(2, tick)
	end)
end)
