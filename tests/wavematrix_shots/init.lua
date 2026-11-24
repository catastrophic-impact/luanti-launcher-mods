local function log(s) core.log("action", "[WM_SHOTS] " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		local wm, n = wavematrix, "tester"
		wm.toggle_favorite(n, "b:track3.ogg")
		wm.play(n, "b:track2.ogg")
		core.after(5, function()
			wm.show(n) -- opened once; nothing touches it afterwards
			core.after(11, function() log("SHOT_READY wm_live_a")
			core.after(14, function() log("SHOT_READY wm_live_b")
			core.after(11, function() log("SHOTS_DONE"); core.request_shutdown("done") end) end) end)
		end)
	end)
end)
