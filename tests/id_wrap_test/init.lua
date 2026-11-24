local function log(s) core.log("action", "[IDW_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local id = identifiable
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		local long = "Harvest: needs a diamond pickaxe or better to break this block quickly"
		local out = id.wrap({ { text = "Short", color = 1 }, { text = long, color = 0x55FF55 }, { text = "mod:very_long_identifier_without_any_spaces_at_all_xyz", color = 2, keep = true } }, 20)
		local ok, longest = true, 0
		for _, l in ipairs(out) do local n = id.clen(id.plain(l.text)); longest = math.max(longest, n); if n > 20 then ok = false end end
		check("every piece fits the width", ok, "longest " .. longest)
		check("short line untouched", out[1].text == "Short" and out[1].color == 1)
		check("wrapped pieces keep the colour", out[2].color == 0x55FF55 and out[3].color == 0x55FF55)
		local joined = {}
		for _, l in ipairs(out) do if l.color == 0x55FF55 then joined[#joined + 1] = l.text end end
		check("words are not lost", table.concat(joined, " ") == long, table.concat(joined, "|"))
		local keeps = 0
		for _, l in ipairs(out) do if l.keep then keeps = keeps + 1 end end
		check("a long word is hard-broken and stays flagged keep", keeps >= 3, tostring(keeps))
		-- limit
		local many = {}
		for i = 1, 12 do many[i] = { text = "line" .. i } end
		many[13] = { text = "id", keep = true }; many[14] = { text = "mod", keep = true }
		local lim = id.limit(many, 8)
		check("limit 8 lines", #lim == 8, #lim)
		check("id and mod always stay, at the end", lim[7].text == "id" and lim[8].text == "mod" and lim[1].text == "line1" and lim[6].text == "line6")
		check("under the limit nothing changes", #id.limit({ { text = "a" } }, 8) == 1)
		-- real window
		local cfg = id.get(player)
		local win = core.get_player_window_information("tester")
		local cpl = id.chars_per_line(player, true, cfg)
		check("window size known", win and win.size and win.size.x > 300, win and (win.size.x .. "x" .. win.size.y .. " hud " .. tostring(win.real_hud_scaling)))
		check("chars per line sensible", cpl >= 20 and cpl <= 200, tostring(cpl))
		cfg.text_size = "huge"
		check("bigger text -> fewer chars per line", id.chars_per_line(player, true, cfg) < cpl)
		cfg.text_size = "normal"
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
