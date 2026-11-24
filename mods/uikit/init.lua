-- uikit: one shared look for every screen our mods draw.
-- Theme = the tables below + the textures made by tools/make_ui_textures.py (original art). Players can change a few things in /uikit (settings.lua).
-- Use:  local fs = uikit.begin(player, 17, 10.8) .. uikit.title(17, "HQ") .. uikit.panel(0.4, 0.4, 8.4, 9.2) .. uikit.field(...) .. plain formspec elements
-- (button[], textlist[], ...) which are already styled by uikit.begin(). Line widgets up with uikit.cols() instead of typing x/width by hand.
uikit = {}
local esc = core.formspec_escape
local S = core.get_translator("uikit")
local path = core.get_modpath("uikit")

uikit.theme = {
	text_dim = "#a0a0a0",
	text_off = "#7c7c7c", -- disabled buttons
	accent   = "#ffd24a", -- the selected button of a group
	tex = { button = "uikit_button.png", hover = "uikit_button_hover.png", pressed = "uikit_button_pressed.png",
		disabled = "uikit_button_disabled.png", field = "uikit_field.png",
		panel = { glass = "uikit_panel.png", solid = "uikit_panel_solid.png" } },
	slice = 4, -- 9-slice border in texture pixels (textures are 16x16)
}
local T = uikit.theme

-- Player options: key -> { default, order = {...}, label, choices = { id = { name = shown text, ... values } } }
uikit.options = {
	{ key = "bg", label = "Background", default = "dim", choices = {
		clear = { name = "See-through", color = "#00000000" }, dim = { name = "Dimmed", color = "#00000050" }, dark = { name = "Dark", color = "#000000b4" } },
		order = { "clear", "dim", "dark" } },
	{ key = "panel", label = "Panels", default = "glass", choices = { glass = { name = "Glass" }, solid = { name = "Solid" } }, order = { "glass", "solid" } },
	{ key = "text", label = "Text color", default = "white", choices = {
		white = { name = "White", color = "#ffffff" }, soft = { name = "Light gray", color = "#d4d4d4" }, warm = { name = "Warm", color = "#ffe6a8" } },
		order = { "white", "soft", "warm" } },
	{ key = "size", label = "Text size", default = "normal", choices = {
		small = { name = "Small", size = "-2" }, normal = { name = "Normal" }, large = { name = "Large", size = "+3" } }, order = { "small", "normal", "large" } },
}
local by_key = {}
for _, o in ipairs(uikit.options) do by_key[o.key] = o end

-- Per-player settings (player meta). Always returns a complete table of valid choices.
function uikit.get(player)
	local out = {}
	local saved = player and core.deserialize(player:get_meta():get_string("uikit:settings")) or {}
	if type(saved) ~= "table" then saved = {} end
	for _, o in ipairs(uikit.options) do
		out[o.key] = (o.choices[saved[o.key]] and saved[o.key]) or o.default
	end
	return out
end
function uikit.set(player, key, value)
	local o = by_key[key]
	if not (o and o.choices[value]) then return false end
	local s = uikit.get(player); s[key] = value
	player:get_meta():set_string("uikit:settings", core.serialize(s))
	return true
