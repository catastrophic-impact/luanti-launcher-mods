-- Screenshot scenes for screens built with uikit.screen: Conflict Resolution, Mob Crate, Populations (3 scenes).
local function log(s) core.log("action", "[UISCR_SHOTS] " .. s) end
local scenes = { { "cr", "scr_cr" }, { "mobcrate", "scr_mobcrate" }, { "pop", "scr_pop" } }
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(12, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		local i = 0
		local function nxt()
			i = i + 1
			if not scenes[i] then log("SHOTS_DONE"); return core.request_shutdown("done") end
			core.registered_chatcommands[scenes[i][1]].func("tester", "")
			core.after(3, function() log("SHOT_READY " .. scenes[i][2]); core.after(12, nxt) end)
		end
		nxt()
	end)
end)
