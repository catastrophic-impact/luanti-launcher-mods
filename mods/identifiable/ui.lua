-- /idconfig: settings screen + position mode.
local S = core.get_translator("identifiable")
local id = identifiable
local esc = core.formspec_escape

local BOOLS = {
	{ "enabled", S("Enabled") }, { "show_id", S("Show ID") }, { "show_mod_name", S("Mod name") }, { "show_icon", S("Icon") },
	{ "show_health", S("Health") }, { "show_armor", S("Armor") }, { "show_player_health", S("Player health") },
	{ "show_block_details", S("Block details") }, { "show_harvest", S("Harvest info") }, { "show_spawnable", S("Spawnable warning") },
	{ "show_villager", S("Villager job") }, { "show_items", S("Items") }, { "show_spawner", S("Spawner mob") }, { "show_breaking", S("Breaking progress") },
}
local LABEL = {
	white = S("White"), yellow = S("Yellow"), red = S("Red"), green = S("Green"), blue = S("Blue"), aqua = S("Aqua"), gold = S("Gold"),
	light_purple = S("Light purple"), gray = S("Gray"), small = S("Small"), normal = S("Normal"), large = S("Large"), huge = S("Huge"),
	dark = S("Dark"), button = S("Button"), advancement = S("Advancement"), tooltip = S("Tooltip"), none = S("None"), off = S("Off"), light = S("Light only"), sky = S("Sky only"), both = S("Both"), combined = S("Combined"),
	manual = S("Manual"), left = S("Left"), center = S("Center"), right = S("Right"),
}
local function lab(v) return LABEL[v] or tostring(v) end

local SAMPLE_LABEL = { block = S("Block"), crop = S("Crop"), mob = S("Mob"), villager = S("Villager"), spawner = S("Spawner"), item = S("Item"), player = S("Player") }
local VIEW_H = 8.2          -- height of the scrolling settings list
local SCROLL_STEP = 0.1     -- formspec units per scrollbar step

