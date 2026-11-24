local function log(s) core.log("action", "[TWP_TEST] NOTE " .. s) end
local function deliver(player, form, fields) for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local inv = player:get_inventory()
		local base = vector.round(player:get_pos())
		local gy = base.y - 1
		local C = vector.new(base.x + 12, gy, base.z) -- pool centre
		-- 9x9 stone box, 7x7 inside, water 3 deep
		for x = -4, 4 do for z = -4, 4 do for y = 1, 5 do
			local wall = math.abs(x) == 4 or math.abs(z) == 4
			local p = vector.offset(C, x, y, z)
			if wall then core.set_node(p, { name = "mcl_core:stone" })
			elseif y <= 3 then core.set_node(p, { name = "mcl_core:water_source" }) else core.set_node(p, { name = "air" }) end
		end end end
		local surface = C.y + 3.5
		local kinds = { "mobs_mc:skeleton_horse", "mobs_mc:zombie_horse", "mobs_mc:donkey", "mobs_mc:mule", "mobs_mc:llama" }
		local pets = {}
		for i, kind in ipairs(kinds) do
			local pos = vector.offset(C, -3 + ((i - 1) % 3) * 3, 2, -3 + math.floor((i - 1) / 3) * 3)
			local o = core.add_entity(pos, kind)
			if o then
				local e = o:get_luaentity()
				inv:add_item("main", "tameful:lead 1"); player:set_wielded_item(ItemStack("tameful:lead"))
				player:set_pos(vector.offset(pos, 2, 0, 0)) -- close enough to tame
				e.on_rightclick(e, player)
				deliver(player, "tameful:tame", { yes = "true" })
				core.close_formspec("tester", "tameful:tame")
				pets[#pets + 1] = { kind = kind, e = e }
			end
		end
		player:set_pos(vector.offset(C, 0, 5.5, 0)) -- player stands on the pool wall top... keep near
		local function sample(tag)
			local row = {}
			for _, p in ipairs(pets) do local pos = p.e.object:get_pos(); row[#row + 1] = p.kind:gsub("mobs_mc:", "") .. "=" .. (pos and string.format("%.2f", pos.y - C.y) or "?") end
			log(tag .. " (surface " .. (surface - C.y) .. ")  " .. table.concat(row, "  "))
		end
						core.after(9, function() sample("9s") end)
		core.after(11, function()
			log("SCENARIO_DONE"); core.request_shutdown("done")
		end)
	end)
end)
