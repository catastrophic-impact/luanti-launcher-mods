-- The HQ screen (/hq): left = quick buttons + your own shortcuts, right = mod shortcuts with stars.
local S = core.get_translator("hq")
local esc = core.formspec_escape

local state = {} -- state[pname] = { sel = index into own, edit = index being edited, name = "", cmd = "" }
local function st(pname) state[pname] = state[pname] or {}; return state[pname] end

-- Quick buttons: label, command, privilege needed
local function quick_rows(player)
	local name = player:get_player_name()
	local function has(p) return core.check_player_privs(name, { [p] = true }) end
	local rows = {}
	if has("settime") then
		rows[#rows + 1] = { { S("Day"), "time 6000" }, { S("Noon"), "time 12000" }, { S("Dusk"), "time 18000" }, { S("Night"), "time 22000" } }
	end
	local r2 = {}
	if has("weather_manager") then
		r2[#r2 + 1] = { S("Clear"), "weather clear" }
		r2[#r2 + 1] = { S("Rain"), "weather rain" }
		r2[#r2 + 1] = { S("Thunder"), "weather thunder" }
	end
	if #r2 > 0 then rows[#rows + 1] = r2 end
	if has("server") then
		local gm = rawget(_G, "mcl_gamemode") and mcl_gamemode.get_gamemode(player) or "survival"
		-- Creative = Mineclonia's creative game mode plus the fly and fast privileges (what /grant <name> fly,fast does); off takes all three away.
		local r3 = { { gm == "creative" and S("Creative: on") or S("Creative: off"), nil, nil, hq.toggle_creative } }
		local function toggle(label, effect, cmd_on)
			local on = rawget(_G, "mcl_potions") and mcl_potions.has_effect and mcl_potions.has_effect(player, effect)
			r3[#r3 + 1] = { label .. (on and S(": on") or S(": off")), on and ("effect remove " .. effect) or cmd_on }
		end
		toggle(S("Night vision"), "night_vision", "effect night_vision INF 1")
		toggle(S("Speed"), "swiftness", "effect swiftness INF 2")
		rows[#rows + 1] = r3
	end
	if hq.can_find_villages(player) then
		local r4 = {}
		for _, k in ipairs(hq.village_kinds) do r4[#r4 + 1] = { k.label, nil, k.key } end
		rows[#rows + 1] = { village = true, unpack(r4) }
	end
	return rows
end

local function formspec(player)
	local pname = player:get_player_name()
	local s = st(pname)
	local d = hq.get(player)
	local H, G = uikit.row_h, uikit.gap
	local LX, LW = 0.7, 7.8          -- left column: x and width (panel 0.4..8.8 minus 0.3 padding)
	local RX, RW = 9.3, 6.6          -- right column (panel 9.0..16.6; the scrollbar sits at 16.0..16.3)
	local t = {
		uikit.begin(player, 17, 10.8),
		uikit.title(17, S("HQ"), 0),
		uikit.panel(0.4, 0.4, 8.4, 9.2),
		uikit.panel(9.0, 0.4, 7.6, 9.2),
	}
	-- left: quick buttons, every row spans the full column width
	local y = 0.9                     -- same top line as the right column's header
	local rows = quick_rows(player)
	if #rows > 0 then
		t[#t + 1] = "label[" .. LX .. "," .. y .. ";" .. esc(S("Quick buttons")) .. "]"
		y = y + 0.4
		for ri, row in ipairs(rows) do
			if row.village then
				t[#t + 1] = "label[" .. LX .. "," .. (y + 0.1) .. ";" .. esc(S("Go to the nearest village:")) .. "]"
				y = y + 0.4
			end
			local cols = uikit.cols(LX, LW, row.village and 0.12 or 0.2, #row)
			for i, b in ipairs(row) do
				t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;q_%d_%d;%s]", cols[i].x, y, cols[i].w, H, ri, i, esc(b[1]))
			end
			y = y + H + 0.1
		end
		y = y + 0.2
	end
	-- left: own shortcuts: name | command | Add, then the list, then Run | Edit | Delete (all rows end at the same right edge)
	t[#t + 1] = "label[" .. LX .. "," .. (y + 0.2) .. ";" .. esc(S("Your shortcuts")) .. "]"
	local fy = y + 0.55
	local fc = uikit.cols(LX, LW, G, { 2.5, 3.3, 1.8 })
	t[#t + 1] = uikit.field(fc[1].x, fy, fc[1].w, H, "nm", s.name)
	t[#t + 1] = uikit.field(fc[2].x, fy, fc[2].w, H, "cmd", s.cmd)
	t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;add;%s]", fc[3].x, fy, fc[3].w, H, esc(s.edit and S("Save") or S("Add")))
	t[#t + 1] = "tooltip[nm;" .. esc(S("Name (letters, numbers, _ -)")) .. "]tooltip[cmd;" .. esc(S("Command, with or without the /")) .. "]"
	local ly = fy + H + 0.15
	if s.edit then
		t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;cancel;%s]", fc[3].x, ly, fc[3].w, 0.6, esc(S("Cancel")))
		ly = ly + 0.7
	end
	local items = {}
	for _, e in ipairs(d.own) do items[#items + 1] = esc(e.name .. "  ->  /" .. e.command) end
	local by = 9.3 - H                 -- the Run/Edit/Delete row sits on the panel's inner bottom edge
	local lh = by - 0.1 - ly
	t[#t + 1] = string.format("textlist[%.2f,%.2f;%.2f,%.2f;own;%s;%d;false]", LX, ly, LW, lh, table.concat(items, ","), s.sel or 0)
	local bc = uikit.cols(LX, LW, G, 3)
	t[#t + 1] = string.format("button_exit[%.2f,%.2f;%.2f,%.2f;own_run;%s]", bc[1].x, by, bc[1].w, H, esc(S("Run")))
	t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;own_edit;%s]", bc[2].x, by, bc[2].w, H, esc(S("Edit")))
	t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;own_del;%s]", bc[3].x, by, bc[3].w, H, esc(S("Delete")))
	-- right: header row (title, mini-buttons count right-aligned to the column edge), rule, scrolling list
	t[#t + 1] = "label[" .. RX .. ",0.9;" .. esc(S("Mods")) .. "]"
	local hc = uikit.cols(RX, RW, 0.1, { 1, "0.8", "0.8" })
	t[#t + 1] = "label[" .. (hc[1].x + hc[1].w - 2.6) .. ",0.9;" .. esc(S("Mini buttons shown:")) .. "]"
	t[#t + 1] = uikit.field(hc[2].x, 0.55, hc[2].w, H, "minis", tostring(d.minis))
	t[#t + 1] = string.format("button[%.2f,0.55;%.2f,%.2f;setminis;OK]", hc[3].x, hc[3].w, H)
	t[#t + 1] = uikit.rule(RX, 1.35, RW)
	local n = #hq.order
	local rowh = 0.9
	local ch = 7.5
	t[#t + 1] = "scroll_container[" .. RX .. ",1.5;" .. RW .. "," .. ch .. ";scroll;vertical;0.1]"
	local rc = uikit.cols(0, RW, 0.1, { 1, "0.75", "0.75" })
	for i, id in ipairs(hq.order) do
		local sc = hq.shortcuts[id]
		local yy = (i - 1) * rowh
		t[#t + 1] = string.format("button_exit[%.2f,%.2f;%.2f,0.8;sc_%s;%s]", rc[1].x, yy, rc[1].w, id, esc(sc.name))
		t[#t + 1] = string.format("tooltip[sc_%s;%s]", id, esc(sc.command and ("/" .. sc.command) or sc.name))
		t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,0.8;star_%s;%s]", rc[2].x, yy, rc[2].w, id, hq.mini_on(d, sc) and "★" or "☆")
		local pic, short = hq.picture_of(d, sc)
		if pic then
			t[#t + 1] = string.format("item_image_button[%.2f,%.2f;%.2f,0.8;%s;pic_%s;]tooltip[pic_%s;%s]", rc[3].x, yy, rc[3].w, pic, id, id, esc(S("Change the mini button's picture")))
		else
			t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,0.8;pic_%s;%s]tooltip[pic_%s;%s]", rc[3].x, yy, rc[3].w, id, esc(short), id, esc(S("Change the mini button's picture")))
		end
	end
	t[#t + 1] = "scroll_container_end[]"
	if n * rowh > ch then
		t[#t + 1] = string.format("scrollbar[16.0,1.5;0.3,%s;vertical;scroll;0]", ch)
		t[#t + 1] = "scrollbaroptions[max=" .. math.ceil((n * rowh - ch) * 10) .. ";smallstep=9;largestep=40]"
	end
	if n == 0 then t[#t + 1] = "label[" .. RX .. ",2.0;" .. esc(S("No mod has added a shortcut yet.")) .. "]" end
	t[#t + 1] = "label[" .. RX .. ",9.3;" .. esc(S("Star = mini button above your inventory")) .. "]"
	t[#t + 1] = "button_exit[7.0,9.85;3.0," .. H .. ";close;" .. esc(S("Close")) .. "]"
	return table.concat(t)
end
hq._formspec = formspec

function hq.show(pname)
	local p = core.get_player_by_name(pname)
	core.log("action", "[hq] show for " .. tostring(pname) .. " player=" .. tostring(p ~= nil))
	if p then core.show_formspec(pname, "hq:main", formspec(p)) end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "hq:main" then return end
	local pname = player:get_player_name()
	local s = st(pname)
	local d = hq.get(player)
	if fields.nm ~= nil then s.name = fields.nm end
	if fields.cmd ~= nil then s.cmd = fields.cmd end
	if fields.own then
		local ev = core.explode_textlist_event(fields.own)
		if ev.type == "CHG" or ev.type == "DCL" then s.sel = ev.index end
	end
	-- quick buttons (same rows as drawn)
	local rows = quick_rows(player)
	for ri, row in ipairs(rows) do
		for i, b in ipairs(row) do
			if fields["q_" .. ri .. "_" .. i] then
				if b[4] then b[4](player) elseif b[3] then hq.find_village(player, b[3]) else hq.run_command(player, b[2]) end
			end
		end
	end
	if fields.add then
		local ok, why = hq.add_own(player, s.name or "", s.cmd or "", s.edit)
		if ok then s.name, s.cmd, s.edit = "", "", nil else hq.msg(pname, why) end
	elseif fields.cancel then
		s.name, s.cmd, s.edit = "", "", nil
	elseif fields.own_edit and d.own[s.sel or 0] then
		local e = d.own[s.sel]
		s.name, s.cmd, s.edit = e.name, e.command, s.sel
	elseif fields.own_del and d.own[s.sel or 0] then
		hq.remove_own(player, s.sel); s.sel = nil; s.edit = nil
	elseif fields.own_run and d.own[s.sel or 0] then
		hq.run_command(player, "/" .. d.own[s.sel].command)
		return true
	elseif fields.setminis then
		local n = tonumber(fields.minis)
		if n then d.minis = math.max(0, math.min(10, math.floor(n))); hq.save(player, d); hq.refresh_inventory(player) end
	end
	for _, id in ipairs(hq.order) do
		local sc = hq.shortcuts[id]
		if fields["sc_" .. id] then hq.run_shortcut(player, sc); return true end
		if fields["pic_" .. id] then
			d.pics[id] = ((d.pics[id] or 1) % #hq.PICTURES) + 1; hq.save(player, d); hq.refresh_inventory(player)
		end
		if fields["star_" .. id] then
			d.stars[id] = not hq.mini_on(d, sc); hq.save(player, d); hq.refresh_inventory(player)
		end
	end
	if not fields.quit then hq.show(pname) end
	return true
end)

core.register_on_leaveplayer(function(p) state[p:get_player_name()] = nil end)
