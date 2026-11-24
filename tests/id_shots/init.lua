local function log(s) core.log("action", "[ID_SHOTS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(16, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		mcl_gamemode.set_gamemode(player, "survival")
		local cfg = identifiable.get(player)
		cfg.light_mode = "both"; cfg.show_spawnable = true; cfg.show_player_health = true
		local base = vector.round(player:get_pos())
		local gy = base.y - 1
		for dx = -3, 12 do for dz = -3, 3 do for dy = 0, 4 do core.set_node({ x = base.x + dx, y = gy + 1 + dy, z = base.z + dz }, { name = "air" }) end core.set_node({ x = base.x + dx, y = gy, z = base.z + dz }, { name = "mcl_core:stone" }) end end
		player:get_inventory():set_list("main", {})
		local cases = {
			{ "wheat", function() core.set_node({ x = base.x + 2, y = gy + 2, z = base.z }, { name = "mcl_farming:wheat_5" }); core.set_node({ x = base.x + 2, y = gy + 1, z = base.z }, { name = "mcl_farming:soil_wet" }) end, "" },
			{ "obsidian", function() core.set_node({ x = base.x + 2, y = gy + 2, z = base.z }, { name = "mcl_core:obsidian" }) end, "mcl_tools:pick_iron" },
			{ "cow", function() local o = core.add_entity({ x = base.x + 3, y = gy + 2.0, z = base.z }, "mobs_mc:cow"); core.after(0.5, function() if o:is_valid() then o:get_luaentity().nametag = "Bessie"; o:get_luaentity():update_tag() end end) end, "" },
			{ "item", function() core.add_item({ x = base.x + 2, y = gy + 2.5, z = base.z }, "mcl_core:diamond 3") end, "" },
			{ "stone_floor", function() end, "" }, -- look down at the floor: light + spawnable
		}
		local i = 0
		local function nxt()
			i = i + 1
			local c = cases[i]
			if not c then log("SHOTS_DONE"); return core.request_shutdown("done") end
			for _, o in ipairs(core.get_objects_inside_radius(base, 8)) do if not o:is_player() then o:remove() end end
			for dx = 1, 4 do core.set_node({ x = base.x + dx, y = gy + 1, z = base.z }, { name = "air" }) end
			player:set_pos({ x = base.x, y = gy + 1, z = base.z })
			player:set_look_horizontal(-math.pi / 2)
			player:set_look_vertical(i == 5 and 0.9 or (i == 1 and 0.35 or 0.0))
			if c[3] ~= "" then player:set_wielded_item(ItemStack(c[3])) else player:set_wielded_item(ItemStack("")) end
			c[2]()
			core.after(2.0, function() log("SHOT_READY id_" .. c[1]); core.after(2.5, nxt) end)
		end
		nxt()
	end)
end)
