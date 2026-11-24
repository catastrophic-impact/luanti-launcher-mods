-- Runtime settings, editable by the server owner / operators from the /tameful screen. Stored in mod storage.
local storage = tameful.storage

local defaults = {
	consume_lead = true,   -- the lead is used up when an animal is tamed
	max_tames = 10,        -- max pets per player (0 = unlimited)
	max_summoned = 1,      -- max pets out in the world at once (0 = unlimited)
	downed_seconds = 30,   -- recovery time of a downed pet in the stable
	immortal = true,       -- pets are downed instead of dying for good
	follow_teleport = 24,
	show_name = true,      -- write the pet's name above it
	show_health = false,   -- and its health on its own line
	show_owner = false,    -- and its owner on its own line
	regen_health = true,   -- pets heal 1 health every 2 s after 10 s without damage  -- a following pet farther away than this is brought next to you
}
local stored = core.deserialize(storage:get_string("settings")) or {}

tameful.cfg = {}
function tameful.cfg.get(key)
	local v = stored[key]
	if v == nil then return defaults[key] end
	return v
end
function tameful.cfg.set(key, value)
	if defaults[key] == nil then return end
	stored[key] = value
	storage:set_string("settings", core.serialize(stored))
end
tameful.cfg.defaults = defaults

function tameful.can_edit_settings(name)
	return core.is_singleplayer() or core.check_player_privs(name, { server = true })
end
