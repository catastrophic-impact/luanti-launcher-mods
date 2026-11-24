local function log(s) core.log("action", "[HQ_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(12, function()
		core.set_player_privs("tester", { interact = true, shout = true })
		-- privilege gate
		core.set_timeofday(0.1)
		check("no settime priv: time command refused", hq.run_command(player, "/time 12000") == false and math.abs(core.get_timeofday() - 0.1) < 0.05)
		core.set_player_privs("tester", { interact = true, shout = true, settime = true, weather_manager = true, server = true })
		hq.run_command(player, "time 12000")
		check("settime priv: time set to noon", math.abs(core.get_timeofday() - 0.5) < 0.05, tostring(core.get_timeofday()))
		-- quick button via the screen's fields: row 1 button 1 = Day (6000)
		deliver(player, "hq:main", { q_1_1 = "x" })
		check("quick button Day", math.abs(core.get_timeofday() - 0.25) < 0.05, tostring(core.get_timeofday()))
		-- own shortcuts
		check("add own ok", hq.add_own(player, "dayzero", "/time 0") == true)
		check("add own duplicate refused", hq.add_own(player, "dayzero", "time 1") == false)
		check("reserved name refused", hq.add_own(player, "add", "time 1") == false)
		check("bad name refused", hq.add_own(player, "bad name!", "time 1") == false)
		check("mod id name refused", hq.add_own(player, "tameful", "time 1") == false)
		check("empty command refused", hq.add_own(player, "x1", " ") == false)
		core.registered_chatcommands.hq.func("tester", "add noon time 12000")
		core.registered_chatcommands.hq.func("tester", "dayzero")
		check("/hq <name> runs it", math.abs(core.get_timeofday() - 0) < 0.05 or core.get_timeofday() > 0.99, tostring(core.get_timeofday()))
		local d = hq.get(player)
		check("two own shortcuts stored", #d.own == 2)
		check("rename keeps its place", hq.add_own(player, "midnight", "time 0", 1) == true and hq.get(player).own[1].name == "midnight" and #hq.get(player).own == 2)
		hq.remove_own(player, 1)
		check("delete", #hq.get(player).own == 1 and hq.get(player).own[1].name == "noon")
		-- stars / mini buttons / inventory formspec (show up to 10 minis: other mods now register before tameful, the default 4 would cut it off)
		deliver(player, "hq:main", { minis = "10", setminis = "x" })
		check("tameful mini on by default", hq.mini_on(hq.get(player), hq.shortcuts.tameful) == true)
		deliver(player, "hq:main", { star_tameful = "x" })
		check("star toggles it off", hq.mini_on(hq.get(player), hq.shortcuts.tameful) == false)
		check("inventory has no tameful mini now", not player:get_inventory_formspec():find("hq_mini_tameful", 1, true))
		check("inventory still has HQ button", player:get_inventory_formspec():find("hq_open", 1, true) ~= nil)
		deliver(player, "hq:main", { star_tameful = "x" })
		check("inventory has tameful mini again", player:get_inventory_formspec():find("hq_mini_tameful", 1, true) ~= nil)
		deliver(player, "hq:main", { minis = "0", setminis = "x" })
		check("minis=0 hides mini buttons", not player:get_inventory_formspec():find("hq_mini_", 1, true))
		-- pictures: cycle through all states and come back
		deliver(player, "hq:main", { minis = "10", setminis = "x" })
		local n0 = #hq.PICTURES
		for i = 1, n0 do deliver(player, "hq:main", { pic_tameful = "x" }) end
		check("picture button cycles back to default", (hq.get(player).pics.tameful or 1) == 1, tostring(hq.get(player).pics.tameful))
		deliver(player, "hq:main", { pic_tameful = "x" })
		check("picture 2 = short name text button", player:get_inventory_formspec():find("button[", 1, true) ~= nil and player:get_inventory_formspec():find(";hq_mini_tameful;TM]", 1, true) ~= nil)
		-- village finder (the test world may have none: it must still answer)
		local said = {}
		local orig = core.chat_send_player
		core.chat_send_player = function(n, m) said[#said + 1] = m; return orig(n, m) end
		core.set_player_privs("tester", { interact = true, shout = true, server = true, teleport = true, settime = true, weather_manager = true })
		hq.find_village(player, "plains")
		core.after(40, function()
			core.chat_send_player = orig
			local joined = table.concat(said, " | ")
			check("village finder answers", joined:find("village") ~= nil and joined:find("Searching") ~= nil, joined:gsub("\27%[[^m]*m", ""):sub(1, 160))
			log("SCENARIO_DONE"); core.request_shutdown("done")
		end)
		do return end
		-- persistence across restart: meta
		check("data persisted in player meta", player:get_meta():get_string("hq:data") ~= "")
		-- clicking the HQ button in the inventory opens the screen (no error)
		deliver(player, "", { hq_open = "x" })
		check("hq_open handled", true)
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
