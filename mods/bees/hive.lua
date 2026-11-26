-- Hive data layer (step 2a). The hive node is the single source of truth for how many bees are INSIDE it (node meta "bees:count").
-- Bees outside are ordinary mobs and are not counted. Two kinds of hive exist in Mineclonia (mcl_beehives), both with levels 0-5 as node names:
--   "beehive"  (group beehive)  crafted / placed by players: starts EMPTY.
--   "nest"     (group bee_nest) natural, grown on trees:     starts with 1-3 bees the first time it is seen.
-- Rules: entering = count+1 and the entity is removed; leaving = count-1 and the entity is created. Never both, never twice.
local S = core.get_translator("bees")

bees = bees or {}
bees.HIVE_MAX = 5

-- Hive sounds: our own files mods/bees/sounds/bees_hive_in.ogg / bees_hive_out.ogg (a bee going in / coming out). Tune gain/pitch here.
local SND = {
	leave = { { "bees_hive_out", 0.8, 1.0 } },
	enter = { { "bees_hive_in", 0.8, 1.0 } },
}
local function hive_sound(kind, pos)
	for _, s in ipairs(SND[kind]) do
		core.sound_play(s[1], { pos = pos, gain = s[2], pitch = s[3], max_hear_distance = 12 }, true)
	end
end
local HIVE_GROUPS = { "group:beehive", "group:bee_nest" }
bees.HIVE_GROUPS = HIVE_GROUPS

-- Bees work in daylight and stay in during rain (same hours as Mineclonia's own honey ABM).
function bees.is_active_time()
	local t = core.get_timeofday() * 24000
	if t <= 6000 or t >= 18000 then return false end
	return not (mcl_weather and mcl_weather.get_weather() ~= "none")
end

function bees.hive_kind(pos)
	local name = core.get_node(pos).name
	if core.get_item_group(name, "beehive") > 0 then return "beehive" end
	if core.get_item_group(name, "bee_nest") > 0 then return "nest" end
end

local function update_infotext(pos, meta)
	meta = meta or core.get_meta(pos)
	meta:set_string("infotext", S("Bees: @1/@2", meta:get_int("bees:count"), bees.HIVE_MAX))
end

-- First sight of a hive: set its starting population once. Returns the count.
function bees.hive_init(pos)
	local kind = bees.hive_kind(pos)
	if not kind then return nil end
	local meta = core.get_meta(pos)
	if meta:get_int("bees:init") == 0 then
		meta:set_int("bees:init", 1)
		meta:set_int("bees:count", kind == "nest" and math.random(1, 3) or 0)
		update_infotext(pos, meta)
	end
	return meta:get_int("bees:count")
end

function bees.hive_count(pos)
	if not bees.hive_kind(pos) then return nil end
	return bees.hive_init(pos)
end

-- +1 bee inside; false if full or not a hive.
function bees.hive_add(pos)
	local n = bees.hive_count(pos)
	if not n or n >= bees.HIVE_MAX then return false end
	local meta = core.get_meta(pos)
	meta:set_int("bees:count", n + 1)
	update_infotext(pos, meta)
	return true
end

-- -1 bee inside; false if empty or not a hive.
function bees.hive_take(pos)
	local n = bees.hive_count(pos)
	if not n or n <= 0 then return false end
	local meta = core.get_meta(pos)
	meta:set_int("bees:count", n - 1)
	update_infotext(pos, meta)
	return true
end

local DIRS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 }, { 0, -1, 0 } }
local function free_spot(pos)
	local order = {}
	for i = 1, #DIRS do order[i] = DIRS[i] end
	for i = #order, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
	for _, d in ipairs(order) do
		local p = vector.offset(pos, d[1], d[2], d[3])
		local def = core.registered_nodes[core.get_node(p).name]
		if def and def.walkable == false and (def.groups.liquid or 0) == 0 then return p end
	end
end

