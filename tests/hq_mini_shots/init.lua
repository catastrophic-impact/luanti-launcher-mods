local function log(s) core.log("action", "[HQMS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(16, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		mcl_gamemode.set_gamemode(player, "survival")
		core.after(1, function()
			core.show_formspec("tester", "", player:get_inventory_formspec())
			core.after(3, function()
				-- what a click on the Wave Matrix mini button sends
				for _, f in ipairs(core.registered_on_player_receive_fields) do f(player, "", { hq_mini_wavematrix = "" }) end
				core.after(12, function() log("SHOT_READY hq_mini_opened"); core.after(11, function() log("SHOTS_DONE"); core.request_shutdown("done") end) end)
			end)
		end)
	end)
end)
