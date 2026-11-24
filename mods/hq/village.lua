-- Village finder: asks Mineclonia's structure locator for the nearest village, loads the place and puts the player on the ground.
local S = core.get_translator("hq")
local KINDS = { -- button order; id = nil means "any kind"
	{ key = "any", label = S("Any") },
	{ key = "plains", label = S("Plains"), id = "mcl_villages:village_plains" },
	{ key = "desert", label = S("Desert"), id = "mcl_villages:village_desert" },
	{ key = "savanna", label = S("Savan."), id = "mcl_villages:village_savannah" },
	{ key = "snowy", label = S("Snowy"), id = "mcl_villages:village_snowy" },
	{ key = "taiga", label = S("Taiga"), id = "mcl_villages:village_taiga" },
}
hq.village_kinds = KINDS

function hq.can_find_villages(player)
	return rawget(_G, "mcl_biome_dispatch") and mcl_biome_dispatch.locate_structure_near
		and core.check_player_privs(player:get_player_name(), { teleport = true })
end

-- Highest standable spot (solid node with two free nodes above) at x,z, searching down from the top of the loaded column.
local function ground_at(x, z, ytop)
	for y = ytop, ytop - 200, -1 do
		local n = core.get_node_or_nil({ x = x, y = y, z = z })
		if not n then return nil end
		local def = core.registered_nodes[n.name]
		if def and def.walkable and core.get_item_group(n.name, "leaves") == 0 then
			local a1 = core.get_node_or_nil({ x = x, y = y + 1, z = z })
			local a2 = core.get_node_or_nil({ x = x, y = y + 2, z = z })
			if a1 and a2 and a1.name == "air" and a2.name == "air" then return { x = x, y = y + 1, z = z } end
		end
	end
end

local busy = {}
function hq.find_village(player, kind)
	local name = player:get_player_name()
	if not hq.can_find_villages(player) then hq.msg(name, S("You need the teleport privilege.")); return end
	if busy[name] then hq.msg(name, S("Still searching.")); return end
	local ids = {}
	for _, k in ipairs(KINDS) do if k.id and (kind == "any" or kind == k.key) then ids[#ids + 1] = k.id end end
	local pos = player:get_pos()
	local best, left = nil, #ids
	busy[name] = true
	hq.msg(name, S("Searching for a village..."))
	local function finished()
		busy[name] = nil
		local p = core.get_player_by_name(name)
		if not p then return end
		if not best then hq.msg(name, S("No village found nearby.")); return end
		local c = vector.round(best)
		core.emerge_area(vector.offset(c, -24, -60, -24), vector.offset(c, 24, 120, 24), function(_, _, remaining)
			if remaining > 0 then return end
			local pl = core.get_player_by_name(name)
			if not pl then return end
			local g
			for r = 0, 12, 4 do -- the exact spot may be inside a house: try nearby columns
				g = ground_at(c.x + r, c.z, c.y + 40) or ground_at(c.x - r, c.z, c.y + 40)
				if g then break end
			end
			if g then
				pl:set_pos(g)
				hq.msg(name, S("You are at a village (@1,@2,@3).", g.x, g.y, g.z))
			else
				hq.msg(name, S("Found a village at (@1,@2,@3) but could not find ground there.", c.x, c.y, c.z))
			end
		end)
	end
	for _, id in ipairs(ids) do
		mcl_biome_dispatch.locate_structure_near(pos, id, 96, function(v)
			if v and (not best or vector.distance(v, pos) < vector.distance(best, pos)) then best = v end
			left = left - 1
			if left == 0 then finished() end
		end, nil, function() return player:is_valid() end)
	end
end
