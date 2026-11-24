-- Screenshot scenes: the /idconfig settings screen and the position mode (2 scenes).
local function log(s) core.log("action", "[IDUI_SHOTS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(12, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		identifiable.state(player).sample = "mob"
		identifiable._open_main(player)
		core.after(3, function() log("SHOT_READY id_config")
			core.after(12, function()
				core.show_formspec("tester", "identifiable:pos", (identifiable._pos_form(player)))
				core.after(3, function() log("SHOT_READY id_position")
					core.after(12, function() log("SHOTS_DONE"); core.request_shutdown("done") end) end)
			end)
		end)
	end)
end)
