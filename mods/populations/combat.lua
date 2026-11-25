-- Health, fighting back, calls for help, iron golems.
-- Adults have 40 health, children 20. Villagers and golems heal 1 hp every 2 s after 10 s out of combat.
-- Adults put on armor and a sword (settings) only while fighting; the gear is gone afterwards.
-- Help comes one villager at a time: each hit has a 10% chance per hit taken in the fight so far (max 60%) to call
-- the nearest free adult within 32 blocks; every hit taken while running away (children always run) calls one for sure.
-- At half health a villager stops fighting and runs (Mineclonia's own panic takes over).
local cfg = populations.cfg
local ADULT_HP, CHILD_HP = 40, 20
local MEMORY = 10         -- seconds without hitting or being hit before a villager calms down
local RANGE = 32
local CALL_RANGE = 32
local HELP_PER_HIT, MAX_HELP = 0.1, 0.6
local ATTACK_INTERVAL = 0.625 -- a full-strength sword swing (1.6 per second)
local REACH = 2.2

local state = setmetatable({}, { __mode = "k" }) -- entity -> fight state (not saved)
populations._fight_state = state

local function now() return core.get_gametime() end
local function st_of(self)
	local s = state[self]
	if not s then s = { hits = 0, hit_time = -1000, last_hurt = -1000 }; state[self] = s end
	return s
end

local function hp_max(self)
	return self.child and CHILD_HP or ADULT_HP
end

local function fleeing(self)
	return self.child or (self.health or 0) <= hp_max(self) * 0.5
end

----------------------------------------------------------------------------------
-- Health
----------------------------------------------------------------------------------
local function apply_health(self)
	local want = hp_max(self)
	-- The engine's hp_max property does not read back reliably; remember the applied value on the entity
	-- (serialized with it). Reading it back doubled health every second (20 -> 1280).
	local old = self._pop_hp_max or 20
	if old == want then return end
	local fraction = math.min(1, (self.health or old) / old)
	self._pop_hp_max = want
	self.object:set_properties({ hp_max = want })
	self.health = math.max(1, fraction * want)
end
populations.apply_health = apply_health

----------------------------------------------------------------------------------
-- Gear
----------------------------------------------------------------------------------
local ARMOR_SLOTS = { head = "helmet", torso = "chestplate", legs = "leggings", feet = "boots" }

local function sword_item() return "mcl_tools:sword_" .. cfg.get("villager_sword") end

local function equip(self)
	local st = st_of(self)
	if st.geared then return end
	st.geared = true
	local armor = cfg.get("villager_armor")
	if armor ~= "none" and self.armor_list then
		for slot, piece in pairs(ARMOR_SLOTS) do
			local name = "mcl_armor:" .. piece .. "_" .. armor
			if core.registered_items[name] then self.armor_list[slot] = name end
		end
		self:set_armor_texture()
	end
	local sword = sword_item()
	if core.registered_items[sword] then
		st.sword = sword
		self:set_wielditem(ItemStack(sword))
	end
end

local function unequip(self)
	local st = st_of(self)
	if not st.geared then return end
	st.geared = false
	if self.armor_list then
		for slot in pairs(ARMOR_SLOTS) do self.armor_list[slot] = "" end
		self:set_armor_texture()
	end
	if st.sword and self:get_wielditem():get_name() == st.sword then
		self:set_wielditem(ItemStack())
	end
	st.sword = nil
end
populations.unequip = unequip

local function end_fight(self)
	local st = st_of(self)
	st.enemy = nil
	st.called = nil
	st.cooldown = nil
	if self.attack then self.attack = nil end
	unequip(self)
end

----------------------------------------------------------------------------------
-- Enemies and calls for help
----------------------------------------------------------------------------------
local function is_ours(obj)
	local ent = obj:get_luaentity()
	return ent and (ent.name == "mobs_mc:villager" or ent.name == "mobs_mc:iron_golem")
end

local function valid_enemy(obj, from)
	if not obj or not obj:is_valid() then return false end
	local pos = obj:get_pos()
	if not pos or obj:get_hp() <= 0 and obj:is_player() then return false end
	if is_ours(obj) then return false end
	if obj:is_player() then
		local ok, mode = pcall(mcl_gamemode.get_gamemode, obj)
		if ok and mode ~= "survival" then return false end
	else
		local ent = obj:get_luaentity()
		if not ent or ent.dead or ent.removed then return false end
	end
	return vector.distance(from, pos) <= RANGE
end

local function call_for_help(victim, attacker)
	local pos = victim.object:get_pos()
	local best, bd
	for _, obj in ipairs(core.get_objects_inside_radius(pos, CALL_RANGE)) do
		local ent = obj:get_luaentity()
		if ent and ent ~= victim and ent.name == "mobs_mc:villager" and not ent.child and not ent._sleeping
			and not ent.dead and not fleeing(ent) then
			local s = st_of(ent)
			local busy = s.enemy or (s.called and s.called.obj:is_valid() and now() - s.called.time <= MEMORY)
			if not busy then
				local d = vector.distance(pos, obj:get_pos())
				if not bd or d < bd then best, bd = ent, d end
			end
		end
	end
	if best then st_of(best).called = { obj = attacker, time = now() } end
end

-- Called whenever a villager takes damage.
local function on_hurt(self, reason, damage)
	local st = st_of(self)
	local t = now()
	st.last_hurt = t
	local source = reason and reason.source
	if not source or not source:is_valid() or source == self.object or is_ours(source) then return end
	if t - st.hit_time <= MEMORY then st.hits = st.hits + 1 else st.hits = 1 end
	st.hit_time = t
	if cfg.get("villagers_can_aid_others") then
		local chance = math.min(MAX_HELP, HELP_PER_HIT * st.hits)
		if fleeing(self) or math.random() < chance then call_for_help(self, source) end
	end
	if cfg.get("villagers_defend_themselves") and not fleeing(self) and valid_enemy(source, self.object:get_pos()) then
		st.enemy = source
		st.last_action = t
	end
end

----------------------------------------------------------------------------------
-- The fight (first entry of the villager's AI list)
----------------------------------------------------------------------------------
local function defend(self, self_pos, dtime)
	local st = state[self]
	if not st then return false end
	local t = now()
	if fleeing(self) or self._sleeping then
		if st.enemy or st.geared then end_fight(self) end
		return false
	end
	local enemy = st.enemy
	if enemy and not valid_enemy(enemy, self_pos) then enemy = nil; st.enemy = nil end
	if not enemy and st.called and cfg.get("villagers_can_aid_others") then
		local c = st.called
		if t - c.time <= MEMORY and valid_enemy(c.obj, self_pos) then
			enemy = c.obj
			st.enemy = enemy
			st.last_action = st.last_action or t
		else
			st.called = nil
		end
	end
	if not enemy or t - (st.last_action or t) >= MEMORY then
		if st.enemy or st.geared then end_fight(self) end
		return false
	end
	equip(self)
	local target_pos = enemy:get_pos()
	local dist = vector.distance(self_pos, target_pos)
	self:look_at(target_pos)
	st.repath = (st.repath or 0) - dtime
	if dist > REACH - 0.3 and st.repath <= 0 then
		st.repath = 0.5
		self:gopath(target_pos, 1.0)
	end
	st.cooldown = (st.cooldown or 0) - dtime
	if dist <= REACH + 0.6 and st.cooldown <= 0 then
		st.cooldown = ATTACK_INTERVAL
		st.last_action = t
		self.attack = enemy
		self.damage = 1 -- the sword brings the rest: a hit like a player's
		self:custom_attack()
		self.attack = nil
	end
	return "_pop_fighting"
end

----------------------------------------------------------------------------------
-- Iron golems
----------------------------------------------------------------------------------
local GOLEM_FACTORS = { movement_speed = 1.3, damage = 1.25 }
local function strengthen(self)
	local def = core.registered_entities["mobs_mc:iron_golem"]
	local on = cfg.get("stronger_golems")
	for field, f in pairs(GOLEM_FACTORS) do
		local base = rawget(def, field) or def[field]
		if base then self[field] = on and base * f or base end
	end
	local range = rawget(def, "view_range") or def.view_range or 16
	self.view_range = on and math.max(range, RANGE) or range
	local track = rawget(def, "tracking_distance") or def.tracking_distance or range
	self.tracking_distance = on and math.max(track, RANGE) or track
end

function populations.refresh_golems()
	for _, ent in pairs(core.luaentities) do
		if ent.name == "mobs_mc:iron_golem" then strengthen(ent) end
	end
end

----------------------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------------------
core.register_on_mods_loaded(function()
	local ent = core.registered_entities["mobs_mc:villager"]
	if not ent then return end

	ent.wears_armor = "no_pickup"
	ent.armor_drop_probability = { head = 0, torso = 0, legs = 0, feet = 0 }
	ent.wielditem_drop_probability = 0
	ent.reach = REACH
	ent.sounds = {} -- no villager voice at all (neither the "hmm" nor a borrowed male player voice)

	local orig_recv = ent.receive_damage or mcl_mobs.mob_class.receive_damage
	ent.receive_damage = function(self, reason, damage)
		local r = orig_recv(self, reason, damage)
		if r and damage and damage > 0 then on_hurt(self, reason, damage) end
		return r
	end

	local orig_schedule = ent.schedule
	ent.schedule = function(self)
		orig_schedule(self)
		if self.ai_functions and self.ai_functions[1] ~= defend then table.insert(self.ai_functions, 1, defend) end
	end

	local orig_activate = ent.on_activate
	ent.on_activate = function(self, staticdata, dtime)
		local r = orig_activate(self, staticdata, dtime)
		if r == false then return r end
		-- gear never survives a reload
		if self.armor_list then for slot in pairs(ARMOR_SLOTS) do self.armor_list[slot] = "" end end
		apply_health(self)
		populations.refresh_tag(self)
		return r
	end

	local golem = core.registered_entities["mobs_mc:iron_golem"]
	if golem then
		local orig_gact = golem.on_activate
		golem.on_activate = function(self, staticdata, dtime)
			local r = orig_gact(self, staticdata, dtime)
			if r == false then return r end
			strengthen(self)
			return r
		end
		local orig_grecv = golem.receive_damage or mcl_mobs.mob_class.receive_damage
		golem.receive_damage = function(self, reason, damage)
			local r = orig_grecv(self, reason, damage)
			if r and damage and damage > 0 then st_of(self).last_hurt = now() end
			return r
		end
	end
end)

-- Every second: health follows age; every 2 s: healing.
local timer, beat = 0, 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 1 then return end
	timer = 0
	beat = beat + 1
	local t = now()
	for _, ent in pairs(core.luaentities) do
		local n = ent.name
		if (n == "mobs_mc:villager" or n == "mobs_mc:iron_golem") and ent.object:get_pos() and not ent.dead then
			if n == "mobs_mc:villager" then
				apply_health(ent)
				if state[ent] and state[ent].geared and not state[ent].enemy then unequip(ent) end
			end
			if beat % 2 == 0 then
				local st = state[ent]
				if (not st or t - st.last_hurt >= MEMORY) then
					local max = ent._pop_hp_max or 20
					if ent.health and ent.health < max then ent:heal_mob(1, max) end
				end
			end
		end
	end
end)

populations.defend = defend
