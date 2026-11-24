local function log(s) core.log("action", "[NOSLEEP_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local bars = {}
local orig = mcl_title.set
mcl_title.set = function(p, t, d) if t == "actionbar" then bars[#bars + 1] = d.text end return orig(p, t, d) end
local function last() return bars[#bars] or "" end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		local base = vector.round(player:get_pos())
		local function bed(dx)
			local top = vector.offset(base, dx, 0, 3)
			local bottom = vector.offset(top, 0, 0, 1) -- param2 0: dir (0,0,1): bottom = top - dir would be z-1; build as Mineclonia does
			local dir = core.facedir_to_dir(0)
			local bot = vector.subtract(top, dir)
			for _, p in ipairs({ top, bot, vector.offset(top, 0, 1, 0), vector.offset(bot, 0, 1, 0) }) do core.set_node(p, { name = "air" }) end
			core.set_node(top, { name = "mcl_beds:bed_red_top", param2 = 0 })
			core.set_node(bot, { name = "mcl_beds:bed_red_bottom", param2 = 0 })
			return top, bot
		end
		core.set_timeofday(0.5) -- noon: vanilla would refuse to sleep
		local top, bot = bed(0)
		mcl_beds.on_rightclick(top, player, true, false)
		local meta = player:get_meta()
		check("noon: respawn point set on the bed", meta:get_string("mcl_beds:spawn") == core.pos_to_string(top), meta:get_string("mcl_beds:spawn"))
		check("noon: not sleeping", not mcl_beds.player["tester"] and meta:get_string("mcl_beds:sleeping") ~= "true")
		check("action bar says Respawn point set (not chat)", last() == "Respawn point set" or last():find("Respawn point set", 1, true) ~= nil, last())
		-- the bottom half works too, and the same bed again still confirms
		bars = {}
		mcl_beds.on_rightclick(bot, player, false, false)
		check("bottom half + same bed again still confirms", #bars == 1 and not mcl_beds.player["tester"], tostring(#bars))
		-- night: still no sleeping
		core.set_timeofday(0.0)
		mcl_beds.on_rightclick(top, player, true, false)
		check("night: still not sleeping", not mcl_beds.player["tester"])
		-- obstructed bed: spawn unchanged, message
		local top2, bot2 = bed(4)
		core.set_node(vector.offset(bot2, 0, 1, 0), { name = "mcl_core:stone" })
		mcl_beds.on_rightclick(top2, player, true, false)
		check("obstructed bed does not set the spawn", meta:get_string("mcl_beds:spawn") == core.pos_to_string(top) and last():find("obstructed", 1, true) ~= nil, last())
		-- respawn anchor / bed chat message becomes an action bar
		bars = {}
		core.chat_send_player("tester", core.get_translator("mcl_beds")("New respawn position set!"))
		check("respawn message goes to the action bar", #bars == 1 and bars[1]:find("Respawn point set", 1, true) ~= nil)
		-- other chat is untouched
		bars = {}
		core.chat_send_player("tester", "hello")
		check("other chat untouched", #bars == 0)
		-- allow_sleeping on: vanilla path (at night it lets you sleep)
		for _, f in ipairs(core.registered_on_player_receive_fields) do f(player, "nosleep:main", { allow = "true" }) end
		check("allow_sleeping toggles via the screen", nosleep.allow_sleeping() == true)
		core.set_timeofday(0.0)
		mcl_beds.on_rightclick(top, player, true, false)
		check("allowed: vanilla sleeping works at night", mcl_beds.player["tester"] ~= nil)
		for _, f in ipairs(core.registered_on_player_receive_fields) do f(player, "nosleep:main", { allow = "false" }) end
		check("setting back off", nosleep.allow_sleeping() == false)
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
