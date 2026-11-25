-- The /uikit settings window (per player) + HQ shortcut. Built with uikit itself, so it previews every change live.
local S = core.get_translator("uikit")
local FORM = "uikit:settings"

local function formspec(player)
	local W = 11
	local rows = math.ceil(#uikit.options / 2)
	local dy = (rows - 2) * (uikit.row_h + uikit.gap) -- room for options beyond two rows
	local t = { uikit.begin(player, W, 8.4 + dy), uikit.title(W, S("UI settings")) }
	local s = uikit.get(player)
	-- settings grid: one cycling button per option, two per row (like the Fabric settings screens)
	t[#t + 1] = uikit.panel(0.4, 0.8, 10.2, 2.25 + dy)
	local cols = uikit.cols(0.7, 9.6, 0.2, 2)
	for i, o in ipairs(uikit.options) do
		local c, r = (i - 1) % 2 + 1, math.floor((i - 1) / 2)
		t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;opt_%s;%s]", cols[c].x, 1.05 + r * (uikit.row_h + uikit.gap), cols[c].w, uikit.row_h,
			o.key, core.formspec_escape(S(o.label) .. ": " .. S(o.choices[s[o.key]].name)))
	end
	-- live preview
	t[#t + 1] = uikit.panel(0.4, 3.25 + dy, 10.2, 3.75)
	t[#t + 1] = "label[0.7," .. (3.65 + dy) .. ";" .. core.formspec_escape(S("Preview")) .. "]"
	t[#t + 1] = uikit.rule(0.7, 3.95 + dy, 9.6)
	local pc = uikit.cols(0.7, 9.6, 0.2, 3)
	t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;pv_a;%s]", pc[1].x, 4.15 + dy, pc[1].w, uikit.row_h, core.formspec_escape(S("Button")))
	t[#t + 1] = uikit.disabled("pv_b") -- style[] must come BEFORE the element it styles
	t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;pv_b;%s]", pc[2].x, 4.15 + dy, pc[2].w, uikit.row_h, core.formspec_escape(S("Disabled")))
	t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;pv_c;%s]", pc[3].x, 4.15 + dy, pc[3].w, uikit.row_h, core.formspec_escape(S("Another")))
	t[#t + 1] = uikit.field(0.7, 5.1 + dy, 9.6, uikit.row_h, "pv_field", S("A text field"))
	t[#t + 1] = uikit.text(0.7, 6.0 + dy, 9.6, 0.8, S("Normal text, and dim text below."))
	t[#t + 1] = uikit.text(0.7, 6.4 + dy, 9.6, 0.5, S("These changes only affect you."), true)
	t[#t + 1] = string.format("button_exit[%.2f,%.2f;3.0,%.2f;done;%s]", (W - 3.0) / 2, 7.3 + dy, uikit.row_h, core.formspec_escape(S("Done")))
	return table.concat(t)
end

function uikit.show_settings(player)
	core.show_formspec(player:get_player_name(), FORM, formspec(player))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then return end
	for _, o in ipairs(uikit.options) do
		if fields["opt_" .. o.key] then uikit.cycle(player, o.key) end
	end
	if not fields.quit then uikit.show_settings(player) end
	return true
end)

core.register_chatcommand("uikit", {
	description = S("Open the UI settings (background, panels, text color and size)"),
	func = function(name)
		local p = core.get_player_by_name(name)
		if p then uikit.show_settings(p) end
		return true
	end,
})

-- HQ gets a shortcut for it (hq loads after us, so register once all mods are loaded).
core.register_on_mods_loaded(function()
	if rawget(_G, "hq") then hq.register_shortcut({ id = "uikit", name = "UI settings", command = "uikit", short = "UI" }) end
end)
