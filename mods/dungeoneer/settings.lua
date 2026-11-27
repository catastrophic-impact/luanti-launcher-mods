-- /dungeon settings (and the HQ shortcut): per world, only operators (and the owner of a single-player world) can change them.
local S = core.get_translator("dungeoneer")
local function can_edit(name) return core.check_player_privs(name, "server") or core.is_singleplayer() end

dungeoneer.settings_screen = uikit.screen({
	name = "dungeoneer:settings", title = S("Dungeoneer"), width = 10,
	can = can_edit, denied = S("Only the world owner or an operator can change this."),
	rows = {
		{ type = "field", id = "reset_minutes", label = S("Minutes an empty dungeon lives (1-1440)"), button = S("Save"), button_name = "save_reset_minutes",
			get = function() return tostring(dungeoneer.reset_minutes()) end, set = function(_, v) dungeoneer.set_setting("reset_minutes", v) end },
		{ type = "field", id = "grave_grace_minutes", label = S("Extra minutes while a chest or grave still holds items (0-10080)"), button = S("Save"), button_name = "save_grave",
			get = function() return tostring(dungeoneer.grave_grace_minutes()) end, set = function(_, v) dungeoneer.set_setting("grave_grace_minutes", v) end },
		{ type = "toggle", id = "reset_on_death", label = S("Reset as soon as it is empty after a player died"),
			get = function() return dungeoneer.reset_on_death() end, set = function(_, v) dungeoneer.set_setting("reset_on_death", v) end },
		{ type = "text", text = S("Dungeons are built with Dungeon Keys at a lit Dungeon Portal."), dim = true },
	},
})

if core.get_modpath("hq") then
	hq.register_shortcut({ id = "dungeoneer", name = "Dungeoneer", func = function(player) dungeoneer.settings_screen.show(player:get_player_name()) end, icon = "dungeoneer:key_1", short = "DG" })
end
