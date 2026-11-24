-- Tameful leftovers (Fabric 1.0.3 behaviour): releasing pets (saddle + armor back, stabled/far pets appear next to you), a pet that
-- changes kind keeps being a pet (sheared mooshroom), wild cats/ocelots leave pets alone.
local S = core.get_translator("tameful")
local mob_class = mcl_mobs.mob_class
local roster = tameful.roster
local storage = tameful.storage

-- ---------------------------------------------------------------------------------------------------------------- released ids
-- A pet that was not loaded when released may still have a stale copy somewhere: such copies are removed when they load.
local released = core.deserialize(storage:get_string("released")) or {}
function tameful.is_released(id) return released[id] == true end
local function mark_released(id) released[id] = true; storage:set_string("released", core.serialize(released)) end

-- ---------------------------------------------------------------------------------------------------------------- gear
local function give(player, stack, pos)
	if stack:is_empty() then return end
	local left = player and player:get_inventory():add_item("main", stack) or stack
	if not left:is_empty() then core.add_item(pos, left) end
end

-- Takes the saddle (and horse armor) off an animal and hands it to the player (or drops it at pos).
function tameful.return_gear(ent, player)
	local pos = ent.object:get_pos()
	local out = {}
	if ent.remove_saddle and type(ent._saddle) == "string" and ent._saddle ~= "" then -- horse, donkey, mule, skeleton/zombie horse
		out[#out + 1] = ItemStack(ent._saddle)
		ent:remove_saddle()
		local armor = ItemStack(ent._horse_armor_stack or "")
		if not armor:is_empty() then out[#out + 1] = armor; ent:remove_armor(armor) end
	elseif ent.saddle == "yes" then -- pig, strider
		out[#out + 1] = ItemStack("mcl_mobitems:saddle")
		ent.saddle = "false"
		if ent.name == "mobs_mc:strider" then
			ent.base_texture = { "extra_mobs_strider.png", "blank.png" }
			ent:set_textures(ent:get_strider_textures())
		else
			ent.base_texture = { "mobs_mc_pig.png", "blank.png" }
			ent:set_textures(ent.base_texture)
		end
	end
	for _, st in ipairs(out) do give(player, st, pos) end
	return #out
end

-- ---------------------------------------------------------------------------------------------------------------- release
-- Lets a pet go: it becomes a normal animal (saddle and armor go to the owner). A pet in the stable or far away appears next to the owner.
function tameful.release(pname, id)
	local rec = roster[pname] and roster[pname][id]
	if not rec then return false end
	local player = core.get_player_by_name(pname)
	local ent = tameful.find_loaded(id)
	if not ent and rec.snapshot and player then
		local t = core.deserialize(rec.snapshot)
		if t then
			-- activate it as a full pet first (the activation check wants a matching record), then untame it below
			rec.epoch = (rec.epoch or 0) + 1
			rec.status, rec.ready_at, rec.loaded = "out", nil, true
			t.order = ""
			t._tameful_epoch = rec.epoch
			if rec.hp_max and (t.health or 0) <= 0 then t.health = rec.hp_max end
			local ppos, dir = player:get_pos(), player:get_look_dir()
			local pos = vector.new(ppos.x + dir.x * 2, ppos.y + 0.6, ppos.z + dir.z * 2)
			local n = core.get_node_or_nil(pos)
			if not n or not core.registered_nodes[n.name] or core.registered_nodes[n.name].walkable then pos = vector.offset(ppos, 0, 0.6, 0) end
			local obj = core.add_entity(pos, rec.kind, core.serialize(t))
			ent = obj and obj:get_luaentity()
		end
		mark_released(id)
	elseif not ent then
		mark_released(id)
	end
	if ent then
		tameful.return_gear(ent, player)
		tameful.untame(ent)
	end
	roster[pname][id] = nil
	tameful.save()
	return true
end

-- ---------------------------------------------------------------------------------------------------------------- kind changes
-- Mineclonia replaces an entity with a fresh one in a few cases (shearing a mooshroom turns it into a cow). A pet stays a pet through
-- that; when it turns into something that cannot be a pet it is released.
local orig_replace = mob_class.replace_with
function mob_class:replace_with(successor, propagate, sd)
	local id = self._tameful_id
	if id and self.tamed then
		local rec, owner = tameful.find_record(id)
		local def = core.registered_entities[successor]
		if rec and def and def.type == "animal" and not tameful.EXCLUDED[successor] then
			sd = table.copy(sd or {})
			sd.tamed, sd.owner, sd.order = true, self.owner, self.order
			sd._tameful_id, sd._tameful_epoch = id, self._tameful_epoch
			rec.kind = successor
			return orig_replace(self, successor, propagate, sd)
		elseif rec then
			if self.owner then roster[owner][id] = nil; tameful.save() end
			tameful.untame(self)
		end
	end
	return orig_replace(self, successor, propagate, sd)
end

-- ---------------------------------------------------------------------------------------------------------------- wild cats and ocelots
-- Wild cats and ocelots hunt chickens / rabbits; pets are left alone unless a pet hit them in the last 10 seconds.
local provoked = setmetatable({}, { __mode = "k" })
mcl_damage.register_on_damage(function(obj, damage, reason)
	if damage <= 0 or obj:is_player() then return end
	local ent = obj:get_luaentity()
	local src = reason and reason.source
	local se = src and not src:is_player() and src:get_luaentity()
	if ent and se and se._tameful_id and (ent.name == "mobs_mc:ocelot" or ent.name == "mobs_mc:cat") then provoked[ent] = core.get_gametime() end
end)
local orig_valid = mob_class.is_valid_target
function mob_class:is_valid_target(obj)
	if not orig_valid(self, obj) then return false end
	if (self.name == "mobs_mc:ocelot" or self.name == "mobs_mc:cat") and not self.tamed then
		local e = obj:get_luaentity()
		if e and e._tameful_id and not (provoked[self] and core.get_gametime() - provoked[self] <= 10) then return false end
	end
	return true
end
