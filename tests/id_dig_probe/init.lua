local function log(s) core.log("action", "[IDD_TEST] NOTE " .. s) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		local nodes = { "mcl_core:stone", "mcl_core:dirt", "mcl_core:tree", "mcl_core:obsidian", "mcl_core:sand", "mcl_farming:wheat_5" }
		local tools = { "", "mcl_tools:pick_wood", "mcl_tools:pick_iron", "mcl_tools:pick_diamond", "mcl_tools:shovel_iron", "mcl_tools:axe_iron" }
		local hand = core.registered_items[""]
		log("registered_items[''] tool_capabilities: " .. tostring(hand and hand.tool_capabilities and core.serialize(hand.tool_capabilities):sub(1, 300)))
		log("registered_tools[''] " .. tostring(core.registered_tools[""]))
		for _, n in ipairs(nodes) do
			local hp = hand and hand.tool_capabilities and core.get_dig_params(core.registered_nodes[n].groups, hand.tool_capabilities, 0)
			log("HAND " .. n .. " = " .. (hp and (hp.diggable and string.format("%.2f", hp.time) or "no") or "nocaps"))
		end
		for _, n in ipairs(nodes) do
			local row = {}
			for _, tl in ipairs(tools) do
				local st = ItemStack(tl)
				local p = core.get_dig_params(core.registered_nodes[n].groups, st:get_tool_capabilities(), st:get_wear())
				row[#row + 1] = (tl == "" and "hand" or tl:gsub("mcl_tools:", "")) .. "=" .. (p.diggable and string.format("%.2f", p.time) or "no")
			end
			log(n .. "  " .. table.concat(row, "  "))
		end
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
