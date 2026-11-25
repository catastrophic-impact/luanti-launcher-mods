core.register_on_joinplayer(function(player)
	core.after(3, function()
		local s = mcl_skins.player_skins[player]
		core.log("action", "[BOY_TEST] " .. ((s and s.slim_arms == false and s.base_color == mcl_skins.steve.base_color) and "PASS" or "FAIL") .. " new player skin slim=" .. tostring(s and s.slim_arms))
		core.log("action", "[BOY_TEST] SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
