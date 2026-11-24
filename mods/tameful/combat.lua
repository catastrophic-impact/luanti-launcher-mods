-- Attitude combat + Relax mode.
--   Attitude: passive (never fights) | defensive (fights whoever hurts the owner or the pet, and what the owner attacks)
--             | aggressive (also mobs that are after the owner or the pet, except creepers, within `range`).
--   Pets give up a target >14 blocks away or after 10 quiet seconds. They never pick fights on their own.
local S = core.get_translator("tameful")
local mob_class = mcl_mobs.mob_class
local roster = tameful.roster

tameful.ATTITUDES = { "passive", "defensive", "aggressive" }
tameful.RANGES = { 8, 16, 24 }
tameful.WANDERS = { 6, 12, 24 }
local GIVE_UP_DIST, GIVE_UP_TIME, MEMORY = 14, 10, 10
local NEVER = { ["mobs_mc:creeper"] = true, ["mobs_mc:creeper_charged"] = true, ["mobs_mc:ghast"] = true }

-- Who hurt whom / who hit what, recently (not persisted).
local owner_hurt = {}   -- owner_hurt[owner] = { source = obj, t = gametime }
local owner_hit = {}    -- owner_hit[owner] = { target = obj, t = gametime }
local pet_hurt = {}     -- pet_hurt[luaentity] = { source = obj, t }

mcl_damage.register_on_damage(function(obj, damage, reason)
	if damage <= 0 then return end
	local now = core.get_gametime()
	local src = reason and reason.source
	if obj:is_player() then
		if src and src ~= obj then owner_hurt[obj:get_player_name()] = { source = src, t = now } end
		return
	end
	local ent = obj:get_luaentity()
	if ent and ent._tameful_id and src and src ~= obj then
		pet_hurt[ent] = { source = src, t = now }
		ent._tameful_engaged_at = now
	end
	if src and src:is_player() and not (ent and ent.owner == src:get_player_name()) then
		owner_hit[src:get_player_name()] = { target = obj, t = now }
	end
end)

local function is_ally(ent, obj)
	if obj:is_player() then return obj:get_player_name() == ent.owner end
	local e = obj:get_luaentity()
	if not e then return true end
	if e == ent then return true end
	return e.owner == ent.owner and e.tamed
end

local function valid_target(ent, obj, aggressive_scan)
	if not obj or not obj:is_valid() or is_ally(ent, obj) then return false end
	local e = obj:get_luaentity()
	if obj:is_player() then
		return core.settings:get_bool("enable_pvp", true) and not core.is_creative_enabled(obj:get_player_name())
	end
	if not e or not e.is_mob or e.dead then return false end
	if NEVER[e.name] then return false end
	if e.tamed and not aggressive_scan then return true end -- someone else's pet that attacked us: allowed when it is the assailant
	return not e.tamed
end

tameful._valid_target = valid_target
tameful._pet_hurt = pet_hurt

local function find_target(ent, self_pos, owner, att)
	local now = core.get_gametime()
	local function recent(rec) return rec and now - rec.t <= MEMORY end
	local mine = pet_hurt[ent]
	if recent(mine) and valid_target(ent, mine.source) then return mine.source end
	if att == "passive" then return nil end
	local oh = owner_hurt[ent.owner]
	if recent(oh) and valid_target(ent, oh.source) then return oh.source end
	local ot = owner_hit[ent.owner]
	if recent(ot) and valid_target(ent, ot.target) then return ot.target end
	if att == "aggressive" and owner then
		local range = ent._tameful_range or 16
		local best, bd = nil, 1e9
		for _, o in ipairs(core.get_objects_inside_radius(self_pos, range)) do
			local e = o:get_luaentity()
			if e and e.is_mob and not e.tamed and e.attack and e.attack:is_valid() then
				local aimed = e.attack == owner
				if not aimed then
					local ae = e.attack:get_luaentity()
					aimed = ae and ae.tamed and ae.owner == ent.owner
				end
				if aimed and valid_target(ent, o, true) then
					local d = vector.distance(self_pos, o:get_pos())
					if d < bd then best, bd = o, d end
				end
			end
		end
		return best
	end
	return nil
end

-- Targeting rule (Mineclonia re-runs its rules every step and clears _active_target first, so the pet's choice must come from a rule).
-- Wrapped into every tameable animal by pets.lua; the species' own rules (a wolf hunting sheep...) are muted while it is a pet.
function tameful.target_rule(self, self_pos, dtime, obj, is_current)
	if not self._tameful_id or self.object:get_attach() then return nil end
	local att = self._tameful_attitude or "defensive"
	if att == "passive" or self.order == "sit" then return nil end
	local now = core.get_gametime()
	if obj and is_current and obj:is_valid() then
		if vector.distance(self_pos, obj:get_pos()) > GIVE_UP_DIST
				or now - (self._tameful_engaged_at or now) > GIVE_UP_TIME then
			self._tameful_ignore_until = now + 2
			return nil
		end
		return obj
	end
	if now < (self._tameful_ignore_until or 0) then return nil end
	if self:check_timer("tameful_scan", 0.5) then
		local owner = self.owner and core.get_player_by_name(self.owner)
		local t = find_target(self, self_pos, owner, att)
		if t then self._tameful_engaged_at = now end
		return t
	end
	return nil
end

-- Relax: stay around the home spot.
local function relax_home(self, self_pos, dtime)
	if self.order ~= "relax" or not self._tameful_home then return false end
	local h = self._tameful_home
	local wander = self._tameful_wander or 12
	local d = vector.distance(self_pos, vector.new(h.x, h.y, h.z))
	if d > wander then
		if self:check_timer("tameful_home_path", 1.0) then self:gopath(vector.new(h.x, h.y, h.z), 1.0, nil, 2) end
		return "tameful_home"
	end
	return false
end
tameful.relax_home = relax_home

function tameful.set_attitude(ent, att)
	ent._tameful_attitude = att
	if att == "passive" then ent._active_target = nil; ent.attack = nil end
end

local function cycle(list, cur, default)
	local i = 1
	for k, v in ipairs(list) do if v == (cur or default) then i = k end end
	return list[i % #list + 1]
end
tameful.cycle = cycle

-- Modes: "follow" | "stay" | "relax"
function tameful.set_mode(ent, mode)
	local pname = ent.owner
	if mode == "stay" then
		ent:stay()
	elseif mode == "relax" then
		ent.order = "relax"
		local p = ent.object:get_pos()
		ent._tameful_home = { x = p.x, y = p.y, z = p.z }
	else
		ent.order = ""
		ent._tameful_home = nil
	end
	local rec = tameful.find_record(ent._tameful_id)
	if rec then rec.order = ent.order; tameful.save() end
end

function tameful.mode_of(order)
	return order == "sit" and "stay" or order == "relax" and "relax" or "follow"
end
function tameful.mode_label(order)
	local m = tameful.mode_of(order)
	return m == "stay" and S("Staying") or m == "relax" and S("Relaxing") or S("Following")
end
