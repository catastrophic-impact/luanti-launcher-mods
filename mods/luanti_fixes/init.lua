-- Small fixes for upstream Mineclonia behaviour that need no game patch. (Also ships textures upstream is missing.)

-- New players always start as the boy (Mineclonia picks the boy or the girl at random). Players who already have a saved skin keep it.
if core.get_modpath("mcl_skins") then
	core.register_on_newplayer(function(player)
		if mcl_skins.steve and mcl_skins.steve.base_color then
			player:get_meta():set_string("mcl_skins:skin", core.serialize(table.copy(mcl_skins.steve)))
		end
	end)
end

-- Water flowing into freshly generated caves destroyed every plant it touched and each one dropped as an item
-- (a lush cave: ~560 items at once, which also triggered "Found duplicate GUID ... __builtin:item" when the block was stored and re-activated).
-- Cause: nodes get on_flood = mcl_core.basic_flood (_mcl_autogroup), which drops the node's items; mapgen liquid settling calls it for the pools and plants
-- the generator itself placed. Fix: while a mapblock is young (generated < 120 s ago) the flooded node is removed without drops, and so is one that floods while no player is within 48 nodes (nobody could pick the item up anyway).
if core.get_modpath("mcl_core") then
	local young = {}   -- mapblock hash -> generation time
	local AGE = 120
	core.register_on_generated(function(minp, maxp)
		local now = core.get_gametime()
		for bz = math.floor(minp.z / 16), math.floor(maxp.z / 16) do
			for by = math.floor(minp.y / 16), math.floor(maxp.y / 16) do
				for bx = math.floor(minp.x / 16), math.floor(maxp.x / 16) do
					young[core.hash_node_position({x = bx, y = by, z = bz})] = now
				end
			end
		end
	end)
	local function is_young(pos)
		local k = core.hash_node_position({x = math.floor(pos.x / 16), y = math.floor(pos.y / 16), z = math.floor(pos.z / 16)})
		local t = young[k]
		if not t then return false end
		if core.get_gametime() - t > AGE then young[k] = nil return false end
		return true
	end
	local function player_near(pos)
		for _, pl in ipairs(core.get_connected_players()) do
			if vector.distance(pl:get_pos(), pos) < 48 then return true end
		end
		return false
	end
	core.register_on_mods_loaded(function()
		local orig = mcl_core.basic_flood
		if not orig then return end
		luanti_fixes_orig_flood = orig -- test hook only (tests/lush_probe)
		local function flood(pos, oldnode, newnode)
			if (is_young(pos) or not player_near(pos)) and core.get_item_group(newnode.name, "water") > 0 then
				core.remove_node(pos)
				return
			end
			return orig(pos, oldnode, newnode)
		end
		mcl_core.basic_flood = flood
		for name, def in pairs(core.registered_nodes) do
			if def.on_flood == orig then core.override_item(name, {on_flood = flood}) end
		end
	end)
end
