local function log(s) core.log("action", "[IDP_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local id = identifiable
local function send(player, form, fields) for _, f in ipairs(core.registered_on_player_receive_fields) do f(player, form, fields) end end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		local cfg = id.get(player)
		local cols, rows = id._grid_dims(player)
		check("grid has cells", cols >= 20 and rows >= 12, cols .. "x" .. rows)
		local fs = id._pos_form(player)
		check("grid buttons are in the formspec", select(2, fs:gsub("button%[[^%]]-;p_%d+_%d+;%]", "")) == cols * rows, tostring(#fs) .. " bytes")
		cfg.align = "manual"
		send(player, "identifiable:pos", { ["p_" .. math.floor(cols / 2) .. "_" .. math.floor(rows / 4)] = "" })
		check("click sets x (manual)", math.abs(cfg.hud_x - math.floor(cols / 2) / cols) < 1e-6, tostring(cfg.hud_x))
		check("click sets y", math.abs(cfg.hud_y - math.floor(rows / 4) / rows) < 1e-6, tostring(cfg.hud_y))
		cfg.align = "left"; local x0 = cfg.hud_x
		send(player, "identifiable:pos", { p_3_10 = "" })
		check("aligned: only the height changes", cfg.hud_x == x0 and math.abs(cfg.hud_y - 10 / rows) < 1e-6)
		cfg.align = "manual"; send(player, "identifiable:pos", { p_1000_1000 = "" })
		check("clicks stay on screen (max 95%)", cfg.hud_x <= 0.95 and cfg.hud_y <= 0.95)
		cfg.hud_x, cfg.hud_y = 0.2, 0.05
		id.save(player)
		-- settings toggles (cycling buttons): a click flips the value, "true"/"false" still set it
		local was = id.get(player).show_id
		send(player, "identifiable:cfg", { show_id = "Show ID" })
		check("toggle click flips show_id", id.get(player).show_id == (not was))
		send(player, "identifiable:cfg", { show_id = "Show ID" })
		check("second click flips it back", id.get(player).show_id == was)
		send(player, "identifiable:cfg", { show_id = "false" })
		check("explicit false still works", id.get(player).show_id == false)
		send(player, "identifiable:cfg", { show_id = "true" })
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
