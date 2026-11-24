local function log(s) core.log("action", "[SHOTS_TEST] " .. s) end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		local name = "tester"
		tameful.cfg.set("max_summoned", 0)
		player:get_inventory():add_item("main", "tameful:lead 10")
		player:set_wielded_item(ItemStack("tameful:lead"))
		local pos = vector.round(player:get_pos())
		for i, kind in ipairs({ "chicken", "pig", "cow", "sheep", "wolf", "horse" }) do
			local obj = core.add_entity(vector.offset(pos, 2 + i, 1, 0), "mobs_mc:" .. kind)
			local ent = obj and obj:get_luaentity()
			log(string.format("spawn %s: obj=%s ent=%s", kind, tostring(obj ~= nil), tostring(ent ~= nil)))
			player:set_wielded_item(ItemStack("tameful:lead")) -- the lead is used up by each taming
			if ent then
				ent.on_rightclick(ent, player)
				for _, f in ipairs(core.registered_on_player_receive_fields) do
					if f(player, "tameful:tame", { yes = "true" }) then break end
				end
				log(string.format("tamed %s: %s dist=%.1f", kind, tostring(ent.tamed),
					vector.distance(ent.object:get_pos(), player:get_pos())))
			end
		end
		core.set_player_privs(name, { interact = true, shout = true, server = true })
		local ids = tameful.sorted_ids(name)
		local i = 0
		local function show_next()
			i = i + 1
			if i > #ids then
				log("SHOTS_DONE")
				return core.after(2, core.request_shutdown, "done")
			end
			tameful._select(name, i)
			tameful.show_roster(name)
			core.after(4, function()
				local rec = tameful.roster[name][ids[i]]
				log("SHOT_READY " .. rec.kind:gsub("mobs_mc:", ""))
			end)
			core.after(9, show_next)
		end
		show_next()
	end)
end)
