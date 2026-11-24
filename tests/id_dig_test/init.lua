local function log(s) core.log("action", "[IDG_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local id = identifiable
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		local base = vector.round(player:get_pos())
		local p = vector.offset(base, 0, 20, 0)
		core.set_node(p, { name = "mcl_core:stone" }); core.set_node(vector.offset(p, 1, 0, 0), { name = "mcl_core:dirt" }); core.set_node(vector.offset(p, 2, 0, 0), { name = "mcl_core:obsidian" })
		player:get_inventory():set_list("main", {})
		player:set_wielded_item(ItemStack("mcl_tools:pick_wood"))
		check("wood pickaxe on stone = 1.15 s", math.abs(id.dig_time(player, p) - 1.15) < 0.01, tostring(id.dig_time(player, p)))
		player:set_wielded_item(ItemStack("mcl_tools:pick_diamond"))
		check("diamond pickaxe on obsidian = 9.4 s", math.abs(id.dig_time(player, vector.offset(p, 2, 0, 0)) - 9.4) < 0.01)
		player:set_wielded_item(ItemStack(""))
		local hd = id.dig_time(player, vector.offset(p, 1, 0, 0))
		check("empty hand can dig dirt (hand item from the hand list)", hd and hd > 0 and hd < 5, tostring(hd))
		check("empty hand cannot dig obsidian", id.dig_time(player, vector.offset(p, 2, 0, 0)) == nil or id.dig_time(player, vector.offset(p, 2, 0, 0)) > 60)
		-- progress step
		local s = {}
		local pos = vector.new(1, 2, 3)
		check("not digging: nothing", id.dig_step(s, 0.1, false, pos, 1) == nil)
		local r
		for _ = 1, 5 do r = id.dig_step(s, 0.1, true, pos, 1) end
		check("0.5 s of 1 s = 50%", math.abs(r - 0.5) < 1e-6, tostring(r))
		check("another node restarts", math.abs(id.dig_step(s, 0.1, true, vector.new(9, 9, 9), 1) - 0.1) < 1e-6)
		for _ = 1, 30 do r = id.dig_step(s, 0.1, true, vector.new(9, 9, 9), 1) end
		check("capped at 100%", r == 1)
		id.dig_step(s, 0.1, false)
		check("releasing the key resets", id.dig_step(s, 0.1, true, vector.new(9, 9, 9), 1) < 0.2)
		check("undiggable (no time) shows nothing", id.dig_step(s, 0.1, true, pos, nil) == nil)
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
