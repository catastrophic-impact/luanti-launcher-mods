local function log(s) core.log("action", "[MV_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
core.after(1, function()
	-- 1. Mineclonia's three are registered with its extents; classification equals Mineclonia's own
	local ow, ne, en = mv.get("overworld"), mv.get("nether"), mv.get("end")
	check("three Mineclonia dimensions registered", ow and ne and en and ow.mineclonia and ne.mineclonia and en.mineclonia)
	for _, y in ipairs({ 10, -128, 5000, mcl_vars.mg_nether_min + 5, mcl_vars.mg_end_min + 3, mcl_vars.mg_end_max, -29100, -28000 + 2000 }) do
		local d = mv.at_y(y)
		local l, name = mcl_worlds.y_to_layer(y)
		check("y " .. y .. " same name as Mineclonia", (d and d.name or "void") == name, tostring(name))
	end
	-- 2. gaps are real voids for Mineclonia
	local gaps = mv.gaps()
	check("gaps found", #gaps >= 3, #gaps .. " gaps")
	for i, g in ipairs(gaps) do log("NOTE gap " .. i .. ": " .. g.ymin .. ".." .. g.ymax .. " (" .. (g.ymax - g.ymin + 1) .. " nodes)") end
	local g3 = gaps[#gaps - 1]
	local _, n = mcl_worlds.y_to_layer(g3.ymin + 10)
	check("a gap is void for Mineclonia before we register anything", n == "void", tostring(n))
	-- 3. a custom dimension in a gap: bad registrations are refused, a good one works and the wrap shows it
	check("overlap refused", mv.register{ name = "bad1", ymin = 0, ymax = 10 } ~= nil)
	check("outside map refused", mv.register{ name = "bad2", ymin = -40000, ymax = -39000 } ~= nil)
	check("build limit outside band refused", mv.register{ name = "bad3", ymin = g3.ymin, ymax = g3.ymin + 99, build_max = g3.ymin + 500 } ~= nil)
	check("duplicate name refused", mv.register{ name = "overworld", ymin = g3.ymin, ymax = g3.ymin + 99 } ~= nil)
	local O = mcl_vars.central_chunk_offset_in_nodes
	local A = O + math.ceil((g3.ymin + 100 - O) / 80) * 80
	local err = mv.register{ name = "testdim", ymin = A, ymax = A + 255, build_max = A + 200,
		slots = { count = 3, size = { x = 80, y = 80, z = 80 }, gap = 80 } }
	check("unaligned slots refused", mv.register{ name = "bad4", ymin = A + 300 + 1, ymax = A + 400, slots = { count = 1, size = { x = 64, y = 16, z = 64 } } } ~= nil)
	check("good registration", err == nil, tostring(err))
	local l, name = mcl_worlds.y_to_layer(A + 50)
	check("Mineclonia sees the new dimension by name and layer", name == "testdim" and l == 50, tostring(name) .. " " .. tostring(l))
	check("pos_to_dimension too", mcl_worlds.pos_to_dimension({ x = 5, y = A + 50, z = 9 }) == "testdim")
	check("below the new band still void", select(2, mcl_worlds.y_to_layer(A - 1)) == "void")
	-- 4. build limits
	check("build ok inside", mv.can_build({ x = 0, y = A + 100, z = 0 }))
	check("build refused above the limit", not mv.can_build({ x = 0, y = A + 201, z = 0 }))
	check("Overworld: no building above the official top", not mv.can_build({ x = 0, y = mcl_vars.mg_overworld_max_official + 1, z = 0 }) and mv.can_build({ x = 0, y = mcl_vars.mg_overworld_max_official, z = 0 }), tostring(mcl_vars.mg_overworld_max_official))
	check("void has no limit", mv.can_build({ x = 0, y = g3.ymin + 5, z = 0 }))
	-- 5. slots
	local i1, a1, b1 = mv.slot_alloc("testdim", "alice")
	local i2, a2 = mv.slot_alloc("testdim", "bob")
	local i3 = mv.slot_alloc("testdim", "carol")
	check("three slots handed out", i1 == 1 and i2 == 2 and i3 == 3)
	check("fourth refused (pool full)", mv.slot_alloc("testdim", "dave") == nil)
	check("areas do not overlap", b1.x < a2.x and a2.x - b1.x == 81, tostring(a2.x - b1.x))
	check("area inside the band", a1.y == A and b1.y <= A + 255)
	check("free + reuse gives the same slot", mv.slot_free("testdim", 2) and select(1, mv.slot_alloc("testdim", "erin")) == 2)
	check("double free refused", mv.slot_free("testdim", 2) and not mv.slot_free("testdim", 2))
	log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
	log("SCENARIO_DONE"); core.request_shutdown("done")
end)
