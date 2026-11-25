-- Main loop, zoom, commands.
local S = core.get_translator("identifiable")
local id = identifiable
local state = {} -- state[name] = { last_key, last_display, panel_hidden, zoom, zoom_idx, config = false/"main"/"pos" }
local function st(player) local n = player:get_player_name(); state[n] = state[n] or {}; return state[n] end
id.state = st

local INTERVAL = 0.1
local ZOOM_MIN, ZOOM_MAX, ZOOM_START, ZOOM_RANGE = 2, 10, 4, 128
local BASE_FOV = 72 -- Luanti's default field of view; the zoom key (native, glides in, slows the mouse) then shows BASE_FOV / zoom
local acc = 0

-- zoom_fov = 0 disables the engine's zoom key, so every player gets a value; the factor changes with the mouse wheel
core.register_on_joinplayer(function(player) player:set_properties({ zoom_fov = BASE_FOV / ZOOM_START }) end)

local function sample_lines(cfg)
	return { { text = S("[Config Mode]") }, { text = "♥ 15 / 20" }, { text = S("Armor: @1", 2) }, { text = "mobs_mc:cow", color = cfg.show_id and 0xAAAAAA or nil }, { text = "Mineclonia", color = 0x5555FF } }
end

local function update(player)
	local cfg = id.get(player)
	local s = st(player)
	if s.config == "pos" then -- position mode: a sample panel to move around
		id.show(player, sample_lines(cfg), cfg.show_icon and "mcl_core:stone" or nil, cfg)
		return
	elseif s.config then -- the settings screen has its own live preview
		id.clear(player)
		return
	end
	if not cfg.enabled or s.panel_hidden then id.clear(player); return end
	local range = s.zoom and ZOOM_RANGE or cfg.range
	local t = id.find_target(player, range, cfg)
	if not t then s.last_key, s.target_pos = nil, nil; id.clear(player); return end
	s.target_pos = (t.kind == "node" and t.pointed and t.pointed.under) or nil
	local info = id.describe(player, t, cfg)
	s.last_key, s.last_display = info.key, info.display
	local lines
	if info.key and cfg.hidden[info.key] then
		lines = { { text = S("Hidden: @1", info.display or "?") } }
	else
		lines = { { text = info.title } }
		for _, l in ipairs(info.lines) do lines[#lines + 1] = l end
		-- long lines wrap (panel at most half the screen wide); at most 8 lines, the id and mod name always stay
		lines = id.limit(id.wrap(lines, id.chars_per_line(player, info.icon ~= nil and cfg.show_icon, cfg)), 8)
	end
	id.show(player, lines, (not (info.key and cfg.hidden[info.key])) and info.icon or nil, cfg, s.dig_progress)
end

core.register_globalstep(function(dtime)
	acc = acc + dtime
	local do_scan = acc >= INTERVAL
	if do_scan then acc = 0 end
	for _, player in ipairs(core.get_connected_players()) do
		local s = st(player)
		local ctl = player:get_player_control()
		-- Zoom: hold the zoom key (default Z); the mouse wheel (hotbar change) adjusts 2x-10x instead of changing the slot
		if ctl.zoom and id.get(player).enabled then
			local idx = player:get_wield_index()
			if not s.zoom then
				s.zoom, s.zoom_idx = ZOOM_START, idx
				player:set_properties({ zoom_fov = BASE_FOV / s.zoom })
			elseif idx ~= s.zoom_idx then
				local size = player:hud_get_hotbar_itemcount() or 8
				local d = (idx - s.zoom_idx) % size
				if d > size / 2 then d = d - size end
				s.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, s.zoom - d)) -- wheel up (previous slot) zooms in
				player:set_wield_index(s.zoom_idx)
				player:set_properties({ zoom_fov = BASE_FOV / s.zoom })
			end
		elseif s.zoom then
			s.zoom, s.zoom_idx = nil, nil
			player:set_properties({ zoom_fov = BASE_FOV / ZOOM_START }) -- ready for the next zoom
		end
		-- breaking progress (survival only): estimated from how long dig is held on the same node
		local cfg = id.get(player)
		local survival = not (mcl_gamemode and mcl_gamemode.get_gamemode(player) == "creative")
		if cfg.show_breaking and survival and ctl.dig and s.target_pos then
			if not (s.dig and vector.equals(s.dig.pos, s.target_pos)) then s.dig_need = id.dig_time(player, s.target_pos) end
			s.dig_progress = id.dig_step(s, dtime, true, s.target_pos, s.dig_need)
		else
			s.dig_progress = id.dig_step(s, dtime, false)
		end
		if do_scan then update(player) end
	end
end)

core.register_on_leaveplayer(function(p) state[p:get_player_name()] = nil end)

-- Commands (Luanti has no client key bindings for server mods: these are the "hide" keys; HQ gives them buttons)
core.register_chatcommand("idhide", {
	description = S("Hide or show the Identifiable panel"),
	func = function(name)
		local p = core.get_player_by_name(name); if not p then return end
		local s = st(p); s.panel_hidden = not s.panel_hidden
		return true, s.panel_hidden and S("Panel hidden.") or S("Panel shown.")
	end,
})
core.register_chatcommand("idblacklist", {
	description = S("Hide (or show again) what you are looking at"),
	func = function(name)
		local p = core.get_player_by_name(name); if not p then return end
		local s, cfg = st(p), id.get(p)
		if not s.last_key then return false, S("Look at something first.") end
		if cfg.hidden[s.last_key] then cfg.hidden[s.last_key] = nil; id.save(p); return true, S("Showing @1 again.", s.last_display or "")
		else cfg.hidden[s.last_key] = true; id.save(p); return true, S("Hiding @1.", s.last_display or "") end
	end,
})

if core.get_modpath("hq") then
	hq.register_shortcut({ id = "identifiable", name = "Identifiable", command = "idconfig", icon = "mcl_compass:compass", short = "ID" })
end
