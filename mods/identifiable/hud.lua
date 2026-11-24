-- The panel: a background box, an item icon and up to MAXL text lines (one HUD text element each so every line can have its own colour).
local id = identifiable
local MAXL = 12
local huds = {} -- huds[name] = { bg=, icon=, lines={}, last = {text per line}, shown = bool }

-- Framed backgrounds (outer frame colour, inner colour, frame width in px). The HUD cannot stretch Minecraft's own frame pictures,
-- so these are drawn with layered fills: they are look-alikes and do not follow resource packs.
local FRAMES = {
	tooltip = { "#2b0a55", "#100010F0", 2 },
	button = { "#1a1a1a", "#6e6e6e", 2 },
	advancement = { "#b8a06a", "#262626", 2 },
}
local function tex_frame(w, h, outer, inner, b)
	w, h = math.max(2 * b + 1, math.floor(w)), math.max(2 * b + 1, math.floor(h))
	return string.format("[combine:%dx%d:0,0=[fill\\:%dx%d\\:0,0\\:%s:%d,%d=[fill\\:%dx%d\\:0,0\\:%s", w, h, w, h, outer, b, b, w - 2 * b, h - 2 * b, inner)
end
local function tex_fill(w, h, color) return string.format("[fill:%dx%d:0,0:%s", math.max(1, math.floor(w)), math.max(1, math.floor(h)), color) end

local function create(player)
	local name = player:get_player_name()
	local inv = player:get_inventory()
	inv:set_size("identifiable_icon", 1)
	local h = { lines = {}, last = {} }
	h.bg = player:hud_add({ hud_elem_type = "image", position = { x = 0, y = 0 }, alignment = { x = 1, y = 1 }, text = tex_fill(1, 1, "#00000000"), scale = { x = 1, y = 1 }, offset = { x = 0, y = 0 }, z_index = -1 })
	h.icon = player:hud_add({ hud_elem_type = "inventory", position = { x = 0, y = 0 }, alignment = { x = 1, y = 1 }, text = "identifiable_icon", number = 1, item = 0, direction = 0, offset = { x = 0, y = 0 }, text2 = tex_fill(1, 1, "#00000000"), z_index = 1 })
	for i = 1, MAXL do
		h.lines[i] = player:hud_add({ hud_elem_type = "text", position = { x = 0, y = 0 }, alignment = { x = 1, y = 1 }, text = "", number = 0xFFFFFF, offset = { x = 0, y = 0 }, size = { x = 1, y = 0 }, z_index = 2 })
	end
	h.track = player:hud_add({ hud_elem_type = "image", position = { x = 0, y = 0 }, alignment = { x = 1, y = 1 }, text = tex_fill(1, 1, "#00000000"), scale = { x = 1, y = 1 }, offset = { x = 0, y = 0 }, z_index = 1 })
	h.fill = player:hud_add({ hud_elem_type = "image", position = { x = 0, y = 0 }, alignment = { x = 1, y = 1 }, text = tex_fill(1, 1, "#00000000"), scale = { x = 1, y = 1 }, offset = { x = 0, y = 0 }, z_index = 2 })
	huds[name] = h
	return h
end

function id.hud(player) return huds[player:get_player_name()] or create(player) end

-- pixel estimates (the server cannot measure text): a line is about 22 px high and each character about 9 px at "normal"
local LINE_H, CHAR_W, ICON_W, PAD = 22, 9.0, 60, 8


-- Plain (translated to English) text of a line and its length in characters.
local function plain(text) return (core.get_translated_string("en", text):gsub("\27%(T@[^)]*%)", ""):gsub("\27[FE]", "")) end
local function clen(s) return #(s:gsub("[\128-\191]", "")) end
function id.plain(text) return plain(text) end
id.clen = clen

-- How many characters fit in a line: the panel is never wider than half the screen (real window size when the client has reported it).
function id.chars_per_line(player, has_icon, cfg)
	local win = core.get_player_window_information(player:get_player_name())
	local W = win and win.size and win.size.x or 1280
	local scale = win and win.real_hud_scaling or 1
	local mult = id.SIZES[cfg.text_size] or 1
	local textmax = (W / 2) / scale - PAD * 2 - (has_icon and ICON_W * mult or 0)
	return math.max(10, math.floor(textmax / (CHAR_W * mult)))
end

