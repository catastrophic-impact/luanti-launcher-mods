-- /wm screen: song list (left, a scroll area), player + settings (right). Clicking a group title puts the group in or out of Shuffle and In order.
-- While it is open and something plays it redraws once a second (progress bar, times). Everything that could be disturbed by a redraw is built
-- to survive one: the list keeps its scroll position (kept in ui[name].scroll), and the settings are cycling buttons, not dropdowns.
local S = core.get_translator("wavematrix")
local esc = core.formspec_escape
local ui = {}
local MODES = { "shuffle", "in_order", "loop" }
local MODE_LABEL = { shuffle = S("Shuffle"), in_order = S("In order"), loop = S("Loop") }
local FORM = "wavematrix:main"
local ROW_H, VIEW_H, SCROLL_STEP = 0.6, 8.0, 0.1

local orig_show, orig_close = core.show_formspec, core.close_formspec
-- Another formspec taking the screen (or the player's formspec being closed) ends the live redraw, so it can never steal the screen back.
core.show_formspec = function(name, form, spec)
	if form ~= FORM and ui[name] then ui[name].open = false end
	return orig_show(name, form, spec)
end
core.close_formspec = function(name, form)
	if (form == "" or form == FORM) and ui[name] then ui[name].open = false end
	return orig_close(name, form)
end

local function mmss(t)
	t = math.max(0, math.floor(t))
	return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

local function rows_for(name, u)
	local c = wavematrix.cfg(name)
	local rows = {}
	if u.tab == 2 then
		local fav = {}
		for _, id in ipairs(c.favorites) do fav[#fav + 1] = wavematrix.by_id[id] end
		table.sort(fav, function(a, b) return a.name:lower() < b.name:lower() end)
		for _, s in ipairs(fav) do rows[#rows + 1] = { song = s } end
	else
		for _, g in ipairs(wavematrix.groups) do
			rows[#rows + 1] = { group = g }
			for _, s in ipairs(wavematrix.songs) do
				if s.group == g then rows[#rows + 1] = { song = s } end
			end
		end
	end
	return rows
end

local function formspec(name)
	local u = ui[name]
	local player = core.get_player_by_name(name)
	local c, st = wavematrix.cfg(name), wavematrix.state(name) or {}
	u.rows = rows_for(name, u)
	-- list (inside a scroll area; row buttons are invisible and only tint on hover)
	local list, rowbtns = {}, {}
	local total = #u.rows * ROW_H
	for i, r in ipairs(u.rows) do
		local y = (i - 1) * ROW_H
		if r.group then
			local out = c.skipped[r.group]
			local col = out and "#8a8a8a" or "#9fd0ff"
			list[#list + 1] = string.format("label[0.2,%.2f;%s]", y + 0.3, esc(core.colorize(col, (out and "+ " or "- ") .. r.group .. (out and (" " .. S("(left out)")) or ""))))
			list[#list + 1] = string.format("button[0,%.2f;8.2,%.2f;grp_%d;]", y, ROW_H, i)
			rowbtns[#rowbtns + 1] = "grp_" .. i
		else
			local s = r.song
			local playing = st.id == s.id
			local selected = u.sel == s.id
			if playing then list[#list + 1] = string.format("box[0,%.2f;8.2,%.2f;#7CFC7C22]", y, ROW_H - 0.04)
			elseif selected then list[#list + 1] = string.format("box[0,%.2f;8.2,%.2f;#FFFFFF22]", y, ROW_H - 0.04) end
			local star = wavematrix.is_favorite(name, s.id) and "★ " or "☆ "
			local col = playing and "#7CFC7C" or (c.skipped[s.group] and u.tab ~= 2 and "#8a8a8a" or "#FFFFFF")
			list[#list + 1] = string.format("label[0.5,%.2f;%s]", y + 0.3, esc(core.colorize(col, star .. s.name .. (playing and "  ♪" or ""))))
			list[#list + 1] = string.format("button[0,%.2f;7.4,%.2f;song_%d;]", y, ROW_H, i)
			rowbtns[#rowbtns + 1] = "song_" .. i
			list[#list + 1] = string.format("button[7.4,%.2f;0.8,%.2f;play_%d;%s]", y + 0.02, ROW_H - 0.04, i, esc("♪"))
		end
	end
	local max = math.max(0, math.floor((total - VIEW_H + 0.2) / SCROLL_STEP + 0.5))
	-- now playing
	local song = st.id and wavematrix.by_id[st.id]
	local line, frac, timetxt = S("Nothing playing"), 0, ""
	local barcol = "#7CFC7C"
	local WAITCOL = "#6FA8DC" -- the pause between songs fills in blue, so the bar always moves
	local function waitfrac(s, t) return s.wait_from and s.wait_until > s.wait_from and (t - s.wait_from) / (s.wait_until - s.wait_from) or 0 end
	local now = core.get_us_time() / 1e6
	if song then
		line = song.name
		local e = wavematrix.elapsed(name)
		if st.pending then timetxt = S("Loading…")
		elseif e then frac = e / st.length; timetxt = mmss(e) .. " / " .. mmss(st.length)
		elseif st.wait_until then timetxt = S("Next song in @1", mmss(st.wait_until - now)); frac, barcol = waitfrac(st, now), WAITCOL end
	elseif st.wait_until then timetxt = S("Starts in @1", mmss(st.wait_until - now)); frac, barcol = waitfrac(st, now), WAITCOL
	elseif c.stopped then timetxt = S("Stopped") end
	local sel = u.sel and wavematrix.by_id[u.sel]
	local favtxt = (sel and wavematrix.is_favorite(name, sel.id)) and S("★ Remove favorite") or S("☆ Make favorite")

	local H, G = uikit.row_h, uikit.gap
	local RX, RW = 10.0, 6.5                        -- right column (panel 9.7..16.8)
	local PY, PB = 1.4, 10.85                       -- both panels: top and bottom
	local hidden = {}
	if #rowbtns > 0 then
		local hov, prs = {}, {}
		for i, n in ipairs(rowbtns) do hov[i] = n .. ":hovered"; prs[i] = n .. ":pressed" end
		hidden = { "style[" .. table.concat(rowbtns, ",") .. ";bgimg=;border=false;bgcolor=#00000000]",
			"style[" .. table.concat(hov, ",") .. ";bgimg=;bgcolor=#FFFFFF25]", "style[" .. table.concat(prs, ",") .. ";bgimg=;bgcolor=#FFFFFF40]" }
	end
	local tc = uikit.cols(RX, RW, G, { 2.2, 2.2, 2.0 })     -- Play | Stop | Next
	local vc = uikit.cols(RX, RW, G, { "1.0", 1, "1.0" })   -- - | volume | +
	local bc = uikit.cols(RX, RW, G, 2)                      -- Rescan | Close
	local by = PB - 0.3 - H
	local fs = {
		uikit.begin(player, 17, 11.5),
		uikit.title(17, S("Wave Matrix"), 0),
		uikit.tabs(0.2, 0.7, 0.6, { S("All songs"), S("★ Favorites") }, u.tab, "tab_"),
		uikit.panel(0.2, PY, 9.3, PB - PY), uikit.panel(9.7, PY, 7.1, PB - PY),
		"box[0.3,1.5;8.7,", VIEW_H + 0.2, ";#14141499]",
		table.concat(hidden),
		string.format("scrollbaroptions[max=%d;smallstep=%d;largestep=%d]", max, 6, 30),
		string.format("scrollbar[9.05,1.6;0.3,%.2f;vertical;sb;%d]", VIEW_H, math.min(u.scroll or 0, max)),
		string.format("scroll_container[0.4,1.6;8.5,%.2f;sb;vertical;%.2f]", VIEW_H, SCROLL_STEP),
		table.concat(list),
		"scroll_container_end[]",
		uikit.text(0.4, PB - 1.05, 8.9, 1.0, S("Click a group title to put it in or out of Shuffle and In order. Click a song to select it, ♪ plays it."), true),
		"label[", RX, ",1.8;", esc(S("Now playing")), "]",
		"label[", RX, ",2.3;", esc(line), "]",
		"box[", RX, ",2.6;", RW, ",0.22;#00000090]",
		"box[", RX, ",2.6;", string.format("%.2f", math.max(0.001, RW * math.min(frac, 1))), ",0.22;", barcol, "]",
		"label[", RX, ",3.1;", esc(timetxt), "]",
		string.format("button[%.2f,3.45;%.2f,%.2f;play;%s]", tc[1].x, tc[1].w, H, esc(S("Play"))),
		string.format("button[%.2f,3.45;%.2f,%.2f;stop;%s]", tc[2].x, tc[2].w, H, esc(S("Stop"))),
		string.format("button[%.2f,3.45;%.2f,%.2f;next;%s]", tc[3].x, tc[3].w, H, esc(S("Next"))),
		string.format("button[%.2f,4.35;%.2f,%.2f;fav;%s]", RX, RW, H, esc(favtxt)),
		string.format("button[%.2f,5.2;%.2f,%.2f;b_mode;%s]", RX, RW, H, esc(S("Mode") .. ": " .. MODE_LABEL[c.mode])),
		string.format("button[%.2f,6.05;%.2f,%.2f;b_imm;%s]", RX, RW, H, esc(S("Immersion") .. ": " .. (c.continuous and S("Continuous") or S("Natural")))),
		string.format("button[%.2f,6.9;%.2f,%.2f;b_plays;%s]", RX, RW, H, esc(S("Plays") .. ": " .. (c.favorites_only and S("Favorites") or S("All")))),
		string.format("button[%.2f,7.75;%.2f,%.2f;vol_dn;-]", vc[1].x, vc[1].w, H),
		string.format("label[%.2f,%.2f;%s]", vc[2].x + 0.6, 7.75 + H / 2, esc(S("Volume") .. ": " .. math.floor(c.volume * 100 + 0.5) .. "%")),
		string.format("button[%.2f,7.75;%.2f,%.2f;vol_up;+]", vc[3].x, vc[3].w, H),
		uikit.toggle(RX, 8.6, RW, H, "show_name", S("Show song name"), c.show_name),
		"tooltip[b_plays;", esc(S("Favorites only works once you have a favorite.")), "]",
		"tooltip[b_imm;", esc(S("Natural: a random 3-8 minute pause between songs. Continuous: back to back.")), "]",
		string.format("button[%.2f,%.2f;%.2f,%.2f;refresh;%s]", bc[1].x, by, bc[1].w, H, esc(S("Rescan songs"))),
		string.format("button_exit[%.2f,%.2f;%.2f,%.2f;close;%s]", bc[2].x, by, bc[2].w, H, esc(S("Close"))),
	}
	return table.concat(fs)
end

-- redraw once a second while the screen is open and a song is playing, loading or waiting
local function tick(name, token)
	local u = ui[name]
	if not u or not u.open or u.token ~= token or not core.get_player_by_name(name) then return end
	local st = wavematrix.state(name)
	if st and (st.id or st.wait_until) then orig_show(name, FORM, formspec(name)) end
	core.after(1, tick, name, token)
end

function wavematrix.show(name)
	ui[name] = ui[name] or { tab = 1 }
	local u = ui[name]
	u.open = true
	u.token = (u.token or 0) + 1
	orig_show(name, FORM, formspec(name))
	core.after(1, tick, name, u.token)
end
wavematrix._formspec = function(name) ui[name] = ui[name] or { tab = 1 }; return formspec(name) end
wavematrix._ui = ui

core.register_chatcommand("wm", {
	description = S("Open the music player"),
	func = function(name) wavematrix.show(name); return true end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then return end
	local name = player:get_player_name()
	local u = ui[name] or { tab = 1 }
	ui[name] = u
	local c = wavematrix.cfg(name)
	if fields.sb then local ev = core.explode_scrollbar_event(fields.sb); if ev.value then u.scroll = ev.value end end
	if fields.quit then u.open = false; return true end
	u.open = true
	local redraw = false

	local want_tab = tonumber(fields.tab)                         -- a numeric "tab" field still selects a tab
	for i = 1, 2 do if fields["tab_" .. i] then want_tab = i end end -- the tab buttons
	if want_tab and want_tab ~= u.tab then u.tab, u.sel, u.scroll = want_tab, nil, 0; redraw = true end
	if fields.show_name ~= nil then c.show_name = uikit.flip(c.show_name, fields.show_name); wavematrix.save(name); redraw = true end

	-- list clicks: grp_<row> toggles a group, song_<row> selects, play_<row> plays
	for k in pairs(fields) do
		local kind, i = k:match("^(%a+)_(%d+)$")
		local row = i and u.rows and u.rows[tonumber(i)]
		if row and kind == "grp" and row.group then
			c.skipped[row.group] = (not c.skipped[row.group]) or nil
			wavematrix.save(name); u.sel = nil; redraw = true
		elseif row and kind == "song" and row.song then
			u.sel = row.song.id; redraw = true
		elseif row and kind == "play" and row.song then
			u.sel = row.song.id; wavematrix.play(name, row.song.id); redraw = true
		end
	end

	if fields.play then
		if u.sel and wavematrix.by_id[u.sel] then wavematrix.play(name, u.sel) else wavematrix.next(name) end
		redraw = true
	end
	if fields.stop then wavematrix.stop(name); redraw = true end
	if fields.next then wavematrix.next(name); redraw = true end
	if fields.fav and u.sel and wavematrix.by_id[u.sel] then wavematrix.toggle_favorite(name, u.sel); redraw = true end
	if fields.b_mode then
		for i, m in ipairs(MODES) do if m == c.mode then c.mode = MODES[i % #MODES + 1]; break end end
		wavematrix.save(name); redraw = true
	end
	if fields.b_imm then c.continuous = not c.continuous; wavematrix.save(name); redraw = true end
	if fields.b_plays then
		c.favorites_only = (not c.favorites_only) and #c.favorites > 0
		wavematrix.save(name); redraw = true
	end
	if fields.vol_dn or fields.vol_up then
		local v = math.floor(c.volume * 10 + 0.5) + (fields.vol_up and 1 or -1)
		wavematrix.set_volume(name, math.max(1, math.min(10, v)) / 10); redraw = true
	end
	if fields.refresh then wavematrix.scan(); redraw = true end
	if redraw then orig_show(name, FORM, formspec(name)) end
	return true
end)

core.register_on_leaveplayer(function(p) ui[p:get_player_name()] = nil end)
wavematrix._ui_tab = function(name, tab) ui[name] = ui[name] or { tab = 1 }; ui[name].tab = tab; ui[name].sel = nil end
