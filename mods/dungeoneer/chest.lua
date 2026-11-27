-- The loot chest in the boss room: sealed until the boss is dead (it will not open and cannot be broken), filled from the dungeon's tier.
local S = core.get_translator("dungeoneer")

local function sealed(pos)
	local id = core.get_meta(pos):get_int("dungeoneer_run")
	local run = dungeoneer.runs()[tostring(id)]
	return run and not run.cleared
end

core.register_node("dungeoneer:chest", {
	description = S("Dungeon Chest"),
	tiles = { "dungeoneer_chest_top.png", "dungeoneer_chest_top.png", "dungeoneer_chest_side.png", "dungeoneer_chest_side.png", "dungeoneer_chest_side.png", "dungeoneer_chest_front.png" },
	paramtype2 = "facedir", is_ground_content = false,
	groups = { handy = 1, axey = 1, deco_block = 1, unmovable_by_piston = 1 },
	sounds = mcl_sounds.node_sound_wood_defaults and mcl_sounds.node_sound_wood_defaults() or nil,
	_mcl_blast_resistance = 2.5, _mcl_hardness = 2.5,
	on_construct = function(pos) core.get_meta(pos):get_inventory():set_size("main", 27) end,
	-- the next-tier key is only for a player who was inside when the boss died, only one each, and only while carrying no key
	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		if stack:get_name():find("^dungeoneer:key_") then
			local run = dungeoneer.runs()[tostring(core.get_meta(pos):get_int("dungeoneer_run"))]
			local name = player:get_player_name()
			if not run or not run.key_for or not run.key_for[name] or (run.key_taken and run.key_taken[name]) or dungeoneer.carries_key(player) then return 0 end
		end
		return stack:get_count()
	end,
	on_metadata_inventory_take = function(pos, listname, index, stack, player)
		if stack:get_name():find("^dungeoneer:key_") then
			local run = dungeoneer.runs()[tostring(core.get_meta(pos):get_int("dungeoneer_run"))]
			if run then run.key_taken = run.key_taken or {}; run.key_taken[player:get_player_name()] = true; dungeoneer.update_run(run) end
		end
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if stack:get_name():find("^dungeoneer:key_") then return 0 end -- keys are not stored back
		return stack:get_count()
	end,
	can_dig = function(pos) return not sealed(pos) and core.get_meta(pos):get_inventory():is_empty("main") end,
	on_blast = function(pos) if sealed(pos) then return end core.remove_node(pos) end,
	on_rightclick = function(pos, node, player)
		if sealed(pos) then
			if rawget(_G, "mcl_title") then mcl_title.set(player, "actionbar", { text = S("The chest is sealed until the boss is dead."), color = "white", stay = 60 }) end
			return
		end
		local spos = pos.x .. "," .. pos.y .. "," .. pos.z
		core.show_formspec(player:get_player_name(), "dungeoneer:chest",
			"formspec_version[4]size[11.75,10.425]label[0.375,0.375;" .. core.formspec_escape(S("Dungeon Chest")) .. "]" ..
			"list[nodemeta:" .. spos .. ";main;0.375,0.75;9,3;]label[0.375,4.7;" .. core.formspec_escape(S("Inventory")) .. "]" ..
			"list[current_player;main;0.375,5.1;9,3;9]list[current_player;main;0.375,8.95;9,1;]" ..
			"listring[nodemeta:" .. spos .. ";main]listring[current_player;main]")
	end,
})

-- loot by tier: { item, min, max, weight }
local LOOT = {
	{ { "mcl_core:iron_ingot", 2, 6, 10 }, { "mcl_core:gold_ingot", 1, 4, 8 }, { "mcl_farming:bread", 2, 5, 8 }, { "mcl_bows:arrow", 8, 24, 8 }, { "mcl_core:coal_lump", 4, 12, 8 }, { "mcl_core:diamond", 1, 1, 1 } },
	{ { "mcl_core:iron_ingot", 4, 10, 10 }, { "mcl_core:gold_ingot", 3, 8, 8 }, { "mcl_core:diamond", 1, 3, 5 }, { "mcl_farming:bread", 4, 8, 6 }, { "mcl_bows:arrow", 16, 32, 6 }, { "mcl_core:emerald", 1, 3, 3 } },
	{ { "mcl_core:diamond", 2, 5, 10 }, { "mcl_core:gold_ingot", 6, 12, 6 }, { "mcl_core:emerald", 2, 6, 8 }, { "mcl_core:iron_ingot", 8, 16, 6 }, { "mcl_farming:bread", 6, 12, 4 } },
	{ { "mcl_core:diamond", 4, 8, 10 }, { "mcl_core:emerald", 4, 10, 8 }, { "mcl_nether:netherite_ingot", 1, 2, 3 }, { "mcl_core:gold_ingot", 10, 20, 5 }, { "mcl_core:iron_ingot", 12, 24, 4 } },
}
function dungeoneer.fill_chest(run, pos)
	local m = core.get_meta(pos); m:set_int("dungeoneer_run", run.id)
	local inv = m:get_inventory(); inv:set_size("main", 27)
	inv:set_list("main", {})
	local rng = PcgRandom(run.seed + 3)
	local table_ = {}
	for _, e in ipairs(LOOT[run.tier]) do if core.registered_items[e[1]] then table_[#table_ + 1] = e end end
	local total = 0; for _, e in ipairs(table_) do total = total + e[4] end
	for i = 1, 6 + run.tier * 2 do
		local r, pick = rng:next(1, total), nil
		for _, e in ipairs(table_) do r = r - e[4]; if r <= 0 then pick = e; break end end
		pick = pick or table_[1]
		inv:set_stack("main", rng:next(1, 27), ItemStack(pick[1] .. " " .. rng:next(pick[2], pick[3])))
	end
end

-- The boss is dead: every player inside right now (a dead player who has not respawned yet still counts) is owed the next-tier key; the
-- chest gets one per player (none for tier 4: there is nothing above it). A player takes theirs whenever they come back for it.
function dungeoneer.award_keys(run, minp, layout)
	local names = dungeoneer.players_inside(run)
	run.key_for, run.key_taken = {}, {}
	for _, n in ipairs(names) do run.key_for[n] = true end
	dungeoneer.update_run(run)
	if run.tier >= 4 then return names end
	local c = layout.chest
	local inv = core.get_meta(vector.new(minp.x + c.x, minp.y + c.y, minp.z + c.z)):get_inventory()
	for _ = 1, #names do inv:add_item("main", ItemStack("dungeoneer:key_" .. (run.tier + 1))) end
	return names
end
