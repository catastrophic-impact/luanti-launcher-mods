local function log(s) core.log("action", "[SWIM_PROBE_TEST] NOTE " .. s) end
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local gy = base.y - 1
		-- pool east of the start: x+3..x+12, 3 deep
		for x = 3, 12 do for z = -4, 4 do
			for d = 0, 2 do core.set_node({ x = base.x + x, y = gy - d, z = base.z + z }, { name = d == 2 and "mcl_core:stone" or "mcl_core:water_source" }) end
		end end
		local kind = "mobs_mc:pig"
		local obj = core.add_entity(base, kind)
		local ent = obj:get_luaentity()
		player:get_inventory():add_item("main", "tameful:lead 1")
		player:set_wielded_item(ItemStack("tameful:lead"))
		ent.on_rightclick(ent, player)
		deliver(player, "tameful:tame", { yes = "true" })
		core.close_formspec("tester", "tameful:tame")
		core.after(2, function()
			player:set_pos(vector.offset(obj:get_pos(), 1, 0, 0))
			log("ride -> " .. tostring(tameful.ride(ent, player)))
			tameful._ride_input = { forward = true }
			player:set_look_horizontal(-math.pi / 2)
			local t = 0
			local function tick()
				t = t + 1
				local p = obj:get_pos()
				log(string.format("t=%d x=%.1f y=%.2f (water top %.1f) driver=%s attached=%s jump=%s", t, p.x - base.x, p.y, gy + 0.5, tostring(ent.driver ~= nil), tostring(player:get_attach() ~= nil), tostring(tameful._ride_input.jump)))
				if t == 6 then tameful._ride_input = { forward = true, jump = true } end
				if t == 10 then tameful._ride_input = { forward = false, jump = false } end
				if t == 12 then tameful._ride_input = { forward = false, jump = true } end
				if t < 16 then return core.after(1, tick) end
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end
			tick()
		end)
	end)
end)
