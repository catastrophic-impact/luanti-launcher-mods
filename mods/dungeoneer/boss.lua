-- The boss: a zombie twice the normal size with a random name, a boss bar, lots of health and armor, and abilities that grow with the tier:
--   tier 1: calls zombie helpers (at most 4 alive)   tier 2: + ground slam (a ring of flames shows where it lands)
--   tier 3: + teleports to a player who keeps their distance   tier 4: all of it, faster and harder.
-- It notices anybody within 24 blocks, even through walls. Beating it marks the run as cleared and unseals the chest.
local S = core.get_translator("dungeoneer")
local mob_class = mcl_mobs.mob_class

local BASE_HP = 200
local TOUGH = { 1.0, 1.5, 2.0, 3.0 }       -- armor: damage taken is divided by this (stacked on the base health)
local DAMAGE = { 6, 8, 10, 13 }
local NOTICE = 24
local TAG_RANGE = 16 -- the name tag floats over the boss only for players this close that can see it

local PRE = { "Gor", "Mor", "Skar", "Vel", "Dra", "Zul", "Krag", "Thok", "Ner", "Bal", "Urs", "Hex" }
local SUF = { "gul the Hollow", "dak the Unburied", "bone the Gravewalker", "thrax the Pale", "moth the Deepwarden", "gar Ironjaw", "rak the Rotting", "ul the Forgotten" }
function dungeoneer.boss_name(rng)
	return PRE[rng:next(1, #PRE)] .. SUF[rng:next(1, #SUF)]
end

-- the definition: Mineclonia's zombie, bigger and meaner
local zdef = table.copy(mcl_mobs.registered_mobs["mobs_mc:zombie"])
-- register_mob moves the object-property fields (visual, mesh, textures, collisionbox, visual_size ...) of a definition into
-- `initial_properties`: lift them back to the top level, or the copy loses its mesh and becomes an invisible sprite
for k, v in pairs(zdef.initial_properties or {}) do if zdef[k] == nil then zdef[k] = v end end
zdef.initial_properties = nil
local zombie_custom = zdef.do_custom
local boss = table.merge(zdef, {
	description = S("Dungeon Boss"),
	hp_min = BASE_HP, hp_max = BASE_HP, xp_min = 60, xp_max = 60,
	collisionbox = { -0.6, 0.0, -0.6, 0.6, 3.9, 0.6 },
	selectionbox = { -0.6, 0.0, -0.6, 0.6, 3.9, 0.6 },
	visual_size = { x = 2, y = 2.2 },
	ignited_by_sunlight = false,
	damage = 6, reach = 3.5, movement_speed = 4.2,
	drops = { { name = "mcl_mobitems:rotten_flesh", chance = 1, min = 3, max = 6 } },
	tracking_distance = 40.0, view_range = NOTICE,
	_spawn_category = "monster",
})
-- notices players within 24 blocks even through walls. (Mineclonia's own nearest-player rule always wants line of sight to PICK a target,
-- so this is our own rule: nearest connected player within range, no sight test; a current target is kept while within range + 4.)
local function notice_rule(self, self_pos, dtime, current, is_current)
	if is_current then
		if current and current:is_valid() and vector.distance(self_pos, current:get_pos()) <= NOTICE + 4 and self:test_object_and_restriction(current, current:get_pos()) then return current end
		return nil
	end
	if not self:check_timer("seek_target", 0.5) then return false end
	local best, bd = nil, NOTICE * NOTICE
	for player, pos in mcl_player.iterate_connected_players(true) do
		local d = (pos.x - self_pos.x) ^ 2 + (pos.y - self_pos.y) ^ 2 + (pos.z - self_pos.z) ^ 2
		if d <= bd and self:test_object_and_restriction(player, pos) then best, bd = player, d end
	end
	return best
end
boss._targeting_rules = { mcl_mobs.build_target_rule({ fn = notice_rule }) }
boss.on_die = function(self, pos, reason) dungeoneer.boss_died(self, pos) end

local function players_near(pos, r)
	local t = {}
	for _, p in ipairs(core.get_connected_players()) do
		if p:get_hp() > 0 and vector.distance(p:get_pos(), pos) <= r then t[#t + 1] = p end
	end
	return t
end

local function ring_particles(pos, radius, time)
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		core.add_particlespawner({
			amount = 6, time = time, exptime = { min = 0.4, max = 0.8 }, size = { min = 2, max = 4 },
			pos = vector.new(pos.x + math.cos(a) * radius, pos.y + 0.2, pos.z + math.sin(a) * radius),
			vel = { min = vector.new(0, 0.6, 0), max = vector.new(0, 1.6, 0) }, texture = "fire_basic_flame.png", glow = 14,
		})
	end
end

local function helpers_alive(self)
	local n = 0
	for _, o in ipairs(core.get_objects_inside_radius(self.object:get_pos(), 30)) do
		local e = o:get_luaentity()
		if e and e._dg_helper_of == self._dg_run then n = n + 1 end
	end
	return n
end

local function summon(self)
	local pos = self.object:get_pos()
	for i = 1, 2 do
		local a = math.random() * math.pi * 2
		local p = vector.new(pos.x + math.cos(a) * 3, pos.y + 0.5, pos.z + math.sin(a) * 3)
		if core.get_node(p).name == "air" and core.get_node(vector.offset(p, 0, 1, 0)).name == "air" then
			local obj = core.add_entity(p, "mobs_mc:zombie")
			local e = dungeoneer.tag_mob(obj, self._dg_run)
			if e then e._dg_helper_of = self._dg_run; e._dg_hp = 1.0 end
		end
	end
end

local function slam(self)
	local pos = self.object:get_pos()
	local radius = 5
	ring_particles(pos, radius, 1.5) -- telegraph: the ring of flames shows where it lands
	core.after(1.5, function()
		if not self.object or not self.object:get_pos() then return end
		local c = self.object:get_pos()
		for _, p in ipairs(players_near(c, radius)) do
			mcl_util.deal_damage(p, DAMAGE[self._dg_tier or 2] + 2, { type = "mob", source = self.object, direct = self.object })
			local d = vector.direction(c, p:get_pos()); d.y = 0.6
			p:add_velocity(vector.multiply(d, 12))
		end
		ring_particles(c, radius, 0.4)
	end)
end

local function teleport(self, target)
	local tp = target:get_pos()
	-- a free spot (two air nodes, solid ground) 2.5 blocks from the player: several tries, a corridor is narrow
	for _ = 1, 12 do
		local a = math.random() * math.pi * 2
		local dest = vector.new(tp.x + math.cos(a) * 2.5, tp.y, tp.z + math.sin(a) * 2.5)
		local ok = core.get_node(dest).name == "air" and core.get_node(vector.offset(dest, 0, 1, 0)).name == "air"
			and core.registered_nodes[core.get_node(vector.offset(dest, 0, -1, 0)).name] and core.registered_nodes[core.get_node(vector.offset(dest, 0, -1, 0)).name].walkable
		if ok then
			ring_particles(self.object:get_pos(), 1.5, 0.3)
			self.object:set_pos(dest)
			ring_particles(dest, 1.5, 0.3)
			return true
		end
	end
end

boss.do_custom = function(self, dtime, moveresult)
	if zombie_custom then zombie_custom(self, dtime, moveresult) end
	if self.dead or not self._dg_run then return end
	local tier = self._dg_tier or 1
	local pos = self.object:get_pos()
	-- boss bar for everybody within 80 blocks, every step (dynamic bars are rebuilt each step)
	local hp = math.max(0, self.health or 0)
	local def = { text = self.nametag ~= "" and self.nametag or S("Dungeon Boss"), color = "red", percentage = math.floor(hp / BASE_HP * 100) }
	for _, p in ipairs(core.get_connected_players()) do
		local d = vector.distance(pos, p:get_pos())
		if d <= 80 then mcl_bossbars.add_bar(p, def, true, d) end
	end
	local t = self._dg_t or {}
	self._dg_t = t
	-- Name tag: the engine draws an object's tag for EVERYONE in range, through walls and from far away, and cannot be told per player.
	-- So it is only switched on while some player within TAG_RANGE has line of sight to the boss.
	t.tag = (t.tag or 0) - dtime
	if t.tag <= 0 then
		t.tag = 0.5
		local show = false
		for _, p in ipairs(core.get_connected_players()) do
			if vector.distance(pos, p:get_pos()) <= TAG_RANGE and self:target_visible(pos, p) then show = true; break end
		end
		if show ~= self._dg_tag_shown then
			self._dg_tag_shown = show
			self.object:set_properties({ nametag = show and (self.nametag or "") or "" })
		end
	end
	local target = self._active_target
	if not target or not target:is_valid() or not target:is_player() then return end
	local speed = tier == 4 and 1.5 or 1.0
	for k, v in pairs(t) do if k ~= "tag" then t[k] = v - dtime end end
	if (t.summon or 0) <= 0 then t.summon = 20 / speed; if helpers_alive(self) < 4 then summon(self) end end
	if tier >= 2 and (t.slam or 0) <= 0 and vector.distance(pos, target:get_pos()) <= 6 then t.slam = 12 / speed; slam(self) end
	if tier >= 3 and (t.tp or 0) <= 0 and vector.distance(pos, target:get_pos()) > 12 then t.tp = 10 / speed; teleport(self, target) end
end

mcl_mobs.register_mob("dungeoneer:boss", boss)

-- Spawn the boss of a run in the boss room.
function dungeoneer.spawn_boss(run, minp, layout)
	local rng = PcgRandom(run.seed + 2)
	local b = layout.boss
	local obj = core.add_entity(vector.new(minp.x + b.cx, minp.y + b.y0 + 0.5, minp.z + b.cz), "dungeoneer:boss")
	local ent = dungeoneer.tag_mob(obj, run.id)
	if not ent then return nil end
	ent._dg_tier = run.tier
	ent._dg_hp = TOUGH[run.tier]
	ent.damage = DAMAGE[run.tier]
	ent.nametag = dungeoneer.boss_name(rng)
	obj:set_properties({ nametag = "" }) -- shown by do_custom while a player can see the boss up close
	return obj
end

-- Death: the run is cleared and the chest unseals.
function dungeoneer.boss_died(self, pos)
	local run = dungeoneer.runs()[tostring(self._dg_run)]
	if not run or run.cleared then return end
	run.cleared = true
	dungeoneer.update_run(run)
	local minp = multiversatile.slot_area("dungeon", run.slot)
	dungeoneer.award_keys(run, minp, dungeoneer.run_layout(run))
	for _, p in ipairs(players_near(pos or self.object:get_pos(), 80)) do
		if rawget(_G, "mcl_title") then mcl_title.set(p, "actionbar", { text = S("The boss has fallen. The chest has unsealed."), color = "gold", stay = 100 }) end
	end
end