-- Wraps lines longer than cpl characters at spaces (or hard); pieces keep the colour and the `keep` flag. Short lines are returned untouched
-- (so they stay translatable on the client); wrapped ones are English text.
function id.wrap(lines, cpl)
	local out = {}
	for _, l in ipairs(lines) do
		local text = plain(l.text)
		if clen(text) <= cpl then out[#out + 1] = l
		else
			local cur = ""
			local function flush() if cur ~= "" then out[#out + 1] = { text = cur, color = l.color, keep = l.keep }; cur = "" end end
			for word in text:gmatch("%S+") do
				while clen(word) > cpl do -- one very long word: hard break
					flush()
					local cut, n = 1, 0 -- byte index after cpl characters (LuaJIT has no utf8 library)
					while n < cpl do local _, e = word:find("^[%z\1-\127\194-\244][\128-\191]*", cut); cut = e + 1; n = n + 1 end
					out[#out + 1] = { text = word:sub(1, cut - 1), color = l.color, keep = l.keep }
					word = word:sub(cut)
				end
				if cur == "" then cur = word elseif clen(cur) + 1 + clen(word) <= cpl then cur = cur .. " " .. word else flush(); cur = word end
			end
			flush()
		end
	end
	return out
end

-- At most `max` lines; lines flagged keep (the id and the mod name) always stay, at the end.
function id.limit(lines, max)
	if #lines <= max then return lines end
	local kept, rest = {}, {}
	for _, l in ipairs(lines) do if l.keep then kept[#kept + 1] = l else rest[#rest + 1] = l end end
	local out = {}
	for i = 1, math.max(1, max - #kept) do if rest[i] then out[#out + 1] = rest[i] end end
	for _, l in ipairs(kept) do out[#out + 1] = l end
	return out
end

-- lines = { {text, color}... } (first = title); icon = itemname or nil. hidden = no panel at all.
function id.show(player, lines, icon, cfg, progress)
	local h = id.hud(player)
	local name = player:get_player_name()
	local mult = id.SIZES[cfg.text_size] or 1
	local lh, cw = LINE_H * mult, CHAR_W * mult
	local color = id.COLORS[cfg.hud_color] or 0xFFFFFF
	local maxc = 0
	for _, l in ipairs(lines) do maxc = math.max(maxc, #(core.get_translated_string("en", l.text):gsub("[\128-\191]", ""))) end
	local textw = maxc * cw
	local icon_w = icon and (ICON_W * mult) or 0
	local total_w = textw + icon_w + PAD * 2
	local BAR_H = 6
	local total_h = math.max(#lines * lh, icon and ICON_W * mult or 0) + PAD * 2 + (progress and (BAR_H + PAD / 2) or 0)
	-- anchor: x,y are fractions of the screen; the panel's top-left corner is at (x,y) in manual mode; for left/center/right it is
	-- placed at 10% in / centred / 10% in from the right and its y is hud_y
	local px, py = cfg.hud_x, cfg.hud_y
	local off_x = 0
	if cfg.align == "left" then px = 0.10
	elseif cfg.align == "center" then px = 0.5; off_x = -total_w / 2
	elseif cfg.align == "right" then px = 0.90; off_x = -total_w end

	local function set(hud_id, field, value, key)
		local k = key .. field
		local s = core.serialize(value)
		if h.last[k] ~= s then h.last[k] = s; player:hud_change(hud_id, field, value) end
	end
	-- background
	if cfg.background_style == "dark" then
		set(h.bg, "text", tex_fill(total_w, total_h, "#000000A0"), "bg")
	elseif FRAMES[cfg.background_style] then
		local f = FRAMES[cfg.background_style]
		set(h.bg, "text", tex_frame(total_w, total_h, f[1], f[2], f[3]), "bg")
	else
		set(h.bg, "text", tex_fill(1, 1, "#00000000"), "bg")
	end
	set(h.bg, "position", { x = px, y = py }, "bg"); set(h.bg, "offset", { x = off_x, y = 0 }, "bg")
	-- breaking progress bar along the bottom edge
	if progress then
		local bw = total_w - PAD * 2
		set(h.track, "text", tex_fill(bw, BAR_H, "#000000C0"), "tr")
		set(h.fill, "text", tex_fill(math.max(1, bw * progress), BAR_H, "#55FF55"), "fi")
		for _, e in ipairs({ { h.track, "tr" }, { h.fill, "fi" } }) do
			set(e[1], "position", { x = px, y = py }, e[2]); set(e[1], "offset", { x = off_x + PAD, y = total_h - PAD / 2 - BAR_H - 2 }, e[2])
		end
	else
		set(h.track, "text", tex_fill(1, 1, "#00000000"), "tr"); set(h.fill, "text", tex_fill(1, 1, "#00000000"), "fi")
	end
	-- icon (the item sits in a list of the player's inventory)
	local inv = player:get_inventory()
	if icon then
		local st = ItemStack(icon)
		if inv:get_stack("identifiable_icon", 1):to_string() ~= st:to_string() then inv:set_stack("identifiable_icon", 1, st) end
		set(h.icon, "position", { x = px, y = py }, "ic"); set(h.icon, "offset", { x = off_x + PAD, y = PAD }, "ic")
		set(h.icon, "number", 1, "ic")
	else
		if not inv:get_stack("identifiable_icon", 1):is_empty() then inv:set_stack("identifiable_icon", 1, ItemStack("")) end
		set(h.icon, "number", 0, "ic")
	end
	-- text lines; "center" text align puts them in the middle of the text area
	local tx = off_x + PAD + icon_w
	for i = 1, MAXL do
		local l = lines[i]
		if l then
			local lw = #(core.get_translated_string("en", l.text):gsub("[\128-\191]", "")) * cw
			local x = tx
			if cfg.text_align == "center" then x = tx + (textw - lw) / 2 end
			set(h.lines[i], "position", { x = px, y = py }, "l" .. i)
			set(h.lines[i], "offset", { x = x, y = PAD + (i - 1) * lh }, "l" .. i)
			set(h.lines[i], "size", { x = mult, y = 0 }, "l" .. i)
			set(h.lines[i], "number", l.color or color, "l" .. i)
			set(h.lines[i], "text", l.text, "l" .. i)
		else
			set(h.lines[i], "text", "", "l" .. i)
		end
	end
	h.shown = true
end

function id.clear(player)
	local h = huds[player:get_player_name()]
	if not h or not h.shown then return end
	player:hud_change(h.bg, "text", tex_fill(1, 1, "#00000000")); h.last = {}
	player:hud_change(h.track, "text", tex_fill(1, 1, "#00000000")); player:hud_change(h.fill, "text", tex_fill(1, 1, "#00000000"))
	player:get_inventory():set_stack("identifiable_icon", 1, ItemStack(""))
	player:hud_change(h.icon, "number", 0)
	for i = 1, MAXL do player:hud_change(h.lines[i], "text", "") end
	h.shown = false
end

core.register_on_joinplayer(function(p) create(p) end)
core.register_on_leaveplayer(function(p) huds[p:get_player_name()] = nil end)
