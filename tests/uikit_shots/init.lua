-- Screenshot scenes: HQ screen, then the uikit settings window with a non-default setting (2 scenes).
local function log(s) core.log("action", "[UIKIT_SHOTS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(12, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, settime = true, weather_manager = true, teleport = true })
		core.after(1, function()
			hq.show("tester")
			core.after(2, function() log("SHOT_READY uikit_hq")
			core.after(10, function()
				uikit.set(player, "text", "warm"); uikit.set(player, "panel", "solid")
				uikit.show_settings(player)
				core.after(2, function() log("SHOT_READY uikit_settings")
				core.after(10, function() log("SHOTS_DONE"); core.request_shutdown("done") end) end)
			end) end)
		end)
	end)
end)
