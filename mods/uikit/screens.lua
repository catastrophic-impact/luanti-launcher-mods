-- uikit.screen{...}: a declarative settings screen (title, a panel of rows, Close below). Most of our mods need exactly this.
--   uikit.screen{
--     name = "mymod:main",                      -- formname
--     title = S("My Mod"), width = 9,           -- width default 9
--     command = "mymod", description = S(".."), -- optional: registers the chat command that opens it
--     can = function(name) return true end,     -- optional: false = rows become read-only text and `denied` is shown
--     denied = S("Only the owner can change this."),
--     on_change = function(name, row) end,      -- optional: after any value was set
--     rows = {
--       { type = "toggle", id = "pvp", label = S("PvP"), get = function(name) return true end, set = function(name, bool) end, tooltip = S("..") },
--       { type = "choice", id = "armor", label = S("Armor"), choices = { "none", "iron" }, names = { none = S("None") }, get = fn(name) -> value, set = fn(name, value) },
--       { type = "field", id = "blacklist", label = S(".."), get = fn(name) -> string, set = fn(name, string), button = S("Save"), button_name = "save" },
--       { type = "text", text = S("note") | fn(name), dim = true },
--       { type = "gap" },
--     },
--   }
-- Returns { show = function(name), formspec = function(name) }. A click on a toggle flips it ("true"/"false" set it directly), a click on a
-- choice goes to the next value (a value that is one of the choices sets it directly), a field is stored when its button is pressed.
local esc = core.formspec_escape
local S = core.get_translator("uikit")

function uikit.screen(def)
	local W = def.width or 9
	local H, G = uikit.row_h, uikit.gap
	local CX, CW = 0.5, W - 1.0
	local scr = {}

	local function allowed(name) return not def.can or def.can(name) end

	function scr.formspec(name)
		local can = allowed(name)
		local player = core.get_player_by_name(name)
		local body, y = {}, 1.0
		for _, r in ipairs(def.rows) do
			if r.type == "toggle" then
				local v = r.get(name)
				if can then body[#body + 1] = uikit.toggle(CX, y, CW, H, r.id, r.label, v)
				else body[#body + 1] = string.format("label[%.2f,%.2f;%s]", CX, y + H / 2, esc(r.label .. ": " .. (v and S("On") or S("Off")))) end
				if r.tooltip then body[#body + 1] = string.format("tooltip[%s;%s]", r.id, esc(r.tooltip)) end
				y = y + H + G
			elseif r.type == "choice" then
				local v = r.get(name)
				local shown = (r.names and r.names[v]) or tostring(v)
				if can then body[#body + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;%s;%s]", CX, y, CW, H, r.id, esc(r.label .. ": " .. shown))
				else body[#body + 1] = string.format("label[%.2f,%.2f;%s]", CX, y + H / 2, esc(r.label .. ": " .. shown)) end
				y = y + H + G
			elseif r.type == "field" then
				body[#body + 1] = string.format("label[%.2f,%.2f;%s]", CX, y + 0.2, esc(r.label))
				if can then
					local bw = 1.6
					body[#body + 1] = uikit.field(CX, y + 0.45, CW - bw - G, H, r.id, r.get(name))
					body[#body + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;%s;%s]", CX + CW - bw, y + 0.45, bw, H, r.button_name or ("save_" .. r.id), esc(r.button or S("Save")))
				else
					body[#body + 1] = string.format("label[%.2f,%.2f;%s]", CX, y + 0.7, esc(tostring(r.get(name))))
				end
				y = y + 0.45 + H + G + 0.1
			elseif r.type == "text" then
				local text = type(r.text) == "function" and r.text(name) or r.text
				body[#body + 1] = string.format("label[%.2f,%.2f;%s]", CX, y + 0.25, esc(core.colorize(r.dim and "#a0a0a0" or "#ffffff", text)))
				y = y + 0.5
			elseif r.type == "gap" then
				y = y + 0.3
			end
		end
		if not can and def.denied then
			body[#body + 1] = string.format("label[%.2f,%.2f;%s]", CX, y + 0.25, esc(def.denied))
			y = y + 0.6
		end
		local panel_h = y + 0.15 - 0.7
		local total = 0.7 + panel_h + 0.25 + H + 0.3
		return table.concat({
			uikit.begin(player, W, total), uikit.title(W, def.title, 0), uikit.panel(0.2, 0.7, W - 0.4, panel_h),
			table.concat(body),
			string.format("button_exit[%.2f,%.2f;3.0,%.2f;close;%s]", (W - 3.0) / 2, 0.7 + panel_h + 0.25, H, esc(S("Close"))),
		})
	end

	function scr.show(name) core.show_formspec(name, def.name, scr.formspec(name)) end

	core.register_on_player_receive_fields(function(player, formname, fields)
		if formname ~= def.name then return end
		local name = player:get_player_name()
		if not allowed(name) then return true end
		for _, r in ipairs(def.rows) do
			local f = r.id and fields[r.id]
			if r.type == "toggle" and f ~= nil then
				r.set(name, uikit.flip(r.get(name), f)); if def.on_change then def.on_change(name, r) end
			elseif r.type == "choice" and f ~= nil then
				local cur, idx = r.get(name), nil
				for i, c in ipairs(r.choices) do if c == f then idx = i end end            -- a listed value sets it directly
				if not idx then for i, c in ipairs(r.choices) do if c == cur then idx = (i % #r.choices) + 1 end end end -- a click cycles
				r.set(name, r.choices[idx or 1]); if def.on_change then def.on_change(name, r) end
			elseif r.type == "field" and fields[r.button_name or ("save_" .. r.id)] and f ~= nil then
				r.set(name, f); if def.on_change then def.on_change(name, r) end
			end
		end
		if not fields.quit then scr.show(name) end
		return true
	end)

	if def.command then
		core.register_chatcommand(def.command, { description = def.description or def.title, func = function(name) scr.show(name); return true end })
	end
	return scr
end
