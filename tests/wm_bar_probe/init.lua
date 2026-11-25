-- Probe: what does the Wave Matrix player show while a song plays? Timeline of elapsed/length/handle/wait_until + the bar width in the formspec.
local function log(s) core.log("action", "[WMBAR_TEST] " .. s) end
core.register_on_joinplayer(function(player)
	local n = player:get_player_name()
	if n ~= "tester" then return end
	core.after(12, function()
		core.set_player_privs(n, { interact = true, shout = true, server = true })
		for _, s in ipairs(wavematrix.songs or {}) do end
		local lens = {}
		for id, s in pairs(wavematrix.by_id) do lens[#lens + 1] = string.format("%s len=%.1f path=%s", id, wavematrix.length(s), s.path ~= "" and "y" or "-") end
		table.sort(lens)
		for _, l in ipairs(lens) do log("SONG " .. l) end
		local first = next(wavematrix.by_id)
		local id = "b:track6.ogg"
		if not wavematrix.by_id[id] then id = first end
		wavematrix.show(n)
		wavematrix.play(n, id)
		core.after(3, function()
			local st = wavematrix.state(n)
			local t0 = core.get_us_time() / 1e6
			st.handle = nil; st.wait_from, st.wait_until = t0 - 10, t0 + 30
			local fs = wavematrix._formspec(n)
			log("WAIT bar=" .. tostring(fs:match("box%[[%d%.]+,2%.6;([%d%.]+),0%.22;(#%x+)%]", 1)) .. " " .. tostring(select(2, fs:match("box%[[%d%.]+,2%.6;([%d%.]+),0%.22;(#%x+)%]", 200))))
			for w, c in fs:gmatch("box%[[%d%.]+,2%.6;([%d%.]+),0%.22;(#%x+)%]") do log("BOX " .. w .. " " .. c) end
			log("SCENARIO_DONE"); core.request_shutdown("done")
		end)
	end)
end)