-- The free air node next to a hive that is closest to `from`; a homing bee flies to it and goes in from there. nil if the hive is walled in.
function bees.hive_entrance(pos, from)
	local best, bd
	for _, d in ipairs(DIRS) do
		local p = vector.offset(pos, d[1], d[2], d[3])
		local def = core.registered_nodes[core.get_node(p).name]
		if def and def.walkable == false and (def.groups.liquid or 0) == 0 then
			local dist = vector.distance(p, from)
			if not bd or dist < bd then best, bd = p, dist end
		end
	end
	return best
end

-- Nearest hive with room within `r` nodes (sideways) / 12 (up-down) of pos, or nil.
-- `skip`: table of hive hashes to ignore until a game time (hives a bee gave up on).
function bees.find_home(pos, r, skip)
	local now = core.get_gametime()
	local list = core.find_nodes_in_area(vector.offset(pos, -r, -12, -r), vector.offset(pos, r, 12, r), HIVE_GROUPS)
	local best, bd
	for _, p in ipairs(list) do
		local d = vector.distance(p, pos)
		local skipped = skip and skip[core.hash_node_position(p)] and skip[core.hash_node_position(p)] > now
		if not skipped and (not bd or d < bd) and (bees.hive_count(p) or bees.HIVE_MAX) < bees.HIVE_MAX then best, bd = p, d end
	end
	return best
end

-- A bee goes in: the entity is removed and the count rises, in this one call. Returns true if it went in.
function bees.enter_hive(obj, pos)
	local le = obj and obj:get_luaentity()
	if not le or le.name ~= "bees:bee" or le._entered or le.tamed then return false end -- tamed bees ignore hives
	if not bees.hive_add(pos) then return false end
	le._entered = true
	-- the hive rests: nobody leaves for 2 minutes after a bee came in
	local meta = core.get_meta(pos)
	meta:set_int("bees:next_out", math.max(meta:get_int("bees:next_out"), core.get_gametime() + 120))
	hive_sound("enter", pos)
	obj:remove()
	return true
end

-- A bee comes out: the count drops and a bee entity is created. Returns the new object, or nil (count restored if it could not be placed).
function bees.leave_hive(pos)
	if not bees.hive_take(pos) then return nil end
	local spot = free_spot(pos)
	local obj = spot and core.add_entity(spot, "bees:bee")
	if not obj then bees.hive_add(pos); return nil end
	hive_sound("leave", spot)
	local le = obj:get_luaentity()
	if le then
		le._hive = vector.copy(pos)
		le._out_since = core.get_gametime()
		le._forage_for = math.random(180, 360) -- seconds out before it heads home by itself
	end
	return obj
end

-- Bees come out on their own: daytime, no rain, a flower within 16 nodes, one at a time (8-20 s apart), and not for 2 minutes after one went in.
core.register_abm({
	label = "Bees leave their hive",
	nodenames = HIVE_GROUPS,
	interval = 10, chance = 1,
	action = function(pos)
		local n = bees.hive_count(pos)
		if not n or n == 0 or not bees.is_active_time() then return end
		local meta, now = core.get_meta(pos), core.get_gametime()
		if now < meta:get_int("bees:next_out") then return end
		if not core.find_node_near(pos, 16, "group:flower") then return end
		if bees.leave_hive(pos) then meta:set_int("bees:next_out", now + math.random(8, 20)) end
	end,
})

-- Natural nests (and any hive set by the mapgen or tree growth) get their population when first loaded.
core.register_lbm({
	label = "Set starting bees in hives",
	name = "bees:init_hives",
	nodenames = HIVE_GROUPS,
	run_at_every_load = true, -- cheap: a meta read; handles hives that appear later (tree growth, mapgen of new areas)
	action = function(pos) bees.hive_init(pos) end,
})

