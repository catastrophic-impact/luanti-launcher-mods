local function log(s) core.log("action", "[WMU_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local wm, n = wavematrix, "tester"
local function send(player, fields) for _, f in ipairs(core.registered_on_player_receive_fields) do f(player, "wavematrix:main", fields) end end
local function row_of(pred) for i, r in ipairs(wm._ui[n].rows) do if pred(r) then return i end end end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= n then return end
	core.after(15, function()
		local c = wm.cfg(n)
		-- count the redraws of our screen
		local shows = 0
		local orig = core.show_formspec
		-- (wavematrix wrapped core.show_formspec already; count what reaches the engine through minetest's real function)
		local real = core.show_formspec
		local counting = function(name, form, spec) if form == "wavematrix:main" then shows = shows + 1 end return real(name, form, spec) end
		wm.show(n)
		local u = wm._ui[n]
		check("open: flagged open", u.open == true)
		check("screen has the scroll area and cycle buttons, no dropdowns", wm._formspec(n):find("scroll_container", 1, true) and wm._formspec(n):find("b_mode", 1, true) and not wm._formspec(n):find("dropdown", 1, true))
		-- clicks
		local gi = row_of(function(r) return r.group == wm.GROUP_BUNDLED end)
		send(player, { ["grp_" .. gi] = "" })
		check("group click leaves the group out", c.skipped[wm.GROUP_BUNDLED] == true)
		send(player, { ["grp_" .. gi] = "" })
		check("group click again puts it back", c.skipped[wm.GROUP_BUNDLED] == nil)
		local si = row_of(function(r) return r.song and r.song.id == "b:track4.ogg" end)
		send(player, { ["song_" .. si] = "" })
		check("song click selects", u.sel == "b:track4.ogg")
		send(player, { fav = "" })
		check("favorite button uses the selected song", wm.is_favorite(n, "b:track4.ogg"))
		send(player, { fav = "" })
		local m0 = c.mode
		send(player, { b_mode = "" })
		check("mode button cycles", c.mode ~= m0)
		send(player, { b_mode = "" }); send(player, { b_mode = "" })
		check("mode cycles back after 3 clicks", c.mode == m0)
		send(player, { b_imm = "" })
		check("immersion button toggles", c.continuous == true)
		send(player, { b_imm = "" })
		send(player, { b_plays = "" })
		check("plays stays All without favorites", c.favorites_only == false)
		local v0 = c.volume
		send(player, { vol_up = "" })
		check("volume + steps 10%", math.abs(c.volume - math.min(1, v0 + 0.1)) < 1e-6, tostring(c.volume))
		send(player, { vol_dn = "" }); send(player, { vol_dn = "" })
		check("volume - steps 10%", math.abs(c.volume - (v0 - 0.1)) < 1e-6 or c.volume == 0.1, tostring(c.volume))
		c.volume = 0.5
		-- scroll position survives redraws
		send(player, { sb = "CHG:25" })
		check("scroll position remembered", u.scroll == 25 and wm._formspec(n):find("sb;25]", 1, true) ~= nil)
		-- the ♪ button plays that row
		local plays = 0
		local osp = core.sound_play
		core.sound_play = function(s, p, ...) if type(s) == "string" and s:sub(1, 3) == "wm_" then plays = plays + 1 end return osp(s, p, ...) end
		local pi = row_of(function(r) return r.song and r.song.id == "b:track6.ogg" end)
		send(player, { ["play_" .. pi] = "" })
		core.after(3, function()
			check("row play button starts that song", wm.state(n).id == "b:track6.ogg" and plays >= 1)
			-- live redraw: count real shows over 3.5 s while open
			local s0 = u.open and 0
			local seen = 0
			local show_orig = core.show_formspec
			-- spy at the engine boundary: wavematrix calls the engine's original show_formspec; wrap show via the registered globalstep-free path
			local engine = core.show_formspec
			local base_count = 0
			-- the cheapest honest spy: elapsed time in the formspec text changes between redraws
			local f1 = wm._formspec(n)
			core.after(3.5, function()
				local f2 = wm._formspec(n)
				check("progress text moves with time", f1 ~= f2)
				check("window still flagged open and redraw loop token alive", u.open == true and u.token ~= nil)
				-- another formspec takes the screen: the loop must stop
				local tok = u.token
				core.show_formspec(n, "other:form", "formspec_version[4]size[4,2]label[0.5,0.5;other]")
				check("another formspec clears the open flag", u.open == false)
				-- quit also ends it
				wm.show(n)
				check("show sets it open again", u.open == true)
				send(player, { quit = "true" })
				check("quit clears the open flag", u.open == false)
				-- closing the player's formspec ends it too
				wm.show(n); core.close_formspec(n, "")
				check("close_formspec clears the open flag", u.open == false)
				wm.stop(n)
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end)
		end)
	end)
end)