-- Live preview: the panel as the HUD would draw it, with the current settings (left side).
local function preview(t, cfg, sample)
	local x0, y0, w0, h0 = 0.3, 1.6, 8.3, 7.5
	t[#t + 1] = string.format("box[%.2f,%.2f;%.2f,%.2f;#1d2635]", x0, y0, w0, h0)
	t[#t + 1] = string.format("box[%.2f,%.2f;%.2f,%.2f;#2e3b52]", x0, y0 + h0 * 0.62, w0, h0 * 0.38) -- a bit of "ground"
	local info = id.sample(sample, cfg)
	local mult = id.SIZES[cfg.text_size] or 1
	local lines = { { text = info.title } }
	for _, l in ipairs(info.lines) do lines[#lines + 1] = l end
	lines = id.limit(id.wrap(lines, 34), 8)
	local lh, cw, pad = 0.5 * mult, 0.17 * mult, 0.25
	local iconw = info.icon and (1.0 * mult) or 0
	local maxc = 0
	for _, l in ipairs(lines) do maxc = math.max(maxc, id.clen(id.plain(l.text))) end
	local textw = maxc * cw
	local totw = math.min(w0 - 0.4, textw + iconw + pad * 2)
	local toth = math.max(#lines * lh, info.icon and 1.0 * mult or 0) + pad * 2
	local px = x0 + 0.4
	if cfg.align == "center" then px = x0 + (w0 - totw) / 2 elseif cfg.align == "right" then px = x0 + w0 - totw - 0.4 end
	local py = y0 + 0.5
	if #lines > 0 and not (sample == "item" and not cfg.show_items) then
		local bg = cfg.background_style
		if bg == "dark" then t[#t + 1] = string.format("box[%.2f,%.2f;%.2f,%.2f;#000000A0]", px, py, totw, toth)
		elseif bg == "tooltip" then t[#t + 1] = string.format("box[%.2f,%.2f;%.2f,%.2f;#2b0a55]box[%.2f,%.2f;%.2f,%.2f;#100010F0]", px, py, totw, toth, px + 0.06, py + 0.06, totw - 0.12, toth - 0.12)
		elseif bg == "button" then t[#t + 1] = string.format("box[%.2f,%.2f;%.2f,%.2f;#1a1a1a]box[%.2f,%.2f;%.2f,%.2f;#6e6e6e]", px, py, totw, toth, px + 0.05, py + 0.05, totw - 0.1, toth - 0.1)
		elseif bg == "advancement" then t[#t + 1] = string.format("box[%.2f,%.2f;%.2f,%.2f;#b8a06a]box[%.2f,%.2f;%.2f,%.2f;#262626]", px, py, totw, toth, px + 0.06, py + 0.06, totw - 0.12, toth - 0.12) end
	end
	if info.icon then t[#t + 1] = string.format("item_image[%.2f,%.2f;%.2f,%.2f;%s]", px + pad, py + pad, 1.0 * mult, 1.0 * mult, info.icon) end
	local color = id.COLORS[cfg.hud_color] or 0xFFFFFF
	local labels = {}
	for i, l in ipairs(lines) do
		local lw = id.clen(id.plain(l.text)) * cw
		local x = px + pad + iconw
		if cfg.text_align == "center" then x = x + (textw - lw) / 2 end
		local col = l.color or color
		labels[#labels + 1] = string.format("label[%.2f,%.2f;%s]", x, py + pad + (i - 0.5) * lh, esc(core.colorize(string.format("#%06X", col), l.text)))
	end
	t[#t + 1] = string.format("style_type[label;font_size=*%.2f]", mult)
	for _, l in ipairs(labels) do t[#t + 1] = l end
	t[#t + 1] = "style_type[label;font_size=*1]"
end

local function main_form(player)
	local cfg, s = id.get(player), id.state(player)
	s.sample = s.sample or "block"
	local H, G = 0.6, 0.1                         -- settings rows: height and gap (pitch 0.7)
	local t = { uikit.begin(player, 17, 11.6), uikit.title(17, S("Identifiable Settings"), 0),
		uikit.panel(0.2, 0.9, 8.6, 8.6), uikit.panel(9.0, 0.9, 7.8, 8.6) }
	-- sample pictures (left, above the preview): one row across the panel, the selected one pressed in
	local sc = uikit.cols(0.3, 8.4, 0.08, { 1, 1, 0.9, 1.25, 1.3, 0.9, 1.05 }) -- block crop mob villager spawner item player (wider for the long names)
	assert(#id.SAMPLE_KINDS == 7, "sample column weights need one entry per sample kind")
	for i, k in ipairs(id.SAMPLE_KINDS) do
		if s.sample == k then t[#t + 1] = uikit.active("sample_" .. k) end
		t[#t + 1] = string.format("button[%.2f,1.05;%.2f,0.5;sample_%s;%s]", sc[i].x, sc[i].w, k, esc(SAMPLE_LABEL[k]))
	end
	-- settings (right, scrolling): every row is a full-width button, On/Off toggles and cycling choices alike
	local y = 0.05
	local RW = 7.0
	local body = {}
	local function head(text) body[#body + 1] = string.format("label[0,%.2f;%s]", y + 0.25, esc(core.colorize("#9fd0ff", text))); y = y + 0.55 end
	local function tog(name, label) body[#body + 1] = uikit.toggle(0, y, RW, H, name, label, cfg[name]); y = y + H + G end
	local function btn(name, label, value) body[#body + 1] = string.format("button[0,%.2f;%.2f,%.2f;%s;%s]", y, RW, H, name, esc(label .. ": " .. lab(value))); y = y + H + G end
	tog("enabled", S("Enabled"))
	btn("b_color", S("Color"), cfg.hud_color)
	btn("b_size", S("Size"), cfg.text_size)
	btn("b_bg", S("Background"), cfg.background_style)
	btn("b_range", S("Range"), cfg.range .. "")
	y = y + 0.1
	head(S("Display Settings"))
	for _, b in ipairs(BOOLS) do if b[1] ~= "enabled" then tog(b[1], b[2]) end end
	btn("b_light", S("Light level"), cfg.light_mode)
	btn("b_talign", S("Text align"), cfg.text_align)
	btn("b_align", S("Panel align"), cfg.align)
	body[#body + 1] = string.format("button[0,%.2f;%.2f,%.2f;clearbl;%s]", y, RW, H, esc(S("Clear blacklist"))); y = y + H + 0.3
	local total = y
	local max = math.max(0, math.floor((total - VIEW_H) / SCROLL_STEP + 0.5))
	t[#t + 1] = string.format("scrollbaroptions[max=%d;smallstep=%d;largestep=%d]", max, 6, 30)
	t[#t + 1] = string.format("scrollbar[16.45,1.05;0.3,%.2f;vertical;sb;%d]", VIEW_H, math.min(s.scroll or 0, max))
	t[#t + 1] = string.format("scroll_container[9.2,1.05;7.1,%.2f;sb;vertical;%.2f]", VIEW_H, SCROLL_STEP)
	t[#t + 1] = table.concat(body)
	t[#t + 1] = "scroll_container_end[]"
	preview(t, cfg, s.sample)
	-- always visible: hint, then Position | Reset on the left and Done on the right, all on the same bottom line
	t[#t + 1] = uikit.text(0.3, 9.6, 16.4, 0.8, S("Hold Z to zoom (mouse wheel: 2x-10x, range 128 while zoomed). /idhide hides the panel, /idblacklist hides what you look at."), true)
	local by = 11.6 - 0.3 - uikit.row_h
	local bc = uikit.cols(0.2, 8.6, uikit.gap, 2)
	t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;position;%s]", bc[1].x, by, bc[1].w, uikit.row_h, esc(S("Position")))
	t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;reset;%s]", bc[2].x, by, bc[2].w, uikit.row_h, esc(S("Reset")))
	t[#t + 1] = string.format("button_exit[%.2f,%.2f;%.2f,%.2f;done;%s]", 16.8 - bc[2].w, by, bc[2].w, uikit.row_h, esc(S("Done")))
	return table.concat(t)
end

-- Position mode: a full-window grid of invisible buttons (half a formspec unit each = 2.5% steps like the arrows). Click where the
-- panel's top-left corner should go; with Align Left/Center/Right only the height changes. The arrows, Align and Done stay on top.
local CELL = 0.5
local function grid_size(player)
	local win = core.get_player_window_information(player:get_player_name())
	local m = win and win.max_formspec_size
	return math.max(10, m and m.x or 20), math.max(6, m and m.y or 11)
end
local function grid_dims(player)
	local mx, my = grid_size(player)
	return math.floor(mx / CELL), math.floor(my / CELL), mx, my
end
local function pos_form(player)
	local cols, rows, mx, my = grid_dims(player)
	local st = uikit.use(player)
	local t = {
		string.format("formspec_version[6]size[%.2f,%.2f]position[0.5,0.5]anchor[0.5,0.5]padding[0,0]no_prepend[]bgcolor[#00000000;neither]", mx, my),
		"style_type[button;bgimg=;border=false;bgcolor=#00000000;bgcolor_hovered=#FFFFFF33;bgcolor_pressed=#FFFFFF66]",
	}
	for cy = 0, rows - 1 do
		for cx = 0, cols - 1 do
			t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;p_%d_%d;]", cx * CELL, cy * CELL, CELL, CELL, cx, cy)
		end
	end
	-- the control bar on top of the grid uses the shared theme (reset the grid's transparent tint first)
	local bx, by = (mx - 9.4) / 2, my - 3.2 -- above Mineclonia's hotbar, which is drawn over formspecs
	t[#t + 1] = uikit.styles(st)
	t[#t + 1] = "style_type[button;bgcolor=#ffffff]style_type[button:hovered;bgcolor=#ffffff]style_type[button:pressed;bgcolor=#ffffff]"
	t[#t + 1] = uikit.panel(bx, by - 0.1, 9.4, 1.4)
	t[#t + 1] = string.format("label[%.2f,%.2f;%s]", bx + 0.2, by + 0.15, esc(S("Click where the panel should go, or nudge it.")))
	t[#t + 1] = string.format("button[%.2f,%.2f;0.9,0.7;left;<]button[%.2f,%.2f;0.9,0.7;up;^]button[%.2f,%.2f;0.9,0.7;down;v]button[%.2f,%.2f;0.9,0.7;right;>]",
		bx + 0.2, by + 0.45, bx + 1.2, by + 0.45, bx + 2.2, by + 0.45, bx + 3.2, by + 0.45)
	t[#t + 1] = string.format("button[%.2f,%.2f;2.0,0.7;align;%s]", bx + 4.4, by + 0.45, esc(S("Align")))
	t[#t + 1] = string.format("button_exit[%.2f,%.2f;2.6,0.7;pdone;%s]", bx + 6.6, by + 0.45, esc(S("Done")))
	return table.concat(t), cols, rows
end

local function open_main(player)
	id.state(player).config = "main"
	core.show_formspec(player:get_player_name(), "identifiable:cfg", main_form(player))
end

core.register_chatcommand("idconfig", {
	description = S("Identifiable settings"),
	func = function(name) local p = core.get_player_by_name(name); if p then open_main(p) end return true end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "identifiable:pos" and formname ~= "identifiable:cfg" then return end
	local name = player:get_player_name()
	local cfg, s = id.get(player), id.state(player)
	if formname == "identifiable:pos" then
		local step = 0.025
		local cx, cy = nil, nil
		for k in pairs(fields) do local a, b = k:match("^p_(%d+)_(%d+)$"); if a then cx, cy = tonumber(a), tonumber(b) end end
		if cx then
			local cols, rows = grid_dims(player)
			if cfg.align == "manual" then cfg.hud_x = math.min(0.95, cx / cols) end
			cfg.hud_y = math.min(0.95, cy / rows)
		elseif fields.left then cfg.hud_x = math.max(0, cfg.hud_x - step); cfg.align = "manual"
		elseif fields.right then cfg.hud_x = math.min(0.95, cfg.hud_x + step); cfg.align = "manual"
		elseif fields.up then cfg.hud_y = math.max(0, cfg.hud_y - step)
		elseif fields.down then cfg.hud_y = math.min(0.95, cfg.hud_y + step)
		elseif fields.align then cfg.align = id.cycle(id.ALIGNS, cfg.align) end
		id.save(player)
		if fields.pdone or fields.quit then s.config = nil; open_main(player)
		else core.show_formspec(name, "identifiable:pos", (pos_form(player))) end
		return true
	end
	for _, b in ipairs(BOOLS) do
		local f = fields[b[1]]
		if f == "true" then cfg[b[1]] = true elseif f == "false" then cfg[b[1]] = false
		elseif f ~= nil then cfg[b[1]] = not cfg[b[1]] end -- a toggle button sends its label when clicked: flip
	end
	if fields.sb then local ev = core.explode_scrollbar_event(fields.sb); if ev.value then s.scroll = ev.value end end
	for _, k in ipairs(id.SAMPLE_KINDS) do if fields["sample_" .. k] then s.sample = k end end
	if fields.b_color then cfg.hud_color = id.cycle(id.COLOR_ORDER, cfg.hud_color)
	elseif fields.b_size then cfg.text_size = id.cycle(id.SIZE_ORDER, cfg.text_size)
	elseif fields.b_bg then cfg.background_style = id.cycle(id.BACKGROUNDS, cfg.background_style)
	elseif fields.b_range then cfg.range = id.cycle(id.RANGES, cfg.range)
	elseif fields.b_light then cfg.light_mode = id.cycle(id.LIGHT_MODES, cfg.light_mode)
	elseif fields.b_talign then cfg.text_align = cfg.text_align == "left" and "center" or "left"
	elseif fields.b_align then cfg.align = id.cycle(id.ALIGNS, cfg.align)
	elseif fields.clearbl then cfg.hidden = {}
	elseif fields.reset then id.reset(player)
	elseif fields.position then
		id.save(player); s.config = "pos"
		core.show_formspec(name, "identifiable:pos", (pos_form(player)))
		return true
	end
	id.save(player)
	if fields.quit or fields.done then s.config = nil
	else core.show_formspec(name, "identifiable:cfg", main_form(player)) end
	return true
end)

identifiable._open_main = open_main

identifiable._grid_dims = grid_dims
identifiable._pos_form = pos_form
