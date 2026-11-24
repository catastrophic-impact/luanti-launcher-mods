-- Pet behaviour: lead + taming, follow AI, stable / downed recovery, upkeep.
local S = core.get_translator("tameful")
local mob_class = mcl_mobs.mob_class
local roster = tameful.roster
local msg, esc = tameful.msg, core.formspec_escape
local cfg = tameful.cfg

local EXCLUDED = {
	["mobs_mc:axolotl"] = true, ["mobs_mc:cod"] = true, ["mobs_mc:salmon"] = true,
	["mobs_mc:tropical_fish"] = true, ["mobs_mc:pufferfish"] = true,
	["mobs_mc:dolphin"] = true, ["mobs_mc:squid"] = true, ["mobs_mc:glow_squid"] = true,
	["mobs_mc:trader_llama"] = true,
}
tameful.EXCLUDED = EXCLUDED

----------------------------------------------------------------------------------
-- Lead item
----------------------------------------------------------------------------------
core.register_craftitem("tameful:lead", {
	description = S("Lead"),
	_doc_items_longdesc = S("Right-click an animal with a lead to tame it."),
	inventory_image = "tameful_lead.png",
	groups = { tool = 1 },
})
core.register_craft({
	output = "tameful:lead",
	recipe = {
		{ "mcl_mobitems:string", "", "" },
		{ "", "mcl_mobitems:string", "" },
		{ "", "", "mcl_mobitems:string" },
	},
})

-- Saddles from rabbit hide or wool instead of leather, and with a copper ingot instead of iron (same shape as the vanilla saddle).
do
	local hides = { "mcl_mobitems:leather", "mcl_mobitems:rabbit_hide", "group:wool" }
	local metals = { "mcl_core:iron_ingot", "mcl_copper:copper_ingot" }
	for hi, hide in ipairs(hides) do
		for mi, metal in ipairs(metals) do
			if not (hi == 1 and mi == 1) then -- that one is Mineclonia's own
				core.register_craft({
					output = "mcl_mobitems:saddle",
					recipe = { { "", hide, "" }, { hide, metal, hide } },
				})
			end
		end
	end
end

----------------------------------------------------------------------------------
-- Snapshots, stable, downed, resummon
----------------------------------------------------------------------------------
-- The picture in /tameful uses the pet's real mesh and textures (some animals, like wolves, compute theirs).
local function remember_look(rec, ent)
	local props = ent.object:get_properties()
	if props and props.mesh and props.textures and #props.textures > 0 then
		rec.mesh = props.mesh
		rec.textures = table.copy(props.textures)
		rec.anim_frame = ent.animation and ent.animation.stand_start or 0
	end
end

-- Serialized staticdata of a loaded pet (what Mineclonia itself would save), plus its hp numbers.
local function capture(ent, rec)
	local t = ent:get_staticdata_table()
	if not t then return nil end
	local props = ent.object:get_properties()
	rec.hp_max = props and props.hp_max or rec.hp_max
	rec.hp = math.max(0, t.health or rec.hp or 0)
	rec.order = ent.order
	remember_look(rec, ent)
	return t
end

local function retire_copy(rec)
	rec.epoch = (rec.epoch or 0) + 1
	rec.loaded = false
end

-- Put a pet into the stable. downed = recovery countdown. keep_entity = the caller removes it (on_die).
function tameful.stable(id, downed, keep_entity)
	local rec, owner = tameful.find_record(id)
	if not rec then return false end
	local ent = tameful.find_loaded(id)
	if ent then
		local t = capture(ent, rec)
		if t then
			t.order = ""
			if downed then t.health = rec.hp_max or t.health end
			t.dead = nil
			rec.snapshot = core.serialize(t)
			if downed then rec.hp = rec.hp_max end
		end
		if not keep_entity then ent.object:remove() end
	end
	-- (an unloaded pet is stabled from its last saved snapshot; its stale copy is retired below)
	if not rec.snapshot then return false end
	retire_copy(rec)
	rec.order = ""
	if downed then
		rec.status = "downed"
		rec.ready_at = core.get_gametime() + cfg.get("downed_seconds")
	else
		rec.status = "stabled"
		rec.ready_at = nil
	end
	tameful.save()
	return true
end

