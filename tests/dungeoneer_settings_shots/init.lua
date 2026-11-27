local function log(s) core.log("action", "[DGSS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(16, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		dungeoneer.settings_screen.show("tester")
		core.after(8, function() log("SHOT_READY dungeoneer_settings"); core.after(14, function() log("SHOTS_DONE"); core.request_shutdown("done") end) end)
	end)
end)
