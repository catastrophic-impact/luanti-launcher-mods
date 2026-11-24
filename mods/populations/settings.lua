-- Settings, kept in mod storage and changed in game with /pop (singleplayer owner or "server" priv).
local storage = core.get_mod_storage()
local S = core.get_translator("populations")

local cfg = {}
populations.cfg = cfg

cfg.armor_choices = { "none", "leather", "chain", "copper", "iron", "gold", "diamond", "netherite" }
cfg.sword_choices = { "wood", "stone", "copper", "iron", "gold", "diamond", "netherite" }

local defaults = {
	stronger_golems = true,
	villagers_defend_themselves = true,
	villagers_can_aid_others = true,
	villager_armor = "leather",
	villager_sword = "stone",
}
local bools = { stronger_golems = true, villagers_defend_themselves = true, villagers_can_aid_others = true }

local values = {}
for k, v in pairs(defaults) do
	local raw = storage:get_string("cfg_" .. k)
	if raw == "" then
		values[k] = v
	elseif bools[k] then
		values[k] = raw == "true"
	else
		values[k] = raw
	end
end

local function valid(k, v)
	if bools[k] then return type(v) == "boolean" end
	local list = k == "villager_armor" and cfg.armor_choices or cfg.sword_choices
	for _, x in ipairs(list) do if x == v then return true end end
	return false
end

function cfg.get(k) return values[k] end
function cfg.set(k, v)
	if defaults[k] == nil or not valid(k, v) then return false end
	values[k] = v
	storage:set_string("cfg_" .. k, tostring(v))
	return true
end

local function can_change(name)
	return core.is_singleplayer() or core.check_player_privs(name, { server = true })
end

local function bool_row(key, label)
	return { type = "toggle", id = key, label = label, get = function() return values[key] end, set = function(_, v) cfg.set(key, v) end }
end
local function choice_row(key, label, choices)
	return { type = "choice", id = key, label = label, choices = choices, get = function() return values[key] end, set = function(_, v) cfg.set(key, v) end }
end
local screen = uikit.screen({
	name = "populations:settings", title = S("Populations"), command = "pop", description = S("Open the Populations settings screen"),
	can = can_change, denied = S("Only the world owner or operators can change these."),
	on_change = function(_, row) if row.id == "stronger_golems" and populations.refresh_golems then populations.refresh_golems() end end,
	rows = {
		bool_row("stronger_golems", S("Stronger iron golems")),
		bool_row("villagers_defend_themselves", S("Villagers defend themselves")),
		bool_row("villagers_can_aid_others", S("Villagers come to help each other")),
		{ type = "gap" },
		choice_row("villager_armor", S("Armor in a fight"), cfg.armor_choices),
		choice_row("villager_sword", S("Sword in a fight"), cfg.sword_choices),
	},
})
cfg.formspec = screen.formspec