-- A hive placed by a player starts empty (it must not roll a natural nest's 1-3 bees). Item meta "bees:count" is for step 2c (silk touch).
core.register_on_placenode(function(pos, newnode, _, _, itemstack)
	if not bees.hive_kind(pos) then return end
	local meta = core.get_meta(pos)
	meta:set_int("bees:init", 1)
	local carried = itemstack and itemstack:get_meta():get_int("bees:count") or 0
	meta:set_int("bees:count", math.min(carried, bees.HIVE_MAX))
	update_infotext(pos, meta)
end)

-- Debug commands (server priv) to try it by hand.
local function nearest_hive(player, r)
	return core.find_node_near(player:get_pos(), r, HIVE_GROUPS, true)
end
core.register_chatcommand("bees_hive", {
	params = "", description = "Show the hive nearest to you (within 8 nodes)", privs = { server = true },
	func = function(name)
		local p = core.get_player_by_name(name); if not p then return end
		local pos = nearest_hive(p, 8)
		if not pos then return true, "No hive within 8 nodes." end
		return true, string.format("%s at %s: %d/%d bees inside, node %s", bees.hive_kind(pos), core.pos_to_string(pos), bees.hive_count(pos), bees.HIVE_MAX, core.get_node(pos).name)
	end,
})
core.register_chatcommand("bees_out", {
	params = "", description = "Let one bee out of the nearest hive", privs = { server = true },
	func = function(name)
		local p = core.get_player_by_name(name); if not p then return end
		local pos = nearest_hive(p, 8)
		if not pos then return true, "No hive within 8 nodes." end
		local o = bees.leave_hive(pos)
		return true, (o and "A bee came out. " or "The hive is empty. ") .. "Now " .. bees.hive_count(pos) .. "/" .. bees.HIVE_MAX .. " inside."
	end,
})
core.register_chatcommand("bees_in", {
	params = "", description = "Make the nearest bee (within 12 nodes) go into the nearest hive", privs = { server = true },
	func = function(name)
		local p = core.get_player_by_name(name); if not p then return end
		local pos = nearest_hive(p, 12)
		if not pos then return true, "No hive within 12 nodes." end
		local best, bd
		for _, o in ipairs(core.get_objects_inside_radius(p:get_pos(), 12)) do
			local le = o:get_luaentity()
			if le and le.name == "bees:bee" then
				local d = vector.distance(o:get_pos(), pos)
				if not bd or d < bd then best, bd = o, d end
			end
		end
		if not best then return true, "No bee within 12 nodes." end
		local ok = bees.enter_hive(best, pos)
		return true, (ok and "A bee went in. " or "It could not go in (full or tamed). ") .. bees.hive_count(pos) .. "/" .. bees.HIVE_MAX .. " inside."
	end,
})

-- Breaking and harvesting (step 2c). Mineclonia's own handlers (mcl_beehives dig_hive / honey_harvest) deal a flat 10 "sting" damage because bees did not exist.
-- We replace the break handler and wrap the harvest one: the damage is swallowed and the bees themselves come out angry (unless a lit campfire is within 5 nodes below).
-- Drops are the same as upstream: beehive -> beehive item (silk touch: the node, with honey level), nest -> nothing (silk touch: the node). With silk touch the bees stay
-- in the item (item meta "bees:count", restored in register_on_placenode above).
local function dig_hive(pos, oldnode, oldmeta, digger)
	if not digger or not digger:is_player() then return end
	local name = digger:get_player_name()
	local creative = core.is_creative_enabled(name)
	local count = tonumber(oldmeta and oldmeta.fields and oldmeta.fields["bees:count"]) or 0
	local is_nest = core.get_item_group(oldnode.name, "bee_nest") > 0
	local silk = mcl_enchanting.has_enchantment(digger:get_wielded_item(), "silk_touch")
	local inv = digger:get_inventory()
	local base = is_nest and "mcl_beehives:bee_nest" or "mcl_beehives:beehive"
	if creative then
		if inv:room_for_item("main", base) and not inv:contains_item("main", base) then inv:add_item("main", base) end
	elseif silk then
		local stack = ItemStack(oldnode.name)
		stack:get_meta():set_int("bees:count", math.min(count, bees.HIVE_MAX))
		core.add_item(pos, stack)
		if is_nest then awards.unlock(name, "mcl:total_beelocation") end
		return -- the bees travel in the item
	elseif not is_nest then
		core.add_item(pos, base)
	end
	-- bees come out; angry unless smoke is calming them (creative players are never targeted)
	bees.release_all(pos, (not bees.calmed_by_smoke(pos)) and digger or nil, count)
end
bees.dig_hive = dig_hive

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_nodes) do
		if core.get_item_group(name, "beehive") > 0 or core.get_item_group(name, "bee_nest") > 0 then
			local orig = def.on_rightclick
			core.override_item(name, {
				after_dig_node = dig_hive,
				on_rightclick = orig and function(pos, node, player, itemstack, pointed)
					local stung = false
					local od = mcl_util.deal_damage
					mcl_util.deal_damage = function(t, d, r)
						if r and r.type == "sting" then stung = true; return 0 end
						return od(t, d, r)
					end
					local ok, ret = pcall(orig, pos, node, player, itemstack, pointed)
					mcl_util.deal_damage = od
					if not ok then error(ret) end
					if stung then bees.release_all(pos, player) end -- no smoke: all bees out, angry
					return ret
				end or nil,
			})
		end
	end
