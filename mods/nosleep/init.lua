-- NoSleep (Luanti/Mineclonia port of the Fabric "Wide Awake" mod).
-- Using a bed sets your respawn point at any time of day, the Mineclonia way (spawn is stored on the bed; a broken/blocked bed loses it),
-- but you never lie down, so the night cannot be skipped. "Respawn point set" shows above the hotbar instead of in chat (beds and
-- respawn anchors). Beds still explode in the Nether and the End. /nosleep opens the settings (world owner / server priv).
-- Mineclonia has no phantoms, so the Fabric setting bed_counts_as_rest does not exist here.
local S = core.get_translator("nosleep")
local esc = core.formspec_escape
local storage = core.get_mod_storage()
nosleep = {}

local function allow_sleeping() return storage:get_string("allow_sleeping") == "true" end
nosleep.allow_sleeping = allow_sleeping

local function actionbar(player, text)
	mcl_title.set(player, "actionbar", { text = text, color = "white", stay = 60 })
end

-- Beds -------------------------------------------------------------------------------------------------------------------
local orig_on_rightclick = mcl_beds.on_rightclick
function mcl_beds.on_rightclick(pos, player, is_top, is_straw_bed)
	if allow_sleeping() or is_straw_bed then return orig_on_rightclick(pos, player, is_top, is_straw_bed) end
	local dim = mcl_worlds.pos_to_dimension(pos)
	if dim == "nether" or dim == "end" then return orig_on_rightclick(pos, player, is_top, is_straw_bed) end -- beds still explode there
	if player:get_meta():get_string("mcl_beds:sleeping") == "true" then return end -- already in bed (before the setting changed)
	local top = is_top and pos or mcl_beds.get_bed_top(pos)
	local bottom = mcl_beds.get_bed_bottom(top)
	if not top or not bottom then return end
	-- the same rules Mineclonia applies when you lie down: the space above both halves must be free and safe
	for _, p in ipairs({ top, bottom }) do
		local def = core.registered_nodes[core.get_node(vector.offset(p, 0, 1, 0)).name]
		if def and def.walkable then actionbar(player, S("The bed is obstructed!")); return end
		if def and (def.damage_per_second or 0) > 0 then actionbar(player, S("It is too dangerous here!")); return end
	end
	-- (set_spawn_pos reports "New respawn position set!" through chat; that message is turned into the action bar below)
	local changed = mcl_spawn.set_spawn_pos(player, top, true)
	if not changed then actionbar(player, S("Respawn point set")) end -- same bed again: no chat message, still confirm
	return mcl_util.return_itemstack_if_alive(player)
end

-- "Respawn point set" above the hotbar (beds and respawn anchors both announce it with this chat message) --------------------
local MSG = {
	[core.get_translator("mcl_beds")("New respawn position set!")] = true,
	[core.get_translator("mcl_spawn")("New respawn position set!")] = true,
}
local orig_chat = core.chat_send_player
core.chat_send_player = function(name, text)
	if MSG[text] then
		local p = core.get_player_by_name(name)
		if p then actionbar(p, S("Respawn point set")); return end
	end
	return orig_chat(name, text)
end

-- Settings screen --------------------------------------------------------------------------------------------------------------
local function can_edit(name) return core.is_singleplayer() or core.check_player_privs(name, { server = true }) end

uikit.screen({
	name = "nosleep:main", title = S("No Sleep"), command = "nosleep", description = S("Open the No Sleep settings"),
	can = can_edit, denied = S("Only the world owner or an operator can change this."),
	rows = {
		{ type = "toggle", id = "allow", label = S("Allow sleeping again (beds work like vanilla)"), get = function() return allow_sleeping() end,
			set = function(_, v) storage:set_string("allow_sleeping", v and "true" or "false") end },
		{ type = "text", text = S("Beds set your respawn point any time of day."), dim = true },
	},
})

if core.get_modpath("hq") then
	hq.register_shortcut({ id = "nosleep", name = "No Sleep", command = "nosleep", icon = "mcl_beds:bed_red", short = "NS" })
end
