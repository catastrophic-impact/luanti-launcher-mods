local function log(s) core.log("action", "[TAMEFUL_MISC_TEST] " .. s) end
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
		local pig_o = core.add_entity(vector.offset(base, 3, 0, 0), "mobs_mc:pig")
		local pig = pig_o:get_luaentity()
		player:get_inventory():add_item("main", "tameful:lead 1")
		player:set_wielded_item(ItemStack("tameful:lead"))
		pig.on_rightclick(pig, player)
		deliver(player, "tameful:tame", { yes = "true" })
		core.close_formspec("tester", "tameful:tame")
		core.after(1.5, function()
			local nm = tameful.find_record(pig._tameful_id).name
			check("tag: name only by default", pig.nametag == nm, tostring(pig.nametag))
			tameful.cfg.set("show_health", true); tameful.cfg.set("show_owner", true)
			tameful.refresh_tag(pig)
			check("tag: name, health, owner lines", pig.nametag == nm .. "\n\u{2764} 50/50\nOwner: tester", (tostring(pig.nametag):gsub("\n", "|")))
			tameful.cfg.set("show_name", false); tameful.cfg.set("show_health", false); tameful.cfg.set("show_owner", false)
			tameful.refresh_tag(pig)
			check("tag: all off = no tag", pig.nametag == "", tostring(pig.nametag))
			tameful.cfg.set("show_name", true)
			-- settings screen shows the new rows
			local fs = tameful._roster_formspec("tester")
			check("settings screen lists show_health and regen", fs:find("s_show_health", 1, true) and fs:find("s_regen_health", 1, true) ~= nil)
			-- saddle recipes
			local function crafts(items)
				local out = core.get_craft_result({ method = "normal", width = 3, items = items })
				return out.item:get_name()
			end
			check("saddle: vanilla (leather+iron) still works", crafts({ "", "mcl_mobitems:leather", "", "mcl_mobitems:leather", "mcl_core:iron_ingot", "mcl_mobitems:leather", "", "", "" }) == "mcl_mobitems:saddle")
			check("saddle: rabbit hide + copper", crafts({ "", "mcl_mobitems:rabbit_hide", "", "mcl_mobitems:rabbit_hide", "mcl_copper:copper_ingot", "mcl_mobitems:rabbit_hide", "", "", "" }) == "mcl_mobitems:saddle")
			check("saddle: wool + iron", crafts({ "", "mcl_wool:white", "", "mcl_wool:white", "mcl_core:iron_ingot", "mcl_wool:white", "", "", "" }) == "mcl_mobitems:saddle")
			-- babies and pet parents
			local baby_o = core.add_entity(vector.offset(base, 9, 0, 0), "mobs_mc:pig")
			local baby = baby_o:get_luaentity()
			baby.child = true
			core.after(1, function()
				baby._timers.check_herd = 0 -- let its herd timer fire
				local r = tameful._follow_herd(baby, baby_o:get_pos())
				check("baby ignores a pet parent", not r and baby.herd_following == nil and rawget(baby, "same_species_p") == nil, tostring(r))
				local wild_o = core.add_entity(vector.offset(base, 16, 0, 0), "mobs_mc:pig")
				core.after(1, function()
					baby._timers.check_herd = 0
					local we = wild_o:get_luaentity()
					log("NOTE wild dist " .. vector.distance(baby_o:get_pos(), wild_o:get_pos()) .. " same_species " .. tostring(baby:same_species_p(we)) .. " wild.child " .. tostring(we.child) .. " baby.child " .. tostring(baby.child) .. " herd " .. tostring(baby.herd_following))
					local r2 = tameful._follow_herd(baby, baby_o:get_pos())
					check("baby still follows a wild adult", baby.herd_following == wild_o and r2 ~= false, tostring(r2))
					log("SCENARIO_DONE"); core.request_shutdown("done")
				end)
			end)
		end)
	end)
end)
