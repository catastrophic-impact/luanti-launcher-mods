local function log(s) core.log("action", "[SHOTS_TEST] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(10, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		core.show_formspec("tester", "populations:settings", populations.cfg.formspec("tester"))
		core.after(3, function() log("SHOT_READY pop") end)
		core.after(6, function() log("SHOTS_DONE"); core.request_shutdown("done") end)
	end)
end)
