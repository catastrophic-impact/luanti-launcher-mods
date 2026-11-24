-- Peace and Quiet (Luanti/Mineclonia port). Fabric hides the client's toast popups; here the only toasts Mineclonia has are the
-- advancement popups (awards HUD panel + sound). Recipe, tutorial and system toasts do not exist in Mineclonia, so there is one switch.
-- The advancement is still unlocked and its prizes/xp still given; the chat line (mcl_showAdvancementMessages) is not a toast and stays.
-- Settings are per player (player meta "peaceandquiet:hide_advancements"), hidden by default, kept on that server/world.
local S = core.get_translator("peaceandquiet")
local esc = core.formspec_escape
peaceandquiet = {}
local KEY = "peaceandquiet:hide_advancements"

function peaceandquiet.hides_advancements(name)
	local p = core.get_player_by_name(name)
	if not p then return false end
	local v = p:get_meta():get_string(KEY)
	return v ~= "false" -- default: hidden
end
function peaceandquiet.set_hide_advancements(name, on)
	local p = core.get_player_by_name(name)
	if p then p:get_meta():set_string(KEY, on and "true" or "false") end
end

-- awards runs these after the award is saved and its prizes are given; returning true skips the sound and the popup.
-- (depends = mcl_achievements so Mineclonia's own xp-reward callback is registered, and runs, before this one)
awards.register_on_unlock(function(name, def)
	if peaceandquiet.hides_advancements(name) then return true end
end)

uikit.screen({
	name = "peaceandquiet:main", title = S("Peace and Quiet"), command = "peaceandquiet", description = S("Open the Peace and Quiet settings"),
	rows = {
		{ type = "toggle", id = "hide_adv", label = S("Hide advancement popups"), get = function(name) return peaceandquiet.hides_advancements(name) end,
			set = function(name, v) peaceandquiet.set_hide_advancements(name, v) end,
			tooltip = S("The popup and sound for Advancement Made, Goal Reached and Challenge Complete. Advancements still unlock as normal.") },
		{ type = "text", text = S("Recipe, tutorial and system popups do not exist in Mineclonia."), dim = true },
	},
})

if core.get_modpath("hq") then
	hq.register_shortcut({ id = "peaceandquiet", name = "Peace and Quiet", command = "peaceandquiet", icon = "mcl_bells:bell", short = "PQ" })
end
