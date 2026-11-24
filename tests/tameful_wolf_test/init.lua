local function log(s) core.log("action", "[TAMEFUL_WOLF_TEST] " .. s) end
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
		local w_o = core.add_entity(vector.offset(base, 2, 0, 0), "mobs_mc:wolf")
		local w = w_o:get_luaentity()
		player:get_inventory():add_item("main", "tameful:lead 1")
		player:set_wielded_item(ItemStack("tameful:lead"))
		w.on_rightclick(w, player)
		deliver(player, "tameful:tame", { yes = "true" })
		core.close_formspec("tester", "tameful:tame")
		local sheep = {}
		for i = 1, 3 do
			local o = core.add_entity(vector.offset(base, 4 + i, 0, 1), "mobs_mc:sheep")
			sheep[#sheep + 1] = o
			core.after(0.6, function() o:set_properties({ hp_max = 1000 }); o:get_luaentity().health = 1000 end)
		end
		local tgt_seen = 0
		for i = 1, 20 do core.after(2 + i, function() if w._active_target then tgt_seen = tgt_seen + 1 end end) end
		core.after(24, function()
			local lost = 0
			for _, o in ipairs(sheep) do lost = lost + (1000 - o:get_luaentity().health) end
			check("pet wolf leaves sheep alone for 20 s", lost == 0 and tgt_seen == 0, "lost " .. lost .. ", target seen " .. tgt_seen)
			-- defends when hurt
			local atk = core.add_entity(vector.offset(base, 4, 0, -2), "mobs_mc:cow")
			core.after(0.6, function() atk:set_properties({ hp_max = 1000 }); atk:get_luaentity().health = 1000 end)
			core.after(1.5, function()
				local reason = { type = "mob", source = atk, direct = atk }
				mcl_damage.finish_reason(reason)
				mcl_util.deal_damage(w_o, 1, reason)
				core.after(8, function()
					check("pet wolf bites what hurt it", atk:get_luaentity().health < 1000, tostring(atk:get_luaentity().health))
					log("SCENARIO_DONE"); core.request_shutdown("done")
				end)
			end)
		end)
	end)
end)
