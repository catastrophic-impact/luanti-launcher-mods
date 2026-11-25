-- Villagers as people: gender (kept near half and half per village), names, player skins, name tags,
-- and the man-and-woman-only family rules. A "village" is everyone within 64 blocks of the villager
-- (no bells: a bell can be broken). Persistence: self._pop is a plain table, so Mineclonia's
-- get_staticdata serialises it with the rest of the mob.
local names = populations.names
local storage = core.get_mod_storage()
local VILLAGE_RADIUS = 64
local NAME_RANGE = 32 -- name tags show up to this many blocks from a player
-- The zombie body: clean humanoid with standard head UVs, so a player skin fits (the piglin head is 10 px wide with its own
-- UV layout: its back, sides and top fell on transparent skin pixels). Mineclonia's player meshes break as mobs.
local MESH = { male = "mobs_mc_zombie.b3d", female = "mobs_mc_zombie.b3d" }
local SKIN_GROUP = { steve = "male", alex = "female" }

----------------------------------------------------------------------------------
-- Skins: textures/populations_<steve|alex>_<hair>_<shirt>_<pants>.png
----------------------------------------------------------------------------------
local skins = { male = {}, female = {} }
local skin_set = {}
do
	local list = core.get_dir_list(core.get_modpath("populations") .. "/textures", false)
	table.sort(list)
	for _, file in ipairs(list) do
		local kind, rest = file:match("^populations_(%a+)_(.+)%.png$")
		local gender = kind and SKIN_GROUP[kind]
		if gender then
			local id = kind .. "_" .. rest
			table.insert(skins[gender], id)
			skin_set[id] = gender
		end
	end
