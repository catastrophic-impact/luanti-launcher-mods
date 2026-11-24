local function log(s) core.log("action", "[IDC_SHOTS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(16, function()
		local n = "tester"
		core.set_player_privs(n, { interact = true, shout = true, server = true })
		mcl_gamemode.set_gamemode(player, "survival")
		local cfg = identifiable.get(player)
		cfg.light_mode = "both"; cfg.show_spawnable = true; cfg.show_player_health = true
		local base = vector.round(player:get_pos())
		local gy = base.y - 1
		for dx = -3, 6 do for dz = -3, 3 do for dy = 0, 4 do core.set_node({ x = base.x + dx, y = gy + 1 + dy, z = base.z + dz }, { name = "air" }) end core.set_node({ x = base.x + dx, y = gy, z = base.z + dz }, { name = "mcl_core:stone" }) end end
		core.set_node({ x = base.x + 2, y = gy + 2, z = base.z }, { name = "mcl_core:obsidian" })
		player:set_pos({ x = base.x, y = gy + 1, z = base.z }); player:set_look_horizontal(-math.pi / 2); player:set_look_vertical(0)
		player:set_wielded_item(ItemStack("mcl_tools:pick_iron"))
		identifiable.dig_step = function() return 0.6 end -- force the breaking bar to 60%
		local st = identifiable.state(player)
		local steps = {
			function() core.close_formspec(n, "identifiable:cfg"); st.config = nil; cfg.hud_color = "white"; cfg.background_style = "dark" end,
			function() cfg.background_style = "advancement" end,
		}
		local names = { "hud_breaking" }
		local i = 0
		local function nxt()
			i = i + 1
			if not steps[i] then log("SHOTS_DONE"); return core.request_shutdown("done") end
			steps[i]()
			core.after(12, function() log("SHOT_READY " .. names[i]); core.after(12, nxt) end)
		end
		nxt()
	end)
end)
