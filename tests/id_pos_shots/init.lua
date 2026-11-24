local function log(s) core.log("action", "[IDPS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(16, function()
		local cfg = identifiable.get(player)
		cfg.hud_x, cfg.hud_y, cfg.align, cfg.background_style = 0.55, 0.30, "manual", "tooltip"
		identifiable.state(player).config = "pos"
		core.show_formspec("tester", "identifiable:pos", (identifiable._pos_form(player)))
		core.after(12, function() log("SHOT_READY id_position"); core.after(12, function() log("SHOTS_DONE"); core.request_shutdown("done") end) end)
	end)
end)
