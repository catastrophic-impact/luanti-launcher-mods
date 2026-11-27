local function log(s) core.log("action", "[MV_CLEAN_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
local function scan(minp, maxp) -- count nodes that are not air/void, and nodes with metadata
	local vm = core.get_voxel_manip(minp, maxp)
	local e1, e2 = vm:read_from_map(minp, maxp)
	local va = VoxelArea:new{ MinEdge = e1, MaxEdge = e2 }
	local data = vm:get_data()
	local ok = { [core.CONTENT_AIR] = true, [core.get_content_id("mcl_core:void")] = true, [core.CONTENT_IGNORE] = true }
	local solid, first = 0, nil
	for z = minp.z, maxp.z do for y = minp.y, maxp.y do for x = minp.x, maxp.x do
		local c = data[va:index(x, y, z)]
		if not ok[c] then solid = solid + 1; first = first or core.get_name_from_content_id(c) end
	end end end
	return solid, first, #core.find_nodes_with_meta(minp, maxp)
end
local function objs(minp, maxp) local n = 0; for _, o in ipairs(core.get_objects_in_area(minp, maxp)) do if not o:is_player() then n = n + 1 end end; return n end
local function emerge(minp, maxp, cb) core.emerge_area(minp, maxp, function(_, _, rem) if rem == 0 then cb() end end) end

core.after(2, function()
	local g = mv.gaps(); local gap = g[#g - 1]
	local O = mcl_vars.central_chunk_offset_in_nodes
	local Y = O + math.ceil((gap.ymin + 64 - O) / 80) * 80
	check("register", mv.register{ name = "cleandim", ymin = Y, ymax = Y + 239, slots = { count = 2, size = { x = 80, y = 80, z = 80 }, gap = 80 } } == nil)
	local i1, a1, b1 = mv.slot_alloc("cleandim", "t")
	local i2, a2, b2 = mv.slot_alloc("cleandim", "t")
	emerge(a1, b2, function()
		-- build in slot 1: stone, a chest with items (meta), an item entity, a mob; in slot 2: one stone block (must survive)
		local c = vector.offset(a1, 10, 5, 10)
		for x = 0, 6 do for z = 0, 6 do core.set_node(vector.offset(c, x, 0, z), { name = "mcl_core:stone" }) end end
		core.set_node(vector.offset(c, 2, 1, 2), { name = "mcl_chests:chest_small", param2 = 0 })
		local inv = core.get_meta(vector.offset(c, 2, 1, 2)):get_inventory()
		inv:set_stack("main", 1, ItemStack("mcl_core:diamond 3"))
		core.get_node_timer(vector.offset(c, 0, 0, 0)):start(1000)
		core.add_item(vector.offset(c, 4, 2, 4), ItemStack("mcl_core:gold_ingot"))
		local mob = core.add_entity(vector.offset(c, 5, 2, 5), "mobs_mc:zombie")
		local keep = vector.offset(a2, 5, 5, 5)
		core.set_node(keep, { name = "mcl_core:stone" })
		core.after(1.0, function()
			local solid, first, metas = scan(a1, b1)
			check("before clean: slot 1 has stuff", solid > 40 and metas >= 1 and objs(a1, b1) >= 1, "solid=" .. solid .. " metas=" .. metas .. " objs=" .. objs(a1, b1) .. " mob=" .. tostring(mob ~= nil))
			-- refuse with a player inside is covered by the rule in code (needs a client); here: clean
			local ok, why = mv.slot_clean("cleandim", i1, function()
			emerge(a1, b1, function()
				local s2, f2, m2 = scan(a1, b1)
				check("after clean: no solid nodes left", s2 == 0, "solid=" .. s2 .. " first=" .. tostring(f2))
				check("after clean: no node metadata", m2 == 0, tostring(m2))
				check("after clean: no objects", objs(a1, b1) == 0, tostring(objs(a1, b1)))
				check("after clean: the old chest spot is not a chest", core.get_node(vector.offset(c, 2, 1, 2)).name ~= "mcl_chests:chest_small", core.get_node(vector.offset(c, 2, 1, 2)).name)
				check("neighbour slot untouched", core.get_node(keep).name == "mcl_core:stone", core.get_node(keep).name)
				check("free + realloc same slot", mv.slot_free("cleandim", i1) and mv.slot_alloc("cleandim", "again") == i1)
				log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end)
			end)
			check("slot_clean returns true", ok == true, tostring(why))
		end)
	end)
end)
