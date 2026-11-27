-- Registry, lookup and area slots.
-- register{ name, ymin, ymax, [build_min, build_max], [mineclonia = true], [slots = { count, size = vector, gap }] }
--   ymin..ymax  = the band that is "this dimension" (classification; bands may not overlap and stay inside the map limit).
--   build_min/max = where blocks may be placed (default = the band); the Overworld band has no top, so it sets build_max.
--   slots = fixed pool of equal areas inside the band for throwaway worlds (Dungeoneer): slot i starts at x = O + (i-1) * (size.x + gap), z = O (O = chunk offset, -32).
local storage = core.get_mod_storage()
local dims, order = {}, {}
local LIMIT = 31007 -- engine map limit (Mineclonia's own edge may be a little past 31000)

local function check_int(v) return type(v) == "number" and v == math.floor(v) end

-- Returns nil on success, or an error string (nothing is registered then).
function multiversatile.register(def)
	if type(def) ~= "table" or type(def.name) ~= "string" or def.name == "" then return "name missing" end
	if dims[def.name] then return "already registered: " .. def.name end
	if not (check_int(def.ymin) and check_int(def.ymax)) or def.ymin > def.ymax then return "bad ymin/ymax" end
	if def.ymin < -LIMIT or def.ymax > LIMIT then return "outside the map limit +-" .. LIMIT end
	for _, o in ipairs(order) do
		if def.ymin <= o.ymax and def.ymax >= o.ymin then return "overlaps " .. o.name end
	end
	local d = table.copy(def)
	d.build_min = d.build_min or d.ymin
	d.build_max = d.build_max or d.ymax
	if d.build_min < d.ymin or d.build_max > d.ymax or d.build_min > d.build_max then return "build limits outside the band" end
	if d.slots then
		local s = d.slots
		if not (check_int(s.count) and s.count > 0 and s.size and s.size.x and s.size.y and s.size.z) then return "bad slots" end
		s.gap = s.gap or mcl_vars.chunk_size_in_nodes
		-- Areas must be whole MAPCHUNKS (80 nodes, edges at 80k-32): terrain is generated per chunk, so re-generating a cleaned slot
		-- would overwrite a neighbour that shares a chunk (found by tests/multiversatile_clean).
		local C, O = mcl_vars.chunk_size_in_nodes, mcl_vars.central_chunk_offset_in_nodes
		if (d.ymin - O) % C ~= 0 or s.size.x % C ~= 0 or s.size.y % C ~= 0 or s.size.z % C ~= 0 or s.gap % C ~= 0 then return "slots must be aligned to the map chunk size " .. C .. " (ymin, size, gap)" end
		if s.size.y > d.ymax - d.ymin + 1 then return "slot taller than the band" end
		if (s.count - 1) * (s.size.x + s.gap) + s.size.x > 2 * LIMIT then return "slots do not fit in x" end
	end
	dims[d.name] = d
	order[#order + 1] = d
	table.sort(order, function(a, b) return a.ymin < b.ymin end)
	return nil
end

function multiversatile.get(name) return dims[name] end
function multiversatile.list() local t = {}; for i, d in ipairs(order) do t[i] = d end; return t end

-- The dimension at a height (or nil = void).
function multiversatile.at_y(y)
	for _, d in ipairs(order) do
		if y >= d.ymin and y <= d.ymax then return d end
	end
end
function multiversatile.at(pos) return multiversatile.at_y(pos.y) end

-- Free height gaps between registered bands, inside the map limit: list of {ymin, ymax}.
function multiversatile.gaps()
	local g, y = {}, -LIMIT
	for _, d in ipairs(order) do
		if d.ymin > y then g[#g + 1] = { ymin = y, ymax = d.ymin - 1 } end
		y = math.max(y, d.ymax + 1)
	end
	if y <= LIMIT then g[#g + 1] = { ymin = y, ymax = LIMIT } end
	return g
end

-- Build limits: true if a block may be placed at pos. Positions in the void have no limit here (nothing is registered).
function multiversatile.can_build(pos)
	local d = multiversatile.at(pos)
	if not d then return true end
	return pos.y >= d.build_min and pos.y <= d.build_max
end

-- Slots ------------------------------------------------------------------------------------------------------------------
-- Used slots are kept in mod storage ("slots:<dim>" = json { [index] = owner }) so a restart does not hand out a busy slot.
local function load_used(name)
	local raw = storage:get_string("slots:" .. name)
	local t = raw ~= "" and core.parse_json(raw) or {}
	return type(t) == "table" and t or {}
end
local function save_used(name, t) storage:set_string("slots:" .. name, core.write_json(t)) end

function multiversatile.slot_area(name, index)
	local d = dims[name]
	if not (d and d.slots) or index < 1 or index > d.slots.count then return nil end
	local s = d.slots
	local O = mcl_vars.central_chunk_offset_in_nodes
	local minp = { x = O + (index - 1) * (s.size.x + s.gap), y = d.ymin, z = O }
	local maxp = { x = minp.x + s.size.x - 1, y = d.ymin + s.size.y - 1, z = O + s.size.z - 1 }
	return minp, maxp
end

-- First free slot -> index, minp, maxp; nil when all are taken (or the dimension has no slots).
function multiversatile.slot_alloc(name, owner)
	local d = dims[name]
	if not (d and d.slots) then return nil end
	local used = load_used(name)
	for i = 1, d.slots.count do
		if not used[tostring(i)] then
			used[tostring(i)] = owner or true
			save_used(name, used)
			local minp, maxp = multiversatile.slot_area(name, i)
			return i, minp, maxp
		end
	end
end
function multiversatile.slot_free(name, index)
	local used = load_used(name)
	if not used[tostring(index)] then return false end
	used[tostring(index)] = nil
	save_used(name, used)
	return true
end
function multiversatile.slot_used(name) return load_used(name) end

-- Clean a slot completely so it can be handed out again: remove every non-player object inside, then (a moment later: the engine finishes
-- removing objects in the next server step, and doing delete_area first made it fail to find their blocks) delete the map blocks of the
-- area (blocks, node metadata, timers and stored objects go with them). Refuses at once while a player stands inside.
-- Returns true (cb(true) follows when the area is gone) or false + reason. The slot is NOT freed here (slot_free does that).
function multiversatile.slot_clean(name, index, cb)
	local minp, maxp = multiversatile.slot_area(name, index)
	if not minp then return false, "no such slot" end
	local objs = core.get_objects_in_area(minp, maxp)
	for _, o in ipairs(objs) do
		if o:is_player() then return false, "player inside" end
	end
	for _, o in ipairs(objs) do o:remove() end
	-- wait until the engine has really dropped them (it does that in its own object management step, not at once), then delete the blocks
	local tries = 0
	local function finish()
		local left = 0
		for _, o in ipairs(core.get_objects_in_area(minp, maxp)) do if not o:is_player() then left = left + 1 end end
		tries = tries + 1
		if left > 0 and tries < 20 then return core.after(0.5, finish) end
		core.delete_area(minp, maxp)
		if cb then cb(true) end
	end
	core.after(0.5, finish)
	return true
end