end
function uikit.cycle(player, key)
	local o = by_key[key]; local s = uikit.get(player)
	for i, id in ipairs(o.order) do if id == s[key] then uikit.set(player, key, o.order[i % #o.order + 1]) return end end
end
local function choice(s, key) return by_key[key].choices[s[key]] end

local ctx = uikit.get(nil) -- settings of the screen being built (set by uikit.begin)

-- Style block that skins every stock element.
function uikit.styles(s)
	s = s or ctx
	local color = choice(s, "text").color
	local size = choice(s, "size").size
	local fs = size and (";font_size=" .. size) or ""
	local btn = "bgimg_middle=" .. T.slice .. ";border=false;textcolor=" .. color .. ";alpha=true" .. fs
	local out = {}
	for _, kind in ipairs({ "button", "button_exit", "item_image_button", "image_button" }) do
		out[#out + 1] = string.format("style_type[%s;bgimg=%s;%s]", kind, T.tex.button, btn)
		out[#out + 1] = string.format("style_type[%s:hovered;bgimg=%s;%s]", kind, T.tex.hover, btn)
		out[#out + 1] = string.format("style_type[%s:pressed;bgimg=%s;%s]", kind, T.tex.pressed, btn)
	end
	for _, kind in ipairs({ "field", "pwdfield", "textarea", "label" }) do
		out[#out + 1] = string.format("style_type[%s;textcolor=%s%s%s]", kind, color, kind ~= "label" and ";border=false" or "", fs)
	end
	return table.concat(out)
end

-- Select the player's settings for the helpers below without starting a screen (for hand-built headers). Returns the settings table.
function uikit.use(player) ctx = uikit.get(player); return ctx end

-- Start a screen for `player`: header + theme styles + the player's background. Optional extra = more header elements.
function uikit.begin(player, w, h, extra)
	ctx = uikit.get(player)
	-- no_prepend[] drops the game's own light window frame; the world shows behind our panels (how much: the player's Background setting).
	return string.format("formspec_version[6]size[%s,%s]no_prepend[]bgcolor[#00000000;true;%s]%s%s", w, h, choice(ctx, "bg").color, extra or "", uikit.styles(ctx))
end

-- A panel (glass = translucent with a thin light border, or solid).
function uikit.panel(x, y, w, h)
	return string.format("background9[%s,%s;%s,%s;%s;false;2]", x, y, w, h, T.tex.panel[ctx.panel])
end

local function text_color() return choice(ctx, "text").color end

-- Centered title across the screen width, at the top.
function uikit.title(w, text, y)
	return string.format("hypertext[0,%s;%s,0.7;;<global halign=center color=%s size=20>%s]", y or 0.15, w, text_color(), core.hypertext_escape(text))
end

-- A text block (dim = grey).
function uikit.text(x, y, w, h, text, dim)
	return string.format("hypertext[%s,%s;%s,%s;;<global halign=left color=%s>%s]", x, y, w, h, dim and T.text_dim or text_color(), core.hypertext_escape(text))
end

-- A text field with a black box and a light border behind it. close_on_enter defaults to false (our screens refresh instead of closing).
function uikit.field(x, y, w, h, name, default, close_on_enter)
	return string.format("background9[%s,%s;%s,%s;%s;false;2]field[%s,%s;%s,%s;%s;;%s]field_close_on_enter[%s;%s]",
		x, y, w, h, T.tex.field, x + 0.05, y, w - 0.1, h, name, esc(default or ""), name, close_on_enter and "true" or "false")
end

-- Make a named button look disabled (still clickable: the handler should ignore it).
function uikit.disabled(name)
	local s = "bgimg=" .. T.tex.disabled .. ";textcolor=" .. T.text_off .. ";bgimg_middle=" .. T.slice .. ";border=false"
	return string.format("style[%s;%s]style[%s:hovered;%s]style[%s:pressed;%s]", name, s, name, s, name, s)
end

-- Mark a named button as the selected one of a group (pressed-in look + accent text). Like disabled(): put it BEFORE the button.
function uikit.active(name)
	local s = "bgimg=" .. T.tex.pressed .. ";textcolor=" .. T.accent .. ";bgimg_middle=" .. T.slice .. ";border=false"
	return string.format("style[%s;%s]style[%s:hovered;%s]style[%s:pressed;%s]", name, s, name, s, name, s)
end

-- A "Label: On/Off" button (Fabric style). The caller flips the value when the button name arrives in the fields. On = gold text.
function uikit.toggle(x, y, w, h, name, label, on)
	local lit = on and string.format("style[%s;textcolor=%s]style[%s:hovered;textcolor=%s]style[%s:pressed;textcolor=%s]", name, T.accent, name, T.accent, name, T.accent) or ""
	return lit .. string.format("button[%s,%s;%s,%s;%s;%s]", x, y, w, h, name, esc(label .. ": " .. (on and S("On") or S("Off"))))
end

-- A row of tab buttons (the engine's tabheader cannot be themed). names = list of strings, selected = index; buttons are named prefix..index
-- (e.g. "tab_1"). Each tab is `tab_w` wide (default 2.6) starting at x.
function uikit.tabs(x, y, h, names, selected, prefix, tab_w)
	local out, w = {}, tab_w or 2.6
	for i, n in ipairs(names) do
		local name = prefix .. i
		if i == selected then out[#out + 1] = uikit.active(name) end
		out[#out + 1] = string.format("button[%s,%s;%s,%s;%s;%s]", x + (i - 1) * (w + 0.1), y, w, h, name, esc(n))
	end
	return table.concat(out)
end

-- New value of a boolean setting from a toggle's field: "true"/"false" set it, anything else (the button's label, i.e. a click) flips `current`.
function uikit.flip(current, f)
	if f == "true" then return true elseif f == "false" then return false end
	return not current
end

-- Thin separator line.
function uikit.rule(x, y, w) return string.format("box[%s,%s;%s,0.03;#ffffff40]", x, y, w) end

-- Layout: split the width `w` starting at `x` into columns with `gap` between them. `parts` = a count (equal columns) or a list of
-- weights, e.g. {2.5, 3, 1.8}; a weight written as a string like "0.8" is a FIXED width in formspec units. Returns { {x=, w=}, ... }
-- whose last column always ends exactly at x + w, so every row built from cols() lines up.
function uikit.cols(x, w, gap, parts)
	if type(parts) == "number" then local t = {}; for i = 1, parts do t[i] = 1 end; parts = t end
	local n, fixed, weights = #parts, 0, 0
	for _, p in ipairs(parts) do if type(p) == "string" then fixed = fixed + tonumber(p) else weights = weights + p end end
	local flex = w - gap * (n - 1) - fixed
	local out, cx = {}, x
	for i, p in ipairs(parts) do
		local cw = type(p) == "string" and tonumber(p) or flex * p / weights
		out[i] = { x = cx, w = cw }
		cx = cx + cw + gap
	end
	return out
end

uikit.row_h, uikit.gap = 0.75, 0.15 -- standard control height and spacing

dofile(path .. "/screens.lua")
dofile(path .. "/settings.lua")
