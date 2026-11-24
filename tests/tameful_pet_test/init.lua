local function log(s) core.log("action", "[TAMEFUL_PET_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local obj = core.add_entity(vector.offset(vector.round(player:get_pos()), 3, 1, 0), "mobs_mc:pig")
		local ent = obj:get_luaentity()
		player:get_inventory():add_item("main", "tameful:lead 1")
		player:set_wielded_item(ItemStack("tameful:lead"))
		ent.on_rightclick(ent, player)
		deliver(player, "tameful:tame", { yes = "true" })
		core.close_formspec("tester", "tameful:tame")
		core.after(1.5, function()
			local id = ent._tameful_id
			-- stick opens the pet window
			player:set_wielded_item(ItemStack("mcl_core:stick"))
			ent.on_rightclick(ent, player)
			local fs = tameful._pet_formspec("tester", ent)
			check("pet window builds with stats", fs and fs:find("Mount speed", 1, true) and fs:find("Chain", 1, true) ~= nil)
			-- name, mode
			deliver(player, "tameful:pet", { rename = "x", newname = "Hamlet" })
			check("rename", tameful.find_record(id).name == "Hamlet" and ent.nametag:find("Hamlet", 1, true) ~= nil, tostring(ent.nametag))
			deliver(player, "tameful:pet", { stay = "x" })
			check("stay", ent.order == "sit")
			deliver(player, "tameful:pet", { follow = "x" })
			check("follow", ent.order ~= "sit")
			-- regen: wound it, then wait: nothing for 10 s, then +1 per 2 s
			ent._tameful_last_hp = ent.health; ent.health = 20
			core.after(3, function()
				check("no regen right after damage", ent.health <= 20, tostring(ent.health))
				ent._tameful_last_hp = ent.health; ent.health = 10 -- new damage
				core.after(8, function()
					check("no regen within 10 s of damage", ent.health <= 10, tostring(ent.health))
					core.after(10, function()
						check("regen after 10 s quiet (+1 per 2 s)", ent.health >= 12 and ent.health <= 16, tostring(ent.health))
						-- ride from the window, then stable closes it
						deliver(player, "tameful:pet", { ride = "x" })
						check("ride from the window", ent.driver == player)
						ent:detach(player, vector.new(0, 0.5, 0))
						deliver(player, "tameful:pet", { stable = "x" })
						check("stable from the window", tameful.find_record(id).status == "stabled")
						-- settings toggles (cycling buttons): a click flips the value and the screen shows On/Off
						local before = tameful.cfg.get("show_health")
						local function plain(fs) return (fs:gsub("\27%(T@[^)]*%)", ""):gsub("\27E", "")) end -- translated strings carry hidden markers
						check("settings screen shows the toggle", plain(tameful._roster_formspec("tester")):find("Show its health: " .. (before and "On" or "Off"), 1, true) ~= nil)
						deliver(player, "tameful:roster", { s_show_health = "Show its health" })
						check("toggle click flips the setting", tameful.cfg.get("show_health") == (not before))
						check("screen now shows the new state", plain(tameful._roster_formspec("tester")):find("Show its health: " .. (before and "Off" or "On"), 1, true) ~= nil)
						deliver(player, "tameful:roster", { s_show_health = "Show its health" })
						check("second click flips it back", tameful.cfg.get("show_health") == before)
						log("SCENARIO_DONE"); core.request_shutdown("done")
					end)
				end)
			end)
		end)
	end)
end)
