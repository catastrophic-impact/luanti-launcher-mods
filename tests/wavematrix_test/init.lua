local function log(s) core.log("action", "[WM_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local wm = wavematrix
local n = "tester"
local function wait(cond, secs, fn)
	local t = 0
	local function step() t = t + 0.5; if cond() or t >= secs then fn(cond()) else core.after(0.5, step) end end
	step()
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= n then return end
	core.after(15, function()
		local songs = wm.songs
		local nb, nu = 0, 0
		for _, s in ipairs(songs) do if s.id:sub(1, 2) == "b:" then nb = nb + 1 else nu = nu + 1 end end
		check("12 bundled tracks listed", nb == 12, tostring(nb))
		check("own music listed from wm_music (subfolder = group)", nu >= 1, tostring(nu) .. " groups=" .. table.concat(wm.groups, "|"))
		local l1 = wm.length(wm.by_id["b:track1.ogg"])
		check("ogg length read (track1 is a few minutes)", l1 > 60 and l1 < 600, tostring(l1))
		local c = wm.cfg(n)
		check("defaults: shuffle, natural, not stopped", c.mode == "shuffle" and c.continuous == false and not c.stopped)
		local sent = 0
		local orig = core.dynamic_add_media
		core.dynamic_add_media = function(d, cb) sent = sent + 1; return orig(d, cb) end
		local plays = {}
		local osp = core.sound_play
		core.sound_play = function(s, p, ...) if type(s) == "string" and s:sub(1, 3) == "wm_" then plays[#plays + 1] = { s, p } end return osp(s, p, ...) end
		check("play starts", wm.play(n, "b:track2.ogg"))
		wait(function() return #plays >= 1 end, 20, function(ok)
			check("media sent then sound played to the player only", ok and sent == 1 and plays[1][2].to_player == n, "sent=" .. sent)
			check("handle returned", wm.state(n).handle ~= nil)
			wm.play(n, "b:track2.ogg")
			check("second play of same song needs no new media", #plays >= 2 and sent == 1, "sent=" .. sent .. " plays=" .. #plays)
			local el = wm.elapsed(n)
			check("elapsed counts", el ~= nil and el < 3, tostring(el))
			wm.set_volume(n, 0.2)
			check("volume restarts at the same spot", #plays >= 3 and plays[#plays][2].gain == 0.2 and (plays[#plays][2].start_time or 0) >= 0)
			-- next-song rules
			c.mode = "in_order"
			check("in order: track2 -> track3", wm.pick_next(n, "b:track2.ogg").id == "b:track3.ogg")
			c.mode = "loop"
			check("loop: same song", wm.pick_next(n, "b:track2.ogg").id == "b:track2.ogg")
			c.mode = "shuffle"
			local ok2 = true
			for _ = 1, 40 do if wm.pick_next(n, "b:track2.ogg").id == "b:track2.ogg" then ok2 = false end end
			check("shuffle never repeats the song just played", ok2)
			-- groups and favorites
			c.skipped[wm.GROUP_BUNDLED] = true
			local pool = wm.pool(n)
			-- own songs only, and not the groups that are left out by default (the Mineclonia discs): count what the pool should hold
			local expect = 0
			for _, sg in ipairs(wm.songs) do if sg.id:sub(1, 2) ~= "b:" and not c.skipped[sg.group] then expect = expect + 1 end end
			check("group left out: no bundled songs in the pool", #pool == expect, #pool .. " vs " .. expect)
			c.skipped[wm.GROUP_BUNDLED] = nil
			wm.toggle_favorite(n, "b:track5.ogg")
			wm.toggle_favorite(n, "b:track7.ogg")
			c.favorites_only = true
			check("favorites only: pool = favorites", #wm.pool(n) == 2)
			c.skipped[wm.GROUP_BUNDLED] = true
			check("favorites play even from a left-out group", #wm.pool(n) == 2)
			c.skipped[wm.GROUP_BUNDLED] = nil
			wm.toggle_favorite(n, "b:track5.ogg"); wm.toggle_favorite(n, "b:track7.ogg")
			wm.pool(n)
			check("last favorite removed -> back to All", c.favorites_only == false)
			c.favorites = { "u:gone.ogg", "b:track1.ogg" }
			wm.pool(n)
			check("favorite of a missing song is dropped", #c.favorites == 1 and c.favorites[1] == "b:track1.ogg")
			-- stop / end of song
			wm.stop(n)
			check("stop: silent, remembered", wm.state(n).handle == nil and c.stopped == true)
			-- end of song: Natural waits, Continuous goes on at once
			c.continuous = false
			wm.play(n, "b:track3.ogg")
			wait(function() return wm.state(n).handle ~= nil end, 20, function()
				wm.state(n).length = 1
				wait(function() return wm.state(n).handle == nil and wm.state(n).wait_until ~= nil end, 10, function(ok3)
					local w = ok3 and (wm.state(n).wait_until - core.get_us_time() / 1e6) or 0
					check("natural: pause of 3-8 minutes after a song", ok3 and w > 170 and w < 485, tostring(w))
					c.continuous = true
					wm.play(n, "b:track3.ogg")
					wait(function() return wm.state(n).handle ~= nil end, 20, function()
						wm.state(n).length = 1
						local before = wm.state(n).id
						wait(function() return wm.state(n).id ~= before and wm.state(n).handle ~= nil end, 25, function(ok4)
							check("continuous: next song starts right away", ok4, tostring(wm.state(n).id))
							local fs = wm._formspec(n)
							check("screen builds", #fs > 500 and fs:find("scroll_container", 1, true) ~= nil)
							wm.stop(n)
							log("SCENARIO_DONE"); core.request_shutdown("done")
						end)
					end)
				end)
			end)
		end)
	end)
end)
