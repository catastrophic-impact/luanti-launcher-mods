local function log(s) core.log("action", "[TAMEFUL_INV_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local h_o = core.add_entity(vector.offset(base, 3, 0, 0), "mobs_mc:horse")
		local h = h_o:get_luaentity()
		local pig_o = core.add_entity(vector.offset(base, 6, 0, 0), "mobs_mc:pig")
		local pig = pig_o:get_luaentity()
		for _, e in ipairs({ h, pig }) do
			player:get_inventory():add_item("main", "tameful:lead 1")
			player:set_wielded_item(ItemStack("tameful:lead"))
			e.on_rightclick(e, player)
			deliver(player, "tameful:tame", { yes = "true" })
		end
		core.close_formspec("tester", "tameful:tame")
		core.after(1.5, function()
			check("horse window has the Inventory button", tameful._pet_formspec("tester", h):find("inventory", 1, true) ~= nil)
			check("pig window has no Inventory button", tameful._pet_formspec("tester", pig):find(";inventory;", 1, true) == nil)
			tameful.show_pet("tester", h)
			player:set_pos(vector.offset(h_o:get_pos(), 1, 0, 0))
			deliver(player, "tameful:pet", { inventory = "x" })
			core.after(1, function()
				local fs = player:get_inventory_formspec()
				check("mounted, and the inventory is the horse's", h.driver == player and fs:find("detached:", 1, true) ~= nil, tostring(h.driver))
				h:detach(player, vector.new(0, 0.5, 0))
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end)
		end)
	end)
end)
