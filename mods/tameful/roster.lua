-- Roster: every pet of every owner. roster[owner][id] = record
--   id, kind (entity name), name, status ("out" | "stabled" | "downed"), ready_at (gametime, downed),
--   snapshot (serialized staticdata of the last copy), epoch (retires stale copies), pos, dim, loaded, hp, hp_max, order
local storage = tameful.storage
local roster = core.deserialize(storage:get_string("roster")) or {}
local next_id = storage:get_int("next_id")
if next_id < 1 then next_id = 1 end

tameful.roster = roster

function tameful.save()
	storage:set_string("roster", core.serialize(roster))
	storage:set_int("next_id", next_id)
end

function tameful.new_id()
	local id = next_id
	next_id = next_id + 1
	return id
end

function tameful.find_record(id)
	for owner, pets in pairs(roster) do
		if pets[id] then return pets[id], owner end
	end
end

function tameful.owner_count(owner)
	local n = 0
	for _ in pairs(roster[owner] or {}) do n = n + 1 end
	return n
end

-- Pets of this owner that are out in the world (loaded or not).
function tameful.out_count(owner)
	local n = 0
	for _, rec in pairs(roster[owner] or {}) do
		if rec.status == "out" then n = n + 1 end
	end
	return n
end

function tameful.sorted_ids(owner)
	local ids = {}
	for id in pairs(roster[owner] or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

function tameful.find_loaded(id)
	for _, ent in pairs(core.luaentities) do
		if ent._tameful_id == id and ent.object and ent.object:get_pos() then
			return ent
		end
	end
end

function tameful.kind_description(kind)
	local def = mcl_mobs.registered_mobs[kind]
	return def and def.description or kind
end

function tameful.msg(pname, text)
	core.chat_send_player(pname, core.colorize("#7fd37f", "[Tameful] ") .. text)
end

function tameful.untame(ent)
	if ent.driver and ent.driver:is_valid() then ent:detach(ent.driver, vector.new(0, 0.5, 0)) end
	if ent._tameful_riding then tameful._ride_cleanup(ent) end
	ent.tamed = false
	ent.owner = nil
	ent.order = ""
	ent._tameful_id = nil
	ent._tameful_epoch = nil
	if ent._tameful_orig_speed then ent.movement_speed = ent._tameful_orig_speed; ent._tameful_orig_speed = nil end
	if ent._tameful_orig_pace then ent.pace_bonus = ent._tameful_orig_pace; ent._tameful_orig_pace = nil end
	if ent._tameful_orig_ign ~= nil then ent.ignores_nametag = ent._tameful_orig_ign or nil; ent._tameful_orig_ign = nil end
	if ent._tameful_orig_floats ~= nil then ent.floats = ent._tameful_orig_floats; ent._tameful_orig_floats = nil end
	ent._tameful_stats = nil
	ent._tameful_attitude, ent._tameful_range, ent._tameful_wander, ent._tameful_home = nil, nil, nil, nil
	ent._active_target = nil; ent.attack = nil
	if ent._tameful_set_melee then ent.attack_type = nil; ent._tameful_set_melee = nil end
	ent.custom_attack = nil -- back to the class method
	ent.nametag = ""
	if ent.update_tag then ent:update_tag() end
end

-- Text above a pet: name / health / owner, each line by its setting; "" = no tag at all.
function tameful.display_name(rec, owner, ent)
	local lines = {}
	if tameful.cfg.get("show_name") then lines[#lines + 1] = rec.name end
	if tameful.cfg.get("show_health") then
		local hp = ent and ent.health or rec.hp
		local mx = (ent and ent._tameful_stats and ent._tameful_stats.hp) or rec.hp_max
		if hp and mx then lines[#lines + 1] = string.format("\u{2764} %d/%d", math.floor(hp + 0.5), mx) end
	end
	if tameful.cfg.get("show_owner") then lines[#lines + 1] = "Owner: " .. owner end
	return table.concat(lines, "\n")
end

-- Bring a loaded pet's tag up to date (only touches it when the text changed).
function tameful.refresh_tag(ent)
	local rec, owner = tameful.find_record(ent._tameful_id)
	if not rec then return end
	local text = tameful.display_name(rec, owner, ent)
	if (ent.nametag or "") ~= text then
		-- (not set_nametag: it truncates to max_name_length, which would cut the extra lines)
		ent.nametag = text
		if ent.update_tag then ent:update_tag() end
	end
end
