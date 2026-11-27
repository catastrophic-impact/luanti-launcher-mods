local function log(s) core.log("action", "[MV_OFF_TEST] " .. s) end
local fails = 0
local died = false
core.register_on_dieplayer(function() died = true end)
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(12, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true, creative = true })
		log("damage setting = " .. tostring(core.settings:get_bool("enable_damage")))
		local ow = multiversatile.get("overworld")
		player:set_pos({ x = 3, y = ow.build_max - 10, z = 0 })
		core.after(1.0, function() player:set_pos({ x = 0, y = ow.build_max + 100, z = 0 }) end)
		core.after(3.0, function()
			local y = player:get_pos().y
			local ok = not died and player:get_hp() > 0 and y <= ow.build_max
			log((ok and "PASS" or "FAIL") .. " damage off: not killed, put back inside the limits (y=" .. math.floor(y) .. " hp=" .. player:get_hp() .. ")")
			log("== " .. (ok and "ALL PASS" or "1 FAILED") .. " ==")
			log("SCENARIO_DONE"); core.request_shutdown("done")
		end)
	end)
end)
