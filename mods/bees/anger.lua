-- Angry bees (step 2c): hurt a bee, break a hive, or take honey without smoke and the bees come out angry, chase the player and sting.
-- A sting: 2 damage + 10 s poison (not in creative); the bee that stung dies about a minute later. Anger lasts 25 s.
-- Fields: _angry_until (game time), _anger_target (player name), _sting_die_at.
local mob_class = mcl_mobs.mob_class
bees.ANGER_SECONDS = 25
bees.ALERT_RADIUS = 16
bees.STING_DIE_AFTER = 60
bees.STING_DAMAGE = 2
bees.STING_RANGE = 1.6
bees.ANGER_SPEED = 2.0 -- angry bees fly this much faster (both straight chase and pathfinding)
local CHASE_GIVE_UP = 48 -- nodes: the target got away

local function target_player(self)
	local name = self._anger_target
	local pl = name and core.get_player_by_name(name)
	if pl and pl:get_hp() > 0 and not core.is_creative_enabled(name) then return pl end
end

-- Make a bee angry at a player (creative players are never targeted). Cancels homing.
function bees.anger(le, player, secs)
	if not le or not player or not player:is_player() then return false end
	local name = player:get_player_name()
	if core.is_creative_enabled(name) then return false end
	le._anger_target = name
	le._angry_until = core.get_gametime() + (secs or bees.ANGER_SECONDS)
	le.heading_home = nil; le._backtrack = nil
	le:cancel_navigation()
	-- red eyes: bee:ai_step swaps the features texture while _angry_until is set (within ~0.1 s)
	return true
end

-- Anger every bee within the alert radius of pos (a hurt bee calls its neighbours).
function bees.anger_nearby(pos, player)
	for _, o in ipairs(core.get_objects_inside_radius(pos, bees.ALERT_RADIUS)) do
		local le = o:get_luaentity()
		if le and le.name == "bees:bee" and not le.tamed then bees.anger(le, player) end
	end
end

-- Is a lit campfire within 5 nodes below the hive? Smoke keeps the bees calm.
function bees.calmed_by_smoke(pos)
	return #core.find_nodes_in_area(vector.offset(pos, 0, -5, 0), pos, "group:lit_campfire") > 0
end

local function calm(self)
	self._angry_until = nil; self._anger_target = nil
end

local function sting(self, pl)
	mcl_util.deal_damage(pl, bees.STING_DAMAGE, { type = "mob", source = self.object, direct = self.object })
	mcl_potions.give_effect_by_level("poison", pl, 1, 10)
	self._sting_die_at = core.get_gametime() + bees.STING_DIE_AFTER -- the stinger is lost: the bee dies soon
	calm(self)
end

function bees.check_anger(self, pos, dtime)
	local now = core.get_gametime()
	if self._sting_die_at and now >= self._sting_die_at then
		self._sting_die_at = nil
		self:receive_damage({ type = "generic" }, 9999)
		return false
	end
	if not self._angry_until then return false end
	local pl = target_player(self)
	if not pl or now >= self._angry_until or self.tamed then calm(self); return false end
	local tpos = pl:get_pos()
	local d = vector.distance(pos, tpos)
	if d > CHASE_GIVE_UP then calm(self); return false end
	if d <= bees.STING_RANGE then sting(self, pl); return false end
	if self:check_timer("chase", 0.4) then
		local aim = vector.offset(tpos, 0, 1.0, 0)
		if core.line_of_sight(pos, aim) then
			-- clear air: fly straight at the player
			if self.waypoints or self.pathfinding_context then self:cancel_navigation() end
			self:go_to_stupidly(aim, bees.ANGER_SPEED)
		elseif self:check_timer("chase_path", 2) then
			-- something in the way: let the pathfinder try (restarting it every tick would never let it finish)
			if not self:gopath(aim, bees.ANGER_SPEED) then self:go_to_stupidly(aim, bees.ANGER_SPEED) end
		end
	end
	return "angry"
end

-- Hurting a bee angers it and its neighbours.
local orig_receive_damage = mob_class.receive_damage
function bees.receive_damage(self, mcl_reason, damage)
	local res = orig_receive_damage(self, mcl_reason, damage)
	local src = mcl_reason and (mcl_reason.source or mcl_reason.direct)
	if res and not self.dead and src and src.is_player and src:is_player() then
		bees.anger(self, src)
		bees.anger_nearby(self.object:get_pos(), src)
	end
	return res
end

-- Let every bee out of a hive at once. `pos` = the hive; `count` given if the node is already gone (digging). `player` = who to be angry at (or nil).
-- Returns the number released.
function bees.release_all(pos, player, count)
	local n = 0
	local node_there = bees.hive_kind(pos) ~= nil
	count = count or (node_there and bees.hive_count(pos)) or 0
	for _ = 1, count do
		local obj
		if node_there then
			obj = bees.leave_hive(pos) -- takes from the count, keeps their home
		else
			obj = core.add_entity(vector.offset(pos, math.random() - 0.5, 0, math.random() - 0.5), "bees:bee") -- hive is gone: homeless bees
		end
		if obj then
			n = n + 1
			if player then bees.anger(obj:get_luaentity(), player) end
		end
	end
	return n
end
