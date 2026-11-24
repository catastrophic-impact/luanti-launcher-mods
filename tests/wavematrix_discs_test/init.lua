local function log(s) core.log("action", "[WMD_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local wm, n = wavematrix, "tester"
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= n then return end
	core.after(15, function()
		local nd, first = 0, nil
		for _, s in ipairs(wm.songs) do if s.id:sub(1, 2) == "d:" then nd = nd + 1; first = first or s end end
		check("discs listed", nd >= 8, tostring(nd))
		check("discs group is last", wm.groups[#wm.groups] == wm.GROUP_DISCS, table.concat(wm.groups, "|"))
		check("disc title has author", first and first.name:find(" - ", 1, true) ~= nil, first and first.name)
		check("disc length read", first and wm.length(first) ~= 180, first and tostring(wm.length(first)))
		local c = wm.cfg(n)
		check("discs left out by default", c.skipped[wm.GROUP_DISCS] == true)
		for _, s in ipairs(wm.pool(n)) do if s.group == wm.GROUP_DISCS then check("pool holds no disc", false) end end
		check("pool holds no disc", true)
		local sent, plays = 0, {}
		local o = core.dynamic_add_media
		core.dynamic_add_media = function(...) sent = sent + 1; return o(...) end
		local osp = core.sound_play
		core.sound_play = function(s, p, ...) plays[#plays + 1] = s return osp(s, p, ...) end
		check("a disc can be played directly", wm.play(n, first.id))
		check("disc plays its own sound, nothing sent", sent == 0 and plays[#plays] == first.media, tostring(plays[#plays]) .. " sent=" .. sent)
		check("handle returned", wm.state(n).handle ~= nil)
		wm.stop(n)
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
