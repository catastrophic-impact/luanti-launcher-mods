-- Personal space: Mineclonia lets mobs stand inside each other, so a whole village gathering at the bell becomes one pile.
-- Twice a second villagers closer than MIN_DIST (horizontally, same floor) are nudged apart. Sleeping villagers stay in bed.
local MIN_DIST = 1.1
local NUDGE = 0.3
local STEP = 0.5

local function free(pos)
	local n = core.get_node_or_nil(pos)
	local def = n and core.registered_nodes[n.name]
	if not def or def.walkable then return false end
	local up = core.get_node_or_nil(vector.offset(pos, 0, 1, 0))
	local updef = up and core.registered_nodes[up.name]
	if not updef or updef.walkable then return false end
	-- stay on the same floor: solid ground right below (or one step down)
	for dy = 1, 2 do
		local d = core.get_node_or_nil(vector.offset(pos, 0, -dy, 0))
		local ddef = d and core.registered_nodes[d.name]
		if ddef and ddef.walkable then return true end
	end
	return false
end

local function movable(ent)
	return ent.object:get_pos() and not ent.dead and not ent.driver and not ent._villager_sleeping
		and ent._active_activity ~= "_villager_sleeping" and not ent.object:get_attach()
end

populations.spacing_stats = { tried = 0, moved = 0, blocked_node = {} }
-- Away from the neighbour first; when that spot is not free (edge of a platform, stairs) try turning up to 120 degrees either way.
local TURNS = { 0, 0.9, -0.9, 1.8, -1.8 }
local function push(ent, dx, dz)
	local p = ent.object:get_pos()
	local st = populations.spacing_stats
	st.tried = st.tried + 1
	for _, a in ipairs(TURNS) do
		local c, s = math.cos(a), math.sin(a)
		local to = vector.new(p.x + dx * c - dz * s, p.y, p.z + dx * s + dz * c)
		if free(vector.round(to)) then st.moved = st.moved + 1; ent.object:set_pos(to) return end
	end
	local n = core.get_node(vector.round(p)).name
	st.blocked_node[n] = (st.blocked_node[n] or 0) + 1
end

-- How many villagers stand near each bell (refreshed with the spacing pass below). A bell holds GATHER_CAP people at once; the others
-- are not sent there and spend the social hours pacing around the village instead.
local GATHER_CAP, GATHER_RADIUS = 6, 6
local at_bell = {}
local function bell_key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
function populations.bell_crowded(self)
	local b = self._bell
	if not b then return false end
	if self._wander_to_bell or self._socializing_at_bell or self._gossiping then return false end -- already part of the group
	if vector.distance(self.object:get_pos(), b) <= GATHER_RADIUS then return false end
	return (at_bell[bell_key(b)] or 0) >= GATHER_CAP
end

core.register_on_mods_loaded(function()
	local ent = core.registered_entities["mobs_mc:villager"]
	if not ent then return end
	local wander = ent.wander_to_bell or mcl_mobs.mob_class.wander_to_bell
	if wander then
		ent.wander_to_bell = function(self, self_pos, dtime)
			if populations.bell_crowded(self) then return false end
			local was = self._wander_to_bell
			local r = wander(self, self_pos, dtime)
			if r and not was and self._bell then -- count a villager the moment it sets off, not half a second later
				local k = bell_key(self._bell)
				at_bell[k] = (at_bell[k] or 0) + 1
			end
			return r
		end
	end
	-- during the social hours everyone who is not at the bell may also pace around the village
	local orig_schedule = ent.schedule or mcl_mobs.mob_class.schedule
	local pace = ent.pace_around_village
	local prev = ent.schedule
	ent.schedule = function(self, ...)
		local r = prev and prev(self, ...) or orig_schedule(self, ...)
		if self._schedule_name == "SOCIALIZE" and pace and self.ai_functions and not self.child then
			table.insert(self.ai_functions, pace)
		end
		return r
	end
end)

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < STEP then return end
	timer = 0
	local list = {}
	for _, ent in pairs(core.luaentities) do
		if ent.name == "mobs_mc:villager" and movable(ent) then list[#list + 1] = ent end
	end
	at_bell = {}
	for _, v in ipairs(list) do
		local b = v._bell
		if b and (v._wander_to_bell or vector.distance(v.object:get_pos(), b) <= GATHER_RADIUS) then at_bell[bell_key(b)] = (at_bell[bell_key(b)] or 0) + 1 end
	end
	for i = 1, #list do
		local a = list[i]
		local pa = a.object:get_pos()
		for j = i + 1, #list do
			local b = list[j]
			local pb = b.object:get_pos()
			if math.abs(pa.y - pb.y) < 1.2 then
				local dx, dz = pb.x - pa.x, pb.z - pa.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < MIN_DIST then
					if d < 0.01 then
						local ang = (i * 2.399 + j) % (2 * math.pi) -- identical spot: fan out by index
						dx, dz = math.cos(ang), math.sin(ang)
					else
						dx, dz = dx / d, dz / d
					end
					push(a, -dx * NUDGE, -dz * NUDGE)
					push(b, dx * NUDGE, dz * NUDGE)
					pa = a.object:get_pos()
				end
			end
		end
	end
end)