end)

-- /bees_why: stand next to a bee that does something odd and run it. Prints the nearest bee's state and what its hive looks like.
core.register_chatcommand("bees_why", {
	params = "", description = "Explain the nearest bee (within 12 nodes): hive, homing state, entrance, anger", privs = { server = true },
	func = function(name)
		local p = core.get_player_by_name(name); if not p then return end
		local pp = p:get_pos()
		local best, bd
		for _, o in ipairs(core.get_objects_inside_radius(pp, 12)) do
			local le = o:get_luaentity()
			if le and le.name == "bees:bee" then
				local d = vector.distance(o:get_pos(), pp)
				if not bd or d < bd then best, bd = le, d end
			end
		end
		if not best then return true, "No bee within 12 nodes." end
		local pos, now = best.object:get_pos(), core.get_gametime()
		local L = {}
		local function add(s) L[#L + 1] = s end
		add(string.format("Bee at %s. active_time=%s tamed=%s angry=%s", core.pos_to_string(pos, 1), tostring(bees.is_active_time()), tostring(best.tamed), tostring(best._angry_until and (best._angry_until - now) .. "s left")))
		add(string.format("activity=%s heading_home=%s tries=%s backtracking=%s navigating=%s", tostring(best._active_activity), tostring(best.heading_home), tostring(best._home_tries), tostring(best._backtrack ~= nil), tostring(best:is_navigating())))
		local av = {}
		for h, t in pairs(best._avoid or {}) do if t > now then av[#av + 1] = core.pos_to_string(core.get_position_from_hash(h)) .. " " .. (t - now) .. "s" end end
		add("avoiding (gave up): " .. (#av > 0 and table.concat(av, ", ") or "none"))
		local hv = best._hive
		if not hv then
			add("NO HIVE: homeless. Nearest hive with room within " .. (bees.LEASH or 22) .. " nodes: " .. tostring(bees.find_home(pos, bees.LEASH or 22) and core.pos_to_string(bees.find_home(pos, bees.LEASH or 22)) or "none"))
		else
			add(string.format("Hive %s %s (%s) %d/%d inside, bee is %.1f nodes away (must be <= 1.25 to go in)", bees.hive_kind(hv) or "MISSING", core.pos_to_string(hv), core.get_node(hv).name, bees.hive_count(hv) or -1, bees.HIVE_MAX, vector.distance(pos, hv)))
			local ent = bees.hive_entrance(hv, pos)
			add("entrance node: " .. (ent and core.pos_to_string(ent) or "NONE (hive is walled in)"))
			local sides = {}
			for _, d in ipairs({ {1,0,0}, {-1,0,0}, {0,0,1}, {0,0,-1}, {0,1,0}, {0,-1,0} }) do
				sides[#sides + 1] = core.get_node(vector.offset(hv, d[1], d[2], d[3])).name:gsub("^.-:", "")
			end
			add("hive neighbours (+x -x +z -z +y -y): " .. table.concat(sides, ", "))
			add("line of sight bee -> entrance: " .. tostring(ent and core.line_of_sight(pos, ent)))
		end
		return true, table.concat(L, "\n")
	end,
})
