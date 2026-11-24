local function log(s) core.log("action", "[UIKIT_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
local function near(a, b) return math.abs(a - b) < 1e-9 end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(10, function()
		-- layout: every row built from cols() ends exactly at x + w, and fixed widths stay fixed
		for _, parts in ipairs({ 1, 2, 3, 6, { 2.5, 3.3, 1.8 }, { 1, "0.7", "0.7" }, { "0.8", 1 } }) do
			local c = uikit.cols(0.7, 7.8, 0.15, parts)
			local last = c[#c]
			check("cols " .. (type(parts) == "number" and parts or #parts .. " parts") .. " ends at the edge", near(last.x + last.w, 8.5), tostring(last.x + last.w))
		end
		local c = uikit.cols(0, 6.6, 0.1, { 1, "0.75", "0.75" })
		check("fixed columns keep their width", near(c[2].w, 0.75) and near(c[3].w, 0.75) and near(c[1].w, 6.6 - 0.2 - 1.5))
		check("columns do not overlap", c[2].x >= c[1].x + c[1].w and c[3].x >= c[2].x + c[2].w)
		-- settings
		local s = uikit.get(player)
		check("defaults", s.bg == "dim" and s.panel == "glass" and s.text == "white" and s.size == "normal")
		check("set valid", uikit.set(player, "text", "warm") and uikit.get(player).text == "warm")
		check("set invalid value refused", uikit.set(player, "text", "pink") == false and uikit.get(player).text == "warm")
		check("set unknown key refused", uikit.set(player, "nope", "x") == false)
		uikit.cycle(player, "bg"); check("cycle bg dim -> dark", uikit.get(player).bg == "dark")
		uikit.cycle(player, "bg"); check("cycle wraps to clear", uikit.get(player).bg == "clear")
		uikit.cycle(player, "bg"); check("cycle wraps to dim", uikit.get(player).bg == "dim")
		-- a corrupt saved value falls back to the default
		player:get_meta():set_string("uikit:settings", core.serialize({ bg = "bogus", size = "large" }))
		check("bad saved value -> default, good one kept", uikit.get(player).bg == "dim" and uikit.get(player).size == "large")
		-- the screen header reflects the player's choices
		uikit.set(player, "size", "large"); uikit.set(player, "text", "warm"); uikit.set(player, "panel", "solid"); uikit.set(player, "bg", "dark")
		local fs = uikit.begin(player, 10, 5)
		check("begin has formspec_version 6 and size", fs:find("formspec_version[6]size[10,5]", 1, true) ~= nil)
		check("begin drops the game frame", fs:find("no_prepend[]", 1, true) ~= nil)
		check("large text -> font_size +3", fs:find("font_size=+3", 1, true) ~= nil)
		check("warm text color", fs:find("textcolor=#ffe6a8", 1, true) ~= nil)
		check("dark background", fs:find("#000000b4", 1, true) ~= nil)
		check("solid panels", uikit.panel(0, 0, 1, 1):find("uikit_panel_solid.png", 1, true) ~= nil)
		uikit.set(player, "size", "normal"); uikit.set(player, "panel", "glass")
		check("normal size sets no font_size", uikit.begin(player, 10, 5):find("font_size", 1, true) == nil)
		check("glass panels", uikit.panel(0, 0, 1, 1):find("uikit_panel.png", 1, true) ~= nil)
		check("disabled style is emitted for hover and pressed too", uikit.disabled("x"):find("style[x:hovered;", 1, true) ~= nil and uikit.disabled("x"):find("style[x:pressed;", 1, true) ~= nil)
		-- settings window: clicking an option cycles it
		uikit.set(player, "bg", "dim")
		deliver(player, "uikit:settings", { opt_bg = "x", quit = "true" })
		check("window click cycles", uikit.get(player).bg == "dark")
		-- declarative screens (uikit.screen)
		do
			local state = { flag = false, mode = "b", text = "hello", allowed = true, changes = 0 }
			local scr = uikit.screen({
				name = "uikit_test:screen", title = "Test", width = 9, command = "uikit_test_screen",
				can = function() return state.allowed end, denied = "No access",
				on_change = function() state.changes = state.changes + 1 end,
				rows = {
					{ type = "toggle", id = "flag", label = "Flag", get = function() return state.flag end, set = function(_, v) state.flag = v end },
					{ type = "choice", id = "mode", label = "Mode", choices = { "a", "b", "c" }, get = function() return state.mode end, set = function(_, v) state.mode = v end },
					{ type = "field", id = "text", label = "Text", button_name = "save", get = function() return state.text end, set = function(_, v) state.text = v end },
					{ type = "text", text = "A note", dim = true }, { type = "gap" },
				},
			})
			local function plain(f) return (f:gsub("\27%(T@[^)]*%)", ""):gsub("\27E", "")) end
			local fs = plain(scr.formspec("tester"))
			check("screen shows the toggle, choice, field and Close", fs:find("Flag: Off", 1, true) and fs:find("Mode: b", 1, true) and fs:find("name=nope") == nil and fs:find(";close;", 1, true) and fs:find(";save;", 1, true) ~= nil)
			deliver(player, "uikit_test:screen", { flag = "Flag: Off" }); check("toggle click flips on", state.flag == true)
			deliver(player, "uikit_test:screen", { flag = "Flag: On" }); check("toggle click flips off", state.flag == false)
			deliver(player, "uikit_test:screen", { flag = "true" }); check("explicit true sets it", state.flag == true)
			deliver(player, "uikit_test:screen", { mode = "Mode: b" }); check("choice click goes to the next value", state.mode == "c")
			deliver(player, "uikit_test:screen", { mode = "Mode: c" }); check("choice wraps around", state.mode == "a")
			deliver(player, "uikit_test:screen", { mode = "c" }); check("a listed value sets the choice directly", state.mode == "c")
			deliver(player, "uikit_test:screen", { text = "changed" }); check("a field is NOT stored without its button", state.text == "hello")
			deliver(player, "uikit_test:screen", { text = "changed", save = "x" }); check("field stored with its button", state.text == "changed")
			check("on_change ran for every set", state.changes == 7, tostring(state.changes))
			state.allowed = false
			local ro = plain(scr.formspec("tester"))
			check("read-only when not allowed: no buttons for the rows, denied text shown", ro:find("button[", 1, true) == nil or ro:find(";flag;", 1, true) == nil, "")
			check("denied text shown", ro:find("No access", 1, true) ~= nil)
			deliver(player, "uikit_test:screen", { flag = "x" }); check("not allowed: click changes nothing", state.flag == true and state.changes == 7)
			check("screen registered its chat command", core.registered_chatcommands.uikit_test_screen ~= nil)
		end
		-- HQ shortcut exists and the command runs
		check("HQ shortcut registered", rawget(_G, "hq") and hq.shortcuts.uikit ~= nil and hq.shortcuts.uikit.command == "uikit")
		check("/uikit command exists", core.registered_chatcommands.uikit ~= nil)
		player:get_meta():set_string("uikit:settings", "")
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
