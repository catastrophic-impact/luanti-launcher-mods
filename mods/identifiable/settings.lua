-- Per-player settings (player meta), defaults as in the Fabric mod.
local S = core.get_translator("identifiable")
local id = identifiable

id.defaults = {
	enabled = true, show_id = true, show_mod_name = true, show_icon = true, show_health = true, show_armor = true,
	show_player_health = false, show_block_details = true, show_harvest = true, light_mode = "off", show_spawnable = false,
	show_villager = true, show_items = true, show_spawner = true, show_breaking = true, text_align = "left",
	hud_x = 0.2, hud_y = 0.05, align = "manual", hud_color = "white", text_size = "normal", background_style = "dark", range = 5,
	hidden = {},
}
id.COLORS = {
	white = 0xFFFFFF, yellow = 0xFFFF55, red = 0xFF5555, green = 0x55FF55, blue = 0x5555FF, aqua = 0x55FFFF,
	gold = 0xFFAA00, light_purple = 0xFF55FF, gray = 0xAAAAAA,
}
id.COLOR_ORDER = { "white", "yellow", "red", "green", "blue", "aqua", "gold", "light_purple", "gray" }
id.SIZES = { small = 0.8, normal = 1.0, large = 1.4, huge = 2.0 }
id.SIZE_ORDER = { "small", "normal", "large", "huge" }
id.BACKGROUNDS = { "dark", "button", "advancement", "tooltip", "none" }
id.RANGES = { 5, 10, 16, 32 }
id.LIGHT_MODES = { "off", "light", "sky", "both", "combined" }
id.ALIGNS = { "manual", "left", "center", "right" }

local cache = {}
function id.get(player)
	local name = player:get_player_name()
	if cache[name] then return cache[name] end
	local d = core.deserialize(player:get_meta():get_string("identifiable:cfg"))
	local cfg = table.copy(id.defaults)
	if type(d) == "table" then for k, v in pairs(d) do if id.defaults[k] ~= nil then cfg[k] = v end end end
	cache[name] = cfg
	return cfg
end
function id.save(player)
	player:get_meta():set_string("identifiable:cfg", core.serialize(id.get(player)))
end
function id.reset(player)
	local cfg = id.get(player)
	local hidden = cfg.hidden -- the blacklist stays
	for k, v in pairs(id.defaults) do cfg[k] = (type(v) == "table") and table.copy(v) or v end
	cfg.hidden = hidden
	id.save(player)
end
core.register_on_leaveplayer(function(p) cache[p:get_player_name()] = nil end)

function id.cycle(list, cur)
	for i, v in ipairs(list) do if v == cur then return list[i % #list + 1] end end
	return list[1]
end
