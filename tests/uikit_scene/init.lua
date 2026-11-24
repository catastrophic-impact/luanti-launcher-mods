-- Scene for interactive checks (lt scene uikit_scene): opens the HQ screen on join and stays up until `lt stop`.
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(10, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, settime = true, weather_manager = true, teleport = true })
		core.after(1, function()
			hq.show("tester")
			core.after(2, function() core.log("action", "[UIKIT_SCENE] SHOT_READY hq_open") end)
		end)
	end)
end)