end
local function random_skin(gender)
	local list = skins[gender]
	return list[math.random(#list)]
end
populations.skins = skins

----------------------------------------------------------------------------------
-- Dead people (so a surviving partner may start a new family)
----------------------------------------------------------------------------------
local dead = core.deserialize(storage:get_string("dead")) or {}
local function mark_dead(id)
	if id and not dead[id] then
		dead[id] = true
		storage:set_string("dead", core.serialize(dead))
	end
end
populations.is_dead = function(id) return dead[id] == true end
populations._mark_dead = mark_dead

----------------------------------------------------------------------------------
-- People
----------------------------------------------------------------------------------
local function new_id()
	return string.format("%x-%08x%08x", os.time(), math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
end

local function pick(list) return list[math.random(#list)] end

local function full_name(p) return p.first .. " " .. p.last end

local function villagers_near(pos)
	local found = {}
	for _, obj in ipairs(core.get_objects_inside_radius(pos, VILLAGE_RADIUS)) do
		local ent = obj:get_luaentity()
		if ent and ent.name == "mobs_mc:villager" and ent._pop then
			found[#found + 1] = ent
		end
	end
	return found
end

-- Whichever gender the village around pos has fewer of (a coin flip when even).
local function balanced_gender(pos)
	local men, women = 0, 0
	for _, ent in ipairs(villagers_near(pos)) do
		if ent._pop.gender == "male" then men = men + 1 else women = women + 1 end
	end
	if men == women then return math.random(2) == 1 and "male" or "female" end
	return men < women and "male" or "female"
end

local function new_person(pos, last)
	local gender = balanced_gender(pos)
	return {
		id = new_id(), gender = gender, first = pick(names[gender]),
		last = last or pick(names.last), skin = random_skin(gender),
	}
end
populations.new_person = new_person

----------------------------------------------------------------------------------
-- Look: player mesh, skin, name tag
----------------------------------------------------------------------------------
local function apply_look(self)
	local p = self._pop
	if not p then return end
	local tex = { "blank.png", "populations_" .. p.skin .. ".png" } -- slot 1 = armor layer, slot 2 = skin
	self.base_texture = tex
	self.base_mesh = MESH[p.gender]
	self.base_size = { x = 1, y = 1, z = 1 }
	self.object:set_properties({ mesh = MESH[p.gender], textures = tex, visual_size = { x = 1, y = 1, z = 1 } })
	if self.child then self:scale_size_of_child(0.5) end
end

local function job_of(self)
	if self._profession and self._profession ~= "nitwit" and self.description then
		-- descriptions are translation escape sequences: use the plain text (also what the width measure needs)
		return core.get_translated_string("en", self.description)
	end
end

-- Luanti draws multi-line name tags left aligned: pad the shorter lines with spaces so every line is centered on the longest.
-- Widths are Helvetica-like estimates (1/1000 em); a space is 278.
local NARROW = { i = 222, l = 222, j = 222, I = 278, f = 278, t = 278, r = 333, [" "] = 278, ["/"] = 278, ["."] = 278, ["'"] = 191, ["-"] = 333 }
local WIDE = { m = 833, w = 722, M = 833, W = 944 }
local function text_width(str)
	local w = 0
	for i = 1, #str do
		local c = str:sub(i, i)
		if NARROW[c] then w = w + NARROW[c]
		elseif WIDE[c] then w = w + WIDE[c]
		elseif c:match("%d") then w = w + 556
		elseif c:match("%u") then w = w + 667
		else w = w + 540 end
	end
	return w
end
local function center_lines(lines)
	local widest = 0
	for _, l in ipairs(lines) do widest = math.max(widest, text_width(l)) end
	local out = {}
	for i, l in ipairs(lines) do
		local pad = math.floor((widest - text_width(l)) / 2 / 278 + 0.5)
		out[i] = string.rep(" ", pad) .. l
	end
	return table.concat(out, "\n")
end
populations._center_lines = center_lines

-- A player's name tag renames the villager; our own tag text is never mistaken for one.
local function refresh_tag(self)
	local p = self._pop
	if not p then return end
	local shown = self.nametag
	if shown and shown ~= "" and shown ~= self._pop_tag and shown ~= full_name(p) and not shown:find("\n", 1, true) then
		self._pop_custom = shown
	end
	local lines = { self._pop_custom or full_name(p) }
	local job = job_of(self)
	if job then lines[#lines + 1] = job end
	local props = self.object:get_properties()
	local max = self._pop_hp_max or (props and props.hp_max) or 20
	lines[#lines + 1] = string.format("%d/%d", math.ceil(self.health or max), math.ceil(max))
	local tag = center_lines(lines)
	-- Luanti draws name tags at any distance; the spec says 32 blocks: hide the tag while no player is that close.
	local pos = self.object:get_pos()
	local near = false
	for _, player in ipairs(core.get_connected_players()) do
		if vector.distance(player:get_pos(), pos) <= NAME_RANGE then near = true; break end
	end
	if tag ~= self._pop_tag or near ~= self._pop_near then
		self._pop_tag = tag
		self._pop_near = near
		self.nametag = tag
		self:update_tag()
	end
end
populations.refresh_tag = refresh_tag

----------------------------------------------------------------------------------
-- Identity: new villagers, births
----------------------------------------------------------------------------------
local pending_birth -- { a, b } entities while conceive_child runs

local function ensure(ent)
	if not ent._pop then
		ent._pop = new_person(ent.object:get_pos())
		refresh_tag(ent)
	end
	return ent._pop
end

local function assign(self)
	local p = self._pop
	if p and not skin_set[p.skin] then p.skin = random_skin(p.gender) end
	if not p then
		local pos = self.object:get_pos()
		if pending_birth and self.child then
			local a, b = pending_birth[1], pending_birth[2]
			local pa, pb = ensure(a), ensure(b)
			local father, mother = a, b
			if pa.gender ~= "male" then father, mother = b, a end
			local him, her = father._pop, mother._pop
			him.partner, her.partner = her.id, him.id
			her.last = him.last
			self._pop = new_person(pos, him.last)
			refresh_tag(father)
			refresh_tag(mother)
		else
			self._pop = new_person(pos)
		end
	end
	apply_look(self)
	refresh_tag(self)
end

----------------------------------------------------------------------------------
-- Family rules
----------------------------------------------------------------------------------
local function free_for(p, other)
	return not p.partner or p.partner == other.id or dead[p.partner] == true
end

local function can_pair(a, b)
	local pa, pb = a._pop, b._pop
	if not pa or not pb or pa.gender == pb.gender then return false end
	return free_for(pa, pb) and free_for(pb, pa)
end
populations.can_pair = can_pair

----------------------------------------------------------------------------------
-- Wire it into the villager and zombie villager entities
----------------------------------------------------------------------------------
core.register_on_mods_loaded(function()
	local ent = core.registered_entities["mobs_mc:villager"]
	if not ent then return end
	local mob_class = mcl_mobs.mob_class

	-- Player-shaped body (the zombie body).
	local _, zip, ip = populations.borrow_zombie_body(ent)
	ip.textures = { "blank.png", "populations_" .. skins.male[1] .. ".png" }
	ent.animation.walk_speed, ent.animation.run_speed = 24, 24
	ent.animation.run_start, ent.animation.run_end = ent.animation.walk_start, ent.animation.walk_end
	ent.animation.nitwit_start, ent.animation.nitwit_end, ent.animation.nitwit_speed = 40, 49, 2
	ent.animation.sleep_start, ent.animation.sleep_end, ent.animation.sleep_speed = 40, 40, 0
	-- the piglin's gait scaling (frame speed ~ sqrt(velocity)): the villager's linear scaling flails limbs at a run
	local piglin = core.registered_entities["mobs_mc:piglin"]
	if piglin and piglin.set_animation_speed then ent.set_animation_speed = piglin.set_animation_speed end

	-- Arms hang down unless the villager holds something (the zombie's forward arms suit a held sword).
	populations.ARM_SWING_SIGN = -1 -- verified by screenshot (tests/pop_arm_shots): +1 swung each arm WITH its same-side leg
	local ARM_DOWN = { rotation = { vec = vector.apply(vector.new(-90, 0, 0), math.rad), absolute = false } }
	local function set_pose(self, down)
		if self._pop_arms_down == down then return end
		self._pop_arms_down = down
		for _, bone in ipairs({ "arm.left", "arm.right" }) do
			if down then self.object:set_bone_override(bone, ARM_DOWN) else self.object:set_bone_override(bone, {}) end
		end
	end
	populations.set_pose = set_pose
	local orig_custom = ent.do_custom
	ent.do_custom = function(self, dtime)
		local r = orig_custom and orig_custom(self, dtime)
		if self._pop then
			local w = self.get_wielditem and self:get_wielditem()
			local down = not w or w:is_empty()
			local anim = self._current_animation
			if down and (anim == "walk" or anim == "run") then
				-- The zombie's walk cycle keeps its arms still: swing them against the legs (leg curve measured from the b3d: left leg +33 .. -46 degrees, period 40 frames).
				local ph = self._pop_phase
				if not ph then ph = 1; self._pop_arms_down = "swing" end
				self._pop_arm_t = (self._pop_arm_t or 0) + dtime
				if self._pop_arm_t >= 0.1 then
					local _, fps = self.object:get_animation()
					local ahead = ph + (fps or 24) * self._pop_arm_t
					self._pop_phase = ahead % 40
					local leg = -40 * math.sin(2 * math.pi * (ahead - 21) / 40)
					local sw = populations.ARM_SWING_SIGN * leg * 0.9
					local function rot(v) return { rotation = { vec = vector.apply(vector.new(v, 0, 0), math.rad), absolute = false, interpolation = 0.1 } } end
					self.object:set_bone_override("arm.left", rot(-90 - sw))
					self.object:set_bone_override("arm.right", rot(-90 + sw))
					self._pop_arm_t = 0
				end
			else
				self._pop_phase = nil
				set_pose(self, down)
			end
		end
		return r
	end

	-- Our skin replaces the profession overlays; the job is shown in the name tag.
	local orig_overlaid = ent.get_overlaid_texture
	ent.get_overlaid_texture = function(self)
		if self._pop then return "blank.png" end -- slot 1 is the armor layer; the skin sits in slot 2
		return orig_overlaid(self)
	end
	local orig_update = ent.update_textures
	ent.update_textures = function(self)
		if self._pop then return apply_look(self) end
		return orig_update(self)
	end

	-- every tag update (also Mineclonia's own) respects the range
	local orig_get_nametag = ent.get_nametag or mob_class.get_nametag
	ent.get_nametag = function(self)
		if self._pop and self._pop_near == false then return "" end
		return orig_get_nametag(self)
	end

	local orig_activate = ent.on_activate
	ent.on_activate = function(self, staticdata, dtime)
		local r = orig_activate(self, staticdata, dtime)
		if r == false then return r end
		self._pop_arms_down = nil -- the field is saved with the mob but bone overrides are not: re-apply the pose after every reload
		assign(self)
		return r
	end

	-- Only a man and a woman, and only partners of each other (or of the dead).
	local orig_love = ent.begin_lovemaking
	ent.begin_lovemaking = function(self, object, dtime)
		local other = object and object:get_luaentity()
		if not other or not can_pair(self, other) then return false end
		return orig_love(self, object, dtime)
	end

	local orig_conceive = ent.conceive_child
	ent.conceive_child = function(self, mate, bed)
		pending_birth = { self, mate }
		local ok, res = pcall(orig_conceive, self, mate, bed)
		pending_birth = nil
		if not ok then error(res) end
		return res
	end

	-- A zombified villager is still the same person (and the cure brings them back).
	local orig_export = ent.export_villager_data
	ent.export_villager_data = function(self)
		local data = orig_export(self)
		data.pop = self._pop and table.copy(self._pop)
		self._pop_converted = true
		return data
	end
	local orig_die = ent.on_die
	ent.on_die = function(self, pos, reason)
		local r = orig_die(self, pos, reason)
		if self._pop and not self._pop_converted then mark_dead(self._pop.id) end
		return r
	end

	local zent = core.registered_entities["mobs_mc:villager_zombie"]
	if zent then
		local orig_prev = zent.previous_staticdata
		zent.previous_staticdata = function(self)
			local data = orig_prev(self)
			local pop = self._previous_incarnation and self._previous_incarnation.pop
			if pop then
				data._pop = table.copy(pop)
				data.nametag = nil
			end
			return data
		end
		local zdie = zent.on_die
		zent.on_die = function(self, pos, reason)
			local pop = self._previous_incarnation and self._previous_incarnation.pop
			if pop then mark_dead(pop.id) end
			if zdie then return zdie(self, pos, reason) end
		end
	end
end)

-- Name tags follow health and job.
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 1 then return end
	timer = 0
	for _, ent in pairs(core.luaentities) do
		if ent.name == "mobs_mc:villager" and ent._pop and ent.object:get_pos() then refresh_tag(ent) end
	end
end)

-- The villager "hmm" voices (trading accept/deny/trade) are played straight through core.sound_play: drop them.
local VOICE = { mobs_mc_villager = true, mobs_mc_villager_accept = true, mobs_mc_villager_deny = true,
	mobs_mc_villager_trade = true, mobs_mc_villager_hurt = true }
local orig_sound_play = core.sound_play
core.sound_play = function(spec, ...)
	local name = type(spec) == "table" and spec.name or spec
	if VOICE[name] then return end
	return orig_sound_play(spec, ...)
end

-- Death messages and trade windows name the person, not the three-line name tag.
local orig_object_name = mcl_util.get_object_name
mcl_util.get_object_name = function(object)
	local ent = object and object:is_valid() and not object:is_player() and object:get_luaentity()
	if ent and ent._pop then return ent._pop_custom or full_name(ent._pop) end
	return orig_object_name(object)
end
