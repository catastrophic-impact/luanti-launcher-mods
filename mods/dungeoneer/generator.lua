-- Castle dungeon: a grid of rooms joined by corridors. The start room is at the west edge, the boss room at the far (east) edge.
-- Layout is random from a seed (PcgRandom): a random spanning tree over the grid (so every room is reachable) plus a few extra
-- corridors (loops). Rooms get different sizes, lanterns light everything. All coordinates are absolute (slot min corner given).
-- dungeoneer.layout(seed, tier) -> pure data (offsets from the slot corner); dungeoneer.build(minp, maxp, layout, cb) writes it.
local GX, GZ, PITCH = 6, 5, 25        -- 6 x 5 cells of 25 nodes = 150 x 125 nodes (a slot is 160 x 80 x 160)
local MARGIN = 5
local FLOOR_Y = 16                    -- offset of the floor top above the slot bottom
local ROOM_H = 9                      -- interior height of a room
local COR_H, COR_HALF = 4, 1          -- corridor interior height, half width (3 wide)

dungeoneer.slot_size = { x = 160, y = 80, z = 160 }

function dungeoneer.layout(seed, tier)
	local rng = PcgRandom(seed)
	local function rnd(a, b) return rng:next(a, b) end
	local start_row, boss_row = rnd(0, GZ - 1), rnd(0, GZ - 1)
	local rooms, grid = {}, {}
	for c = 0, GX - 1 do
		grid[c] = {}
		for r = 0, GZ - 1 do
			local kind, hs = "room", rnd(4, 7)
			if c == 0 and r == start_row then kind, hs = "start", 6
			elseif c == GX - 1 and r == boss_row then kind, hs = "boss", 10 end
			local room = { col = c, row = r, kind = kind, hs = hs,
				cx = MARGIN + c * PITCH + 12, cz = MARGIN + r * PITCH + 12, y0 = FLOOR_Y }
			rooms[#rooms + 1] = room; grid[c][r] = room
		end
	end
	-- random spanning tree (randomized depth-first)
	local seen, edges, stack = {}, {}, { grid[0][start_row] }
	local function ekey(a, b)
		if a.col > b.col or (a.col == b.col and a.row > b.row) then a, b = b, a end
		return a.col .. "," .. a.row .. "-" .. b.col .. "," .. b.row
	end
	local have = {}
	seen[stack[1]] = true
	while #stack > 0 do
		local cur = stack[#stack]
		local opts = {}
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local n = grid[cur.col + d[1]] and grid[cur.col + d[1]][cur.row + d[2]]
			if n and not seen[n] then opts[#opts + 1] = n end
		end
		if #opts == 0 then stack[#stack] = nil
		else
			local n = opts[rnd(1, #opts)]
			seen[n] = true; edges[#edges + 1] = { cur, n }; have[ekey(cur, n)] = true
			stack[#stack + 1] = n
		end
	end
	-- a few extra corridors (loops)
	for c = 0, GX - 1 do for r = 0, GZ - 1 do
		for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
			local n = grid[c + d[1]] and grid[c + d[1]][r + d[2]]
			if n and not have[ekey(grid[c][r], n)] and rnd(1, 100) <= 18 then
				edges[#edges + 1] = { grid[c][r], n }; have[ekey(grid[c][r], n)] = true
			end
		end
	end end
	local start, boss = grid[0][start_row], grid[GX - 1][boss_row]
	-- exit portals (opening lower corner, plane x/y): in the start and boss rooms, off the corridor mouths (which sit at cx-1..cx+1)
	local function exit_of(r) return { x = r.cx + 3, y = r.y0, z = r.cz + r.hs - 1 } end
	return { seed = seed, tier = tier, rooms = rooms, edges = edges, start = start, boss = boss,
		start_pos = { x = start.cx, y = start.y0, z = start.cz }, boss_pos = { x = boss.cx, y = boss.y0, z = boss.cz },
		exits = { start = exit_of(start), boss = exit_of(boss) },
		chest = { x = boss.cx - boss.hs + 1, y = boss.y0, z = boss.cz - boss.hs + 1 } } -- north-west corner of the boss room
end

-- Writes the layout into the slot (emerges it first). cb(true) when done.
function dungeoneer.build(minp, maxp, layout, cb)
	core.emerge_area(minp, maxp, function(_, _, remaining)
		if remaining > 0 then return end
		local vm = core.get_voxel_manip(minp, maxp)
		local emin, emax = vm:get_emerged_area()
		local area = VoxelArea:new{ MinEdge = emin, MaxEdge = emax }
		local data = vm:get_data()
		local BRICK, FLOOR, LANTERN = core.get_content_id("dungeoneer:brick"), core.get_content_id("dungeoneer:floor"), core.get_content_id("dungeoneer:lantern")
		local AIR = core.CONTENT_AIR
		local ox, oy, oz = minp.x, minp.y, minp.z
		local function fill(x1, y1, z1, x2, y2, z2, id)
			for z = oz + z1, oz + z2 do for y = oy + y1, oy + y2 do
				local i = area:index(ox + x1, y, z)
				for x = ox + x1, ox + x2 do data[i] = id; i = i + 1 end
			end end
		end
		local function set(x, y, z, id) data[area:index(ox + x, oy + y, oz + z)] = id end
		-- 1. shells (bricks), floor layer included; 2. interiors carved after all shells are in
		for _, r in ipairs(layout.rooms) do
			fill(r.cx - r.hs - 1, r.y0 - 1, r.cz - r.hs - 1, r.cx + r.hs + 1, r.y0 + ROOM_H, r.cz + r.hs + 1, BRICK)
		end
		for _, e in ipairs(layout.edges) do
			local a, b = e[1], e[2]
			if a.col == b.col then -- same column: corridor along z
				local z1, z2 = math.min(a.cz, b.cz), math.max(a.cz, b.cz)
				fill(a.cx - COR_HALF - 1, a.y0 - 1, z1, a.cx + COR_HALF + 1, a.y0 + COR_H, z2, BRICK)
			else
				local x1, x2 = math.min(a.cx, b.cx), math.max(a.cx, b.cx)
				fill(x1, a.y0 - 1, a.cz - COR_HALF - 1, x2, a.y0 + COR_H, a.cz + COR_HALF + 1, BRICK)
			end
		end
		for _, r in ipairs(layout.rooms) do
			fill(r.cx - r.hs, r.y0, r.cz - r.hs, r.cx + r.hs, r.y0 + ROOM_H - 1, r.cz + r.hs, AIR)
		end
		for _, e in ipairs(layout.edges) do
			local a, b = e[1], e[2]
			if a.col == b.col then
				fill(a.cx - COR_HALF, a.y0, math.min(a.cz, b.cz), a.cx + COR_HALF, a.y0 + COR_H - 1, math.max(a.cz, b.cz), AIR)
			else
				fill(math.min(a.cx, b.cx), a.y0, a.cz - COR_HALF, math.max(a.cx, b.cx), a.y0 + COR_H - 1, a.cz + COR_HALF, AIR)
			end
		end
		-- 3. floor (inside rooms and corridors) and lanterns
		for _, r in ipairs(layout.rooms) do
			fill(r.cx - r.hs, r.y0 - 1, r.cz - r.hs, r.cx + r.hs, r.y0 - 1, r.cz + r.hs, FLOOR)
			local d = r.hs - 1
			for _, p in ipairs({ { -d, -d }, { d, -d }, { -d, d }, { d, d }, { 0, 0 } }) do set(r.cx + p[1], r.y0 + ROOM_H - 1, r.cz + p[2], LANTERN) end
		end
		for _, e in ipairs(layout.edges) do
			local a, b = e[1], e[2]
			if a.col == b.col then
				fill(a.cx - COR_HALF, a.y0 - 1, math.min(a.cz, b.cz), a.cx + COR_HALF, a.y0 - 1, math.max(a.cz, b.cz), FLOOR)
				for z = math.min(a.cz, b.cz) + 8, math.max(a.cz, b.cz) - 8, 8 do set(a.cx, a.y0 + COR_H - 1, z, LANTERN) end
			else
				fill(math.min(a.cx, b.cx), a.y0 - 1, a.cz - COR_HALF, math.max(a.cx, b.cx), a.y0 - 1, a.cz + COR_HALF, FLOOR)
				for x = math.min(a.cx, b.cx) + 8, math.max(a.cx, b.cx) - 8, 8 do set(x, a.y0 + COR_H - 1, a.cz, LANTERN) end
			end
		end
		-- exit portal rings (unbreakable bricks; the opening is lit by runs.lua after the build)
		for _, e in pairs(layout.exits) do
			for i = -1, 2 do for j = -1, 2 do
				local corner = (i == -1 or i == 2) and (j == -1 or j == 2)
				local opening = i >= 0 and i <= 1 and j >= 0 and j <= 1
				if not corner and not opening then set(e.x + i, e.y + j, e.z, BRICK) end
			end end
		end
		set(layout.chest.x, layout.chest.y, layout.chest.z, core.get_content_id("dungeoneer:chest"))
		vm:set_data(data)
		vm:write_to_map(true) -- light is recalculated by the engine for blocks written this way
		-- Night vision (Mineclonia's effect) works by raising the day/night ratio, which only brightens the DAY light bank, and a closed dungeon
		-- has no sunlight: both banks are the same, so the effect did nothing here. Give every interior air node a day bank of 14 (below the 15
		-- of direct sun, so nothing burns); with the dungeon's ratio of 0 nothing changes, and a player with night vision gets a raised ratio
		-- (multiversatile look.night_vision_ratio) that blends in the day bank = a brighter dungeon.
		local vm2 = core.get_voxel_manip(minp, maxp)
		local ld, cd = vm2:get_light_data(), vm2:get_data()
		local bor, band = bit.bor, bit.band
		for i = 1, #cd do
			if cd[i] == AIR then ld[i] = bor(band(ld[i], 0xF0), 14) end
		end
		vm2:set_light_data(ld)
		vm2:write_to_map(false)
		if cb then cb(true) end
	end)
end
