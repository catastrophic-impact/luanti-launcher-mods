local function log(s) core.log("action", "[DGPS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(16, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true })
		local o = { x = 10, y = 9, z = 10 } -- flat dev world ground is around y=5..8: ring above the grass
		core.emerge_area(vector.offset(o, -6, -3, -8), vector.offset(o, 6, 6, 6), function(_, _, rem)
			if rem > 0 then return end
			for x = -5, 6 do for y = -1, 6 do for z = -8, 4 do core.set_node(vector.new(o.x + x, o.y + y, o.z + z), { name = "air" }) end end end
			for x = -5, 6 do for z = -8, 4 do core.set_node(vector.new(o.x + x, o.y - 1, o.z + z), { name = "mcl_core:stone" }) end end
			for i = -1, 2 do for j = -1, 2 do
				local corner = (i == -1 or i == 2) and (j == -1 or j == 2); local opening = i >= 0 and i <= 1 and j >= 0 and j <= 1
				if not corner and not opening then core.set_node(vector.new(o.x + i, o.y + j, o.z), { name = "dungeoneer:frame" }) end
			end end
			dungeoneer.use_key(player, ItemStack("dungeoneer:key_2"), vector.new(o.x - 1, o.y, o.z), 2)
			player:set_pos({ x = o.x + 0.5, y = o.y, z = o.z - 4 }); player:set_look_horizontal(0); player:set_look_vertical(0.15)
			core.after(8, function()
				log("SHOT_READY portal_lit")
				core.after(14, function()
					player:set_pos({ x = o.x + 0.5, y = o.y, z = o.z - 0.2 })
					core.after(6, function()
						log("SHOT_READY portal_window")
						core.after(14, function() log("SHOTS_DONE"); core.request_shutdown("done") end)
					end)
				end)
			end)
		end)
	end)
end)
