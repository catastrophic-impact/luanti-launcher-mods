-- Bee brain (step 2b): leave, forage inside a leash around the hive, head home, enter only at the hive face, backtrack when home cannot be reached.
-- State fields on the bee (mcl_mobs saves non-function fields): _hive (position), _out_since, _forage_for, _crumbs, heading_home (the activity),
-- _home_tries, _backtrack, _best_dist, _progress_at. A tamed bee (tameful) ignores all of it and forgets its hive; once released it adopts a hive again.
local mob_class = mcl_mobs.mob_class

local LEASH = 22 -- nodes from the hive a bee may be
local ENTER_DIST = 1.25 -- centre of the bee to centre of the hive: it must be touching the hive face
local CRUMB_GAP = 2 -- a breadcrumb every 2 nodes of flying
local MAX_CRUMBS = 10
local NO_PROGRESS = 5 -- seconds without getting 0.5 nodes closer = path is failing
local MAX_TRIES = 4
local FINAL_APPROACH = 30 -- nodes: whenever the entrance is in clear view within this range, fly straight at it (the pathfinder path often ends well short of the hive)
bees.LEASH = LEASH

-- Forget the hive. `avoid` (seconds): do not adopt that same hive again for that long (unreachable or full).
local function homeless(self, avoid)
	if avoid and self._hive then
		self._avoid = self._avoid or {}
		self._avoid[core.hash_node_position(self._hive)] = core.get_gametime() + avoid
	end
	self._hive = nil; self.heading_home = nil; self._crumbs = nil; self._backtrack = nil; self._fa_best = nil; self._fa_since = nil
	self:cancel_navigation()
end

local function hive_ok(self)
	local name = core.get_node(self._hive).name
	if name == "ignore" then return true end -- not loaded: assume it is still there
	return bees.hive_kind(self._hive) ~= nil
end

local function start_path(self, pos)
	local ent = bees.hive_entrance(self._hive, pos)
	if not ent then return false end -- walled in
	self._entrance = ent
	self._best_dist = vector.distance(pos, self._hive)
	self._progress_at = core.get_gametime()
	if self:gopath(ent) then return true end
	-- No route found (often just too far for the pathfinder): in open air fly straight at it.
	if core.line_of_sight(pos, ent) then self:go_to_stupidly(ent); return true end
	return false
end

local function should_go_home(self, pos, now)
	return not bees.is_active_time()
		or now - (self._out_since or now) > (self._forage_for or 240)
		or vector.distance(pos, self._hive) > LEASH
end

-- One failure: fly back to the previous breadcrumb, then try the way home again from there. Out of tries or crumbs: give up on this hive.
local function backtrack(self, pos)
	self._home_tries = (self._home_tries or 0) + 1
	local crumbs = self._crumbs
	local target
	while crumbs and #crumbs > 0 do
		local c = table.remove(crumbs)
		if vector.distance(c, pos) > 3 then target = c; break end
	end
	if self._home_tries > MAX_TRIES or not target then homeless(self, 300); return false end -- unreachable: leave it alone for 5 minutes
	self._backtrack = target
	if not self:gopath(target) then self:go_to_stupidly(target) end
	return true
end

local function step_home(self, pos, dtime, now)
	if not hive_ok(self) then homeless(self); return false end
	local d = vector.distance(pos, self._hive)
	if d <= ENTER_DIST then
		if bees.enter_hive(self.object, self._hive) then return true end -- the entity is gone after this
		homeless(self, 60); return false -- hive full or not enterable: look for another
	end
	-- Last 4 nodes with a clear line to the entrance: fly straight in (first to the free entrance node, then at the hive face). The pathfinder only gets a bee
	-- near the hive (its path ends a node or two short), so treating "path finished" as failure here made bees fly away again.
	if d <= FINAL_APPROACH and not self._backtrack then
		local ent = bees.hive_entrance(self._hive, pos)
		if ent and core.line_of_sight(pos, ent) then
			-- fail only when it stops getting closer: 6 s without gaining half a node
			if not self._fa_best or d < self._fa_best - 0.5 then self._fa_best = d; self._fa_since = now end
			if now - self._fa_since < 6 then
				local aim = vector.distance(pos, ent) > 0.45 and ent or self._hive
				if self.waypoints or self.pathfinding_context then self:cancel_navigation() end
				self:go_to_stupidly(aim, 0.8)
				self._best_dist = d; self._progress_at = now
				return true
			end
			self._fa_best = nil; self._fa_since = nil
			if not backtrack(self, pos) then return false end
			return true
		end
	end
	self._fa_best = nil; self._fa_since = nil
	if not self:check_timer("home_step", 1.0) then return true end
	if self._backtrack then
		if vector.distance(pos, self._backtrack) < 1.5 or self:navigation_finished() then
			self._backtrack = nil
			if not start_path(self, pos) and not backtrack(self, pos) then return false end
		end
		return true
	end
	if d < (self._best_dist or d) - 0.5 then self._best_dist = d; self._progress_at = now end
	local stuck = now - (self._progress_at or now) >= NO_PROGRESS
	if stuck or (self:navigation_finished() and d > ENTER_DIST + 0.5) then
		if not backtrack(self, pos) then return false end
	elseif not self:is_navigating() then
		if not start_path(self, pos) and not backtrack(self, pos) then return false end
	end
	return true
end

function bees.check_hive(self, pos, dtime)
	if self.tamed then
		if self._hive or self.heading_home then homeless(self) end
		return false
	end
	if self._angry_until then return false end -- angry bees ignore the hive until they calm down
	local now = core.get_gametime()
	if self.heading_home then return step_home(self, pos, dtime, now) end

	if not self._hive then
		if self:check_timer("hive_search", 5) then
			local h = bees.find_home(pos, LEASH, self._avoid)
			if h then self._hive = h; self._out_since = now; self._forage_for = math.random(180, 360) end
		end
		return false
	end
	if not self:check_timer("hive_check", 1.0) then return false end
	if not hive_ok(self) then homeless(self); return false end

	local crumbs = self._crumbs or {}
	self._crumbs = crumbs
	local last = crumbs[#crumbs]
	if not last or vector.distance(last, pos) > CRUMB_GAP then
		crumbs[#crumbs + 1] = vector.copy(pos)
		if #crumbs > MAX_CRUMBS then table.remove(crumbs, 1) end
	end
	if should_go_home(self, pos, now) then
		self._home_tries = 0; self._backtrack = nil
		self.heading_home = true
		if not start_path(self, pos) and not backtrack(self, pos) then return false end
		return "heading_home"
	end
	return false
end