function tameful.ready_in(rec)
	if rec.status ~= "downed" or not rec.ready_at then return 0 end
	return math.max(0, math.ceil(rec.ready_at - core.get_gametime()))
end

-- Bring a stabled pet out next to the player. Returns ok, reason.
function tameful.resummon(id, player)
	local pname = player:get_player_name()
	local rec = roster[pname] and roster[pname][id]
	if not rec then return false, "unknown" end
	if rec.status == "out" then return false, "already out" end
	if tameful.ready_in(rec) > 0 then
		return false, S("@1 is still recovering (@2 s).", rec.name, tameful.ready_in(rec))
	end
	local max = cfg.get("max_summoned")
	if max > 0 and tameful.out_count(pname) >= max then
		return false, S("You already have @1 pet(s) out (limit).", max)
	end
	if not rec.snapshot then return false, "no snapshot" end
	local t = core.deserialize(rec.snapshot)
	if not t then return false, "bad snapshot" end

	local ppos = player:get_pos()
	local dir = player:get_look_dir()
	local pos = vector.new(ppos.x + dir.x * 2, ppos.y + 0.6, ppos.z + dir.z * 2)
	local n = core.get_node_or_nil(pos)
	if not n or core.registered_nodes[n.name] == nil or core.registered_nodes[n.name].walkable then
		pos = vector.offset(ppos, 0, 0.6, 0)
	end

	-- State first: the activation check below accepts only the copy that matches the roster.
	rec.epoch = (rec.epoch or 0) + 1
	rec.status = "out"
	rec.ready_at = nil
	rec.loaded = true
	t.order = ""
	t._tameful_epoch = rec.epoch
	t.nametag = tameful.display_name(rec, pname, nil)
	if rec.hp_max and (t.health or 0) <= 0 then t.health = rec.hp_max end
	local obj = core.add_entity(pos, rec.kind, core.serialize(t))
	if not obj then
		rec.status = "stabled"
		rec.loaded = false
		return false, "could not spawn"
	end
	tameful.save()
	return true
end

----------------------------------------------------------------------------------
-- Taming
----------------------------------------------------------------------------------
local pending = {}
tameful._pending = pending

local function tame_formspec(desc, player)
	local bc = uikit.cols(0.5, 6.0, 0.2, 2)
	return table.concat({
		uikit.begin(player, 7, 3.4),
		uikit.panel(0.2, 0.2, 6.6, 3.0),
		"label[0.5,0.7;", esc(S("Tame this @1?", desc)), "]",
		string.format("button_exit[%.2f,1.7;%.2f,%.2f;yes;%s]", bc[1].x, bc[1].w, uikit.row_h, esc(S("Yes"))),
		string.format("button_exit[%.2f,1.7;%.2f,%.2f;no;%s]", bc[2].x, bc[2].w, uikit.row_h, esc(S("No"))),
	})
end

-- Make `ent` a Tameful pet of `pname` (record + stats). Returns false when the owner is at max_tames.
local function adopt(ent, pname, quiet)
	local max = cfg.get("max_tames")
	if max > 0 and tameful.owner_count(pname) >= max then
		if not quiet then msg(pname, S("You already have @1 pets (limit).", max)) end
		return false
	end
	local id = tameful.new_id()
	local desc = tameful.kind_description(ent.name)
	ent.tamed = true
	ent.owner = pname
	ent.order = ent.order == "sit" and "sit" or ""
	ent._tameful_id = id
	ent._tameful_epoch = 0
	tameful.apply_stats(ent, true)
	local pos = ent.object:get_pos()
	local props = ent.object:get_properties()
	roster[pname] = roster[pname] or {}
	roster[pname][id] = {
		id = id, kind = ent.name, name = desc, status = "out", epoch = 0,
		pos = pos, dim = mcl_worlds.pos_to_dimension(pos), loaded = true,
		hp = ent.health, hp_max = props and props.hp_max, order = ent.order,
	}
	remember_look(roster[pname][id], ent)
	tameful.save()
	tameful.refresh_tag(ent)
	msg(pname, S("@1 is now your pet.", desc))
	local max_out = cfg.get("max_summoned")
	if max_out > 0 and tameful.out_count(pname) > max_out then
		-- the world already holds as many pets as allowed: the new one goes to the stable
		local rec = roster[pname][id]
		rec.snapshot = nil
		tameful.stable(id, false)
		msg(pname, S("@1 went to the stable (summon limit).", desc))
	end
	return true
