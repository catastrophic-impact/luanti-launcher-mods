local function log(s) core.log("action", "[DG_BUILD_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile

-- flood fill over walkable air (air nodes whose cell above is also air) from a start position inside the slot
local function flood(minp, maxp, start)
	local vm = core.get_voxel_manip(minp, maxp)
	local e1, e2 = vm:read_from_map(minp, maxp)
	local va = VoxelArea:new{ MinEdge = e1, MaxEdge = e2 }
	local data = vm:get_data()
	local AIR = core.CONTENT_AIR
	local seen, count, q = {}, 0, { start }
	seen[va:indexp(start)] = true
	local reach = {}
	while #q > 0 do
		local p = table.remove(q)
		count = count + 1; reach[#reach + 1] = p
		for _, d in ipairs({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }) do
			local n = { x = p.x + d[1], y = p.y, z = p.z + d[3] }
			if va:containsp(n) then
				local i = va:indexp(n)
				if not seen[i] and data[i] == AIR then seen[i] = true; q[#q + 1] = n end
			end
		end
	end
	return count, seen, va
end

core.after(2, function()
	check("dungeon dimension registered", mv.get("dungeon") ~= nil and mv.get("dungeon").transient)
	local gaps_ok = mv.get("dungeon").ymax < mv.get("overworld").ymin
	check("band is under the Overworld", gaps_ok)
	-- layouts are deterministic and different per seed
	local l1, l2, l3 = dungeoneer.layout(123, 1), dungeoneer.layout(123, 1), dungeoneer.layout(124, 1)
	check("same seed -> same layout", core.write_json(l1.start_pos) == core.write_json(l2.start_pos) and #l1.edges == #l2.edges and l1.boss.row == l2.boss.row)
	local diff = #l1.edges ~= #l3.edges or l1.boss.row ~= l3.boss.row or l1.start.row ~= l3.start.row
	check("another seed -> another layout", diff)
	check("start on the west side, boss on the east side", l1.start.col == 0 and l1.boss.col == 5)
	check("tree + loops: at least 29 corridors for 30 rooms", #l1.edges >= 29, #l1.edges .. " corridors")

	dungeoneer.new_run(2, function(run, why)
		check("run built", run ~= nil, tostring(why))
		local minp, maxp = mv.slot_area("dungeon", run.slot)
		local layout = dungeoneer.run_layout(run)
		-- every room reachable from the start room by walking (flood fill over air at floor level)
		local sp = dungeoneer.run_start_pos(run)
		local count, seen, va = flood(minp, maxp, vector.offset(sp, 0, 0, 0))
		local unreachable = 0
		for _, r in ipairs(layout.rooms) do
			local p = { x = minp.x + r.cx, y = minp.y + r.y0, z = minp.z + r.cz }
			if not seen[va:indexp(p)] then unreachable = unreachable + 1 end
		end
		check("all 30 rooms reachable from the start room", unreachable == 0, "unreachable=" .. unreachable .. " air=" .. count)
		local bp = vector.new(minp.x + layout.boss_pos.x, minp.y + layout.boss_pos.y, minp.z + layout.boss_pos.z)
		check("boss room reachable", seen[va:indexp(bp)] == true)
		-- floor and walls are dungeon blocks, lanterns exist and give light
		check("floor under the start is Dungeon Floor", core.get_node(vector.offset(sp, 0, -1, 0)).name == "dungeoneer:floor", core.get_node(vector.offset(sp, 0, -1, 0)).name)
		local lanterns = #core.find_nodes_in_area(minp, maxp, "dungeoneer:lantern")
		check("lanterns placed", lanterns > 100, tostring(lanterns))
		local bricks = #core.find_nodes_in_area(minp, maxp, "dungeoneer:brick")
		check("bricks placed", bricks > 10000, tostring(bricks))
		check("nothing outside the slot area was written (above)", core.get_node(vector.new(minp.x + 10, maxp.y + 1, minp.z + 10)).name ~= "dungeoneer:brick")
		check("unbreakable: bedrock-like groups", core.get_item_group("dungeoneer:brick", "creative_breakable") == 1 and core.registered_nodes["dungeoneer:brick"]._mcl_blast_resistance >= 3600000)
		local cell = { x = minp.x + layout.start.cx, y = minp.y + layout.start.y0 + 2, z = minp.z + layout.start.cz }
		check("spawn spot has light", (core.get_node_light(cell) or 0) >= 8, tostring(core.get_node_light(cell)))
		-- remove: slot clean and free
		local ok, w = dungeoneer.remove_run(run.id, function()
		core.emerge_area(minp, maxp, function(_, _, rem)
			if rem > 0 then return end
			check("after remove: no bricks left", #core.find_nodes_in_area(minp, maxp, "dungeoneer:brick") == 0)
			check("slot free again", next(mv.slot_used("dungeon")) == nil)
			log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
			log("SCENARIO_DONE"); core.request_shutdown("done")
		end)
		end)
		check("remove_run ok", ok == true, tostring(w))
	end)
end)