end
tameful.adopt = adopt

local function do_tame(ent, player)
	local pname = player:get_player_name()
	if not adopt(ent, pname) then return false end
	if cfg.get("consume_lead") and not core.is_creative_enabled(pname) then
		local item = player:get_wielded_item()
		if item:get_name() == "tameful:lead" then
			item:take_item()
			player:set_wielded_item(item)
		end
	end
	return true
end
tameful._do_tame = do_tame

function tameful.toggle_order(ent, pname)
	local rec = tameful.find_record(ent._tameful_id)
	if ent.order == "sit" then
		ent.order = ""
		msg(pname, S("@1 follows you.", rec and rec.name or "Pet"))
	else
		ent:stay()
		msg(pname, S("@1 stays here.", rec and rec.name or "Pet"))
	end
	if rec then rec.order = ent.order end
end

local function needs_sneak(ent)
	return ent.saddle == "yes" or ent.name:find("horse", 1, true)
		or ent.name:find("llama", 1, true) or ent.name:find("donkey", 1, true)
		or ent.name:find("mule", 1, true) or ent.name:find("camel", 1, true)
		or ent.name:find("strider", 1, true)
end

----------------------------------------------------------------------------------
-- Follow AI (own function: starts early, runs faster than the animal's walk, brings it along when far)
----------------------------------------------------------------------------------
local FOLLOW_START = 6
local FOLLOW_STOP = 3
local FOLLOW_BONUS = 1.35 -- x movement_speed 6: measured 7.08 blocks/second (tests/tameful_speed_probe)

local function follow_owner(self, self_pos, dtime)
	if not self._tameful_id or (self.order or "") ~= "" or self.object:get_attach() then
		self.tameful_follow = nil
		return false
	end
	local owner = self.owner and core.get_player_by_name(self.owner)
	if not owner then return false end
	local opos = owner:get_pos()
	local d = vector.distance(self_pos, opos)
	if d > cfg.get("follow_teleport") then
		if self:teleport_to_owner(owner, opos) then
			self.tameful_follow = nil
			return false
		end
	end
	if d > FOLLOW_START or (self.tameful_follow and d > FOLLOW_STOP) then
		if self:check_timer("tameful_path", 0.4) then
			local penalties = table.merge(self.gwp_penalties, { WATER = 0.0 })
			self:gopath(opos, FOLLOW_BONUS, nil, 1, penalties)
		end
		self.tameful_follow = true
		return "tameful_follow"
	end
	if self.tameful_follow then
		self.tameful_follow = nil
		self:cancel_navigation()
		self:halt_in_tracks()
	end
	return false
end

-- Baby animals do not tag along behind a parent that is a pet (Mineclonia's herd-following picks the nearest adult of the species).
local function follow_herd_not_pets(self, pos)
	local f = self.herd_following
	local fe = f and f:get_luaentity()
	if fe and fe._tameful_id then self.herd_following = nil; return false end
	local orig_same = self.same_species_p
	self.same_species_p = function(me, other)
		if other._tameful_id then return false end
		return orig_same(me, other)
	end
	local r = mob_class.follow_herd(self, pos)
	self.same_species_p = nil
	return r
end

tameful._follow_herd = follow_herd_not_pets

----------------------------------------------------------------------------------
-- Wrap every tameable animal
----------------------------------------------------------------------------------
local function wrap_mob(name)
	local ent = core.registered_entities[name]
	if not ent then return end
	ent._tameful_wrapped = true

	local base = ent.ai_functions or mob_class.ai_functions
	local combined = { mob_class.sit_if_ordered, mob_class.check_attack, tameful.relax_home, follow_owner }
	for _, fn in ipairs(base) do
		if fn ~= mob_class.sit_if_ordered and fn ~= mob_class.check_travel_to_owner and fn ~= mob_class.check_attack then
			combined[#combined + 1] = (fn == mob_class.follow_herd) and follow_herd_not_pets or fn
		end
	end
	ent.ai_functions = combined

	-- Legs: Mineclonia scales the walk animation with velocity; pets move 2-6x faster than the wild animal (pig follow 7 b/s = 9.7 leg cycles/s,
	-- measured by tests/tameful_anim_probe), so cap the walk cycle rate.
	local orig_anim = ent.set_animation_speed or mob_class.set_animation_speed
	ent.set_animation_speed = function(self, custom_speed)
		orig_anim(self, custom_speed)
		if self._tameful_id and (self._current_animation == "walk" or self._current_animation == "run") then
			local range, speed = self.object:get_animation()
			if range and speed and range.y > range.x then
				local cap = (range.y - range.x) * tameful.MAX_LEG_CYCLES
				if speed > cap then self.object:set_animation_frame_speed(cap) end
			end
		end
	end

	-- Striders: no cold slow-down/shivering out of lava for pets, and keep the ride speed we set (Mineclonia resets drive_bonus when they leave lava).
	if name == "mobs_mc:strider" then
		local orig_ai = ent.ai_step
		ent.ai_step = function(self, dtime)
			orig_ai(self, dtime)
			if self._tameful_id then
				if self._aground then
					self:remove_physics_factor("movement_speed", "mobs_mc:strider_out_of_water")
					if self.shaking then self.shaking = false; self:set_textures(self.base_texture) end
				end
				if self._tameful_riding and self._tameful_drive_bonus then self.drive_bonus = self._tameful_drive_bonus end
			end
		end
	end

	-- Rabbits hop: pets hop again sooner so a following rabbit keeps up.
	if name == "mobs_mc:rabbit" then
		local orig_ms = ent.movement_step
		ent.movement_step = function(self, dtime, moveresult)
			orig_ms(self, dtime, moveresult)
			if self._tameful_id and self._jump_delay and self._jump_delay > tameful.RABBIT_HOP_DELAY then
				self._jump_delay = tameful.RABBIT_HOP_DELAY
			end
		end
	end

	-- targeting: our rule first; the species' own rules only act while it is not a pet
	local rules = { tameful.target_rule }
	for _, fn in ipairs(ent._targeting_rules or mob_class._targeting_rules or {}) do
		rules[#rules + 1] = function(self, ...)
			if self._tameful_id then return nil end
			return fn(self, ...)
		end
	end
	ent._targeting_rules = rules

	local orig_click = ent.on_rightclick
	ent.on_rightclick = function(self, clicker)
		if clicker and clicker:is_player() then
			local pname = clicker:get_player_name()
			local item = clicker:get_wielded_item()
			local iname = item:get_name()
			if iname == "tameful:lead" and not self.tamed and not self.child then
				pending[pname] = self.object
				core.show_formspec(pname, "tameful:tame", tame_formspec(tameful.kind_description(self.name), clicker))
				return
			end
			if self._tameful_id and self.owner == pname then
				if iname == "default:stick" or iname == "mcl_core:stick" then
					tameful.show_pet(pname, self)
					return
				end
				if item:is_empty() then
					if clicker:get_player_control().sneak or not needs_sneak(self) then
						tameful.toggle_order(self, pname)
						return
					end
				end
			end
		end
		if orig_click then return orig_click(self, clicker) end
	end

	-- Stale / orphaned copies disappear on activation.
	local orig_activate = ent.on_activate
	ent.on_activate = function(self, staticdata, dtime)
		local r = orig_activate(self, staticdata, dtime)
		if r == false then return r end
		local id = self._tameful_id
		if id then
			tameful.apply_stats(self, false)
			local rec = tameful.find_record(id)
			if not rec then
				if tameful.is_released(id) then self.object:remove(); return false end -- a stale copy of a released pet
				tameful.untame(self)
			elseif rec.status ~= "out" or (self._tameful_epoch or 0) ~= (rec.epoch or 0) then
				self.object:remove()
				return false
			end
		end
		return r
	end

	local orig_die = ent.on_die
	ent.on_die = function(self, pos, reason)
		local id = self._tameful_id
		if id then
			local rec, owner = tameful.find_record(id)
			if rec then
				if cfg.get("immortal") then
					tameful.stable(id, true, true)
					msg(owner, S("@1 was downed and is recovering in the stable.", rec.name))
					return true -- no death, no drops: Mineclonia removes this copy
				end
				roster[owner][id] = nil
				tameful.save()
				msg(owner, S("@1 has died.", rec.name))
			end
		end
		if orig_die then return orig_die(self, pos, reason) end
	end
end

core.register_on_mods_loaded(function()
	for name, def in pairs(mcl_mobs.registered_mobs) do
		if def.type == "animal" and not EXCLUDED[name] then
			wrap_mob(name)
		end
	end
end)

----------------------------------------------------------------------------------
-- Upkeep: positions/health of loaded pets, dimension change, downed recovery
----------------------------------------------------------------------------------
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 2 then return end
	timer = 0
	local seen = {}
	local to_stable = {}
	-- Animals tamed the vanilla way (wolves, cats, horses...) become Tameful pets.
	local adopt_list = {}
	for _, ent in pairs(core.luaentities) do
		if ent.tamed and ent.owner and ent.owner ~= "" and not ent._tameful_id and not ent.child and ent.is_mob
				and mcl_mobs.registered_mobs[ent.name] and mcl_mobs.registered_mobs[ent.name].type == "animal"
				and not EXCLUDED[ent.name] and ent._tameful_wrapped and ent.object and ent.object:get_pos() then
			adopt_list[#adopt_list + 1] = ent
		end
	end
	for _, ent in ipairs(adopt_list) do adopt(ent, ent.owner, true) end
	for _, ent in pairs(core.luaentities) do
		local id = ent._tameful_id
		if id and ent.object then
			local pos = ent.object:get_pos()
			if pos then
				-- regeneration: 1 health every 2 s (this loop's period), starting 10 s after the last damage
				local now = core.get_gametime()
				local hpmax = ent._tameful_stats and ent._tameful_stats.hp
				if hpmax and ent.health then
					if ent._tameful_last_hp and ent.health < ent._tameful_last_hp then ent._tameful_hurt_at = now end
					if cfg.get("regen_health") and ent.health > 0 and ent.health < hpmax and now - (ent._tameful_hurt_at or 0) >= 10 then
						ent.health = math.min(hpmax, ent.health + 1)
					end
					ent._tameful_last_hp = ent.health
				end
				local rec, owner = tameful.find_record(id)
				if rec and rec.status == "out" then
					tameful.refresh_tag(ent)
					rec.pos = pos
					rec.dim = mcl_worlds.pos_to_dimension(pos)
					rec.hp = ent.health
					rec.order = ent.order
					remember_look(rec, ent)
					seen[id] = true
					-- A following pet does not cross dimensions: it waits in the stable.
					local p = core.get_player_by_name(owner)
					if p and (ent.order or "") == "" and mcl_worlds.pos_to_dimension(p:get_pos()) ~= rec.dim then
						to_stable[#to_stable + 1] = id
					end
				end
			end
		end
	end
	for _, id in ipairs(to_stable) do
		local rec, owner = tameful.find_record(id)
		if tameful.stable(id, false) then
			msg(owner, S("@1 was sent to the stable (you changed dimension).", rec.name))
		end
	end
	local dirty = false
	for _, pets in pairs(roster) do
		for id, rec in pairs(pets) do
			local loaded = rec.status == "out" and (seen[id] or false)
			if rec.loaded ~= loaded then rec.loaded = loaded; dirty = true end
		end
	end
	if dirty then tameful.save() end
end)

-- Logging out: following pets wait in the stable (not resummoned on login). Staying pets stay where they are.
core.register_on_leaveplayer(function(player)
	local pname = player:get_player_name()
	pending[pname] = nil
	for id, rec in pairs(roster[pname] or {}) do
		if rec.status == "out" and rec.loaded and (rec.order or "") == "" then
			tameful.stable(id, false)
		end
	end
end)

-- Mob Crate: when a pet goes into a crate its last copy is saved in the roster, so the stable can still take it (and the crate's copy is deleted if released later).
if core.get_modpath("mobcrate") then
	mobcrate.register_on_crate(function(ent)
		local id = ent._tameful_id
		local rec = id and tameful.find_record(id)
		if not rec then return end
		local t = capture(ent, rec)
		if t then t.order = ""; t.dead = nil; rec.snapshot = core.serialize(t) end
		rec.loaded = false
		tameful.save()
	end)
end

tameful._wrap_ready = true
