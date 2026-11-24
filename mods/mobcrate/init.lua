-- Mob Crate (Luanti/Mineclonia port of the Fabric Mob Crate; original Luanti mod by Twinsonian).
-- Right-click (or left-click) a mob with an empty crate: it goes into the crate with ALL its state (the mob's staticdata: name, health, owner,
-- saddle/armor, villager job/trades, age, data of other mods such as Tameful and Populations). Right-click a block with a full crate: the same mob comes out.
local S = core.get_translator("mobcrate")
local esc = core.formspec_escape
local storage = core.get_mod_storage()
mobcrate = { on_crate = {}, on_release = {} }

----------------------------------------------------------------------------------------------------------------------
-- Settings (mod storage; the Fabric version edits a file, here /mobcrate does it)
----------------------------------------------------------------------------------------------------------------------
local BOSSES = {
	["mobs_mc:enderdragon"] = true, ["mobs_mc:dragon_piece"] = true, ["mobs_mc:wither"] = true,
	["mobs_mc:guardian_elder"] = true, ["mobs_mc:elder_guardian"] = true, ["mobs_mc:warden"] = true,
}
local function setting_bool(key) return storage:get_string(key) == "true" end
local function blacklist()
	local t = {}
	for id in storage:get_string("blacklist"):gmatch("[^,%s]+") do t[id] = true end
	return t
end
mobcrate.blacklist = blacklist

function mobcrate.register_on_crate(fn) mobcrate.on_crate[#mobcrate.on_crate + 1] = fn end
function mobcrate.register_on_release(fn) mobcrate.on_release[#mobcrate.on_release + 1] = fn end

----------------------------------------------------------------------------------------------------------------------
-- Rules
----------------------------------------------------------------------------------------------------------------------
local function is_mob_entity(ent)
	if not ent then return false end
	if ent.is_mob then return true end
	local def = core.registered_entities[ent.name or ""]
	return (def and (def._mobcrate_ok or def.type == "animal" or def.type == "monster" or def.type == "npc")) or false
end

-- Returns true, or false + reason (already translated).
function mobcrate.can_capture(player, obj)
	if not obj or not obj:is_valid() then return false, S("There is nothing there.") end
	if obj:is_player() then return false, S("Players cannot be put in a crate.") end
	local ent = obj:get_luaentity()
	if not ent or not ent.name then return false, S("That cannot be put in a crate.") end
	if not is_mob_entity(ent) then return false, S("That cannot be put in a crate.") end
	if ent.dead or ent.removed or (ent.health and ent.health <= 0) then return false, S("It is not in a state to be moved.") end
	if blacklist()[ent.name] then return false, S("This mob cannot be put in a crate.") end
	if BOSSES[ent.name] and not setting_bool("allow_bosses") then return false, S("Bosses cannot be put in a crate.") end
	local name = player:get_player_name()
	if ent.tamed and ent.owner and ent.owner ~= "" and ent.owner ~= name and not setting_bool("allow_other_players_pets") then
		return false, S("That is another player's pet.")
	end
	-- jockeys: a mob riding another mob, or carrying one, would be left in a broken state
	if obj:get_attach() and not (obj:get_attach():is_player()) then return false, S("Get it off its mount first.") end
	for _, child in ipairs(obj:get_children()) do
		if not child:is_player() then return false, S("Something is riding it. Get it off first.") end
	end -- (a rider that is a player is lifted off when it goes in: see try_capture)
	local pos = obj:get_pos()
	if core.is_protected(pos, name) and not core.check_player_privs(name, { protection_bypass = true }) then
		core.record_protection_violation(pos, name)
		return false, S("This area is protected.")
	end
	return true
end

----------------------------------------------------------------------------------------------------------------------
-- Items
----------------------------------------------------------------------------------------------------------------------
local function plain(s) return (tostring(s or ""):gsub("\n.*$", "")) end

local function kind_desc(ent)
	local def = mcl_mobs.registered_mobs and mcl_mobs.registered_mobs[ent.name]
	return (def and def.description) or ent.name
end

local function describe(ent, obj)
	local kind = kind_desc(ent)
	local tag = plain(ent.nametag)
	local who = (tag ~= "" and tag ~= kind) and (tag .. " (" .. kind .. ")") or kind
	local lines = { S("Mob Crate"), S("Contains: @1", who) }
	local hp = ent.health
	local props = obj:get_properties()
	local mx = props and props.hp_max
	if hp and mx then lines[#lines + 1] = S("Health: @1/@2", math.floor(hp + 0.5), mx) end
	return table.concat(lines, "\n")
end

core.register_craftitem("mobcrate:crate_empty", {
	description = S("Mob Crate"),
	_doc_items_longdesc = S("Right-click a mob to put it in the crate, then right-click a block to let it out."),
	inventory_image = "crate_empty.png",
	stack_max = 16,
	tool_capabilities = { full_punch_interval = 1.0, damage_groups = { fleshy = 0 } }, -- a left-click must never hurt the mob
	-- left-click also crates (the original Luanti behaviour) instead of hurting the mob
	on_use = function(itemstack, user, pointed_thing)
		if pointed_thing.type == "object" then mobcrate.try_capture(user, pointed_thing.ref) end
		return nil -- try_capture changes the wielded stack itself
	end,
})

core.register_craftitem("mobcrate:crate_full", {
	description = S("Full Mob Crate"),
	inventory_image = "crate_full.png",
	stack_max = 1,
	tool_capabilities = { full_punch_interval = 1.0, damage_groups = { fleshy = 0 } },
	groups = { not_in_creative_inventory = 1 },
	on_use = function() return nil end, -- no punching with a full crate
	on_place = function(itemstack, placer, pointed_thing)
		if not placer or not placer:is_player() then return itemstack end
		local rc = mcl_util.call_on_rightclick(itemstack, placer, pointed_thing)
		if rc then return rc end
		if pointed_thing.type ~= "node" then return itemstack end
		return mobcrate.release(itemstack, placer, pointed_thing)
	end,
})

core.register_craft({
	output = "mobcrate:crate_empty",
	recipe = { { "group:wood", "group:wood", "group:wood" }, { "group:wood", "group:wood", "group:wood" }, { "group:wood", "group:wood", "group:wood" } },
})

----------------------------------------------------------------------------------------------------------------------
-- Capture
----------------------------------------------------------------------------------------------------------------------
local function say(player, text) core.chat_send_player(player:get_player_name(), core.colorize("#9cf", "[Mob Crate] ") .. text) end

-- Put `obj` into a crate taken from the player's wielded stack. Returns true on success.
function mobcrate.try_capture(player, obj)
	local wielded = player:get_wielded_item()
	if wielded:get_name() ~= "mobcrate:crate_empty" then return false end
	local ok, why = mobcrate.can_capture(player, obj)
	if not ok then say(player, why); return false end
	local ent = obj:get_luaentity()
	local data = ent.get_staticdata and ent:get_staticdata()
	if type(data) ~= "string" or data == "" then say(player, S("That cannot be put in a crate.")); return false end

	local full = ItemStack("mobcrate:crate_full")
	local meta = full:get_meta()
	meta:set_string("mob", ent.name)
	meta:set_string("data", data)
	meta:set_string("description", describe(ent, obj))
	meta:set_string("mobname", ent.name) -- the original mod's field name, kept for crates made with it
	local props = obj:get_properties()
	if props and props.collisionbox then meta:set_string("cbox", core.serialize(props.collisionbox)) end -- to check the room needed on release

	-- anyone riding it gets off first
	for _, child in ipairs(obj:get_children()) do
		if child:is_player() then
			if ent.detach then ent:detach(child, vector.new(0, 0.5, 0)) else child:set_detach() end
		end
	end
	for _, fn in ipairs(mobcrate.on_crate) do fn(ent, player) end -- (Tameful saves the pet's last copy here)
	-- Take one empty crate and give the full one; the mob is removed only after the crate is in the player's hands (or on the ground).
	wielded:take_item(1)
	if wielded:is_empty() then
		player:set_wielded_item(full) -- the stack of one: the full crate takes its place
	else
		player:set_wielded_item(wielded)
		local left = player:get_inventory():add_item("main", full)
		if not left:is_empty() then core.add_item(vector.offset(player:get_pos(), 0, 0.5, 0), left) end -- inventory full: it lands at your feet
	end
	if obj:is_valid() then obj:remove() end
	return true
end

----------------------------------------------------------------------------------------------------------------------
-- Release
----------------------------------------------------------------------------------------------------------------------
local function free_spot(pos, height)
	-- a node column the mob fits in: not walkable and not liquid-harmful for `height` nodes
	for dy = 0, math.max(0, math.ceil(height) - 1) do
		local n = core.get_node_or_nil(vector.offset(pos, 0, dy, 0))
		if not n then return false end
		local def = core.registered_nodes[n.name]
		if not def or def.walkable then return false end
		if (def.damage_per_second or 0) > 0 then return false end
	end
	return true
end

function mobcrate.release(itemstack, placer, pointed_thing)
	local meta = itemstack:get_meta()
	local mob = meta:get_string("mob")
	if mob == "" then mob = meta:get_string("mobname") end
	if mob == "" then return itemstack end
	local data = meta:get_string("data")
	if not core.registered_entities[mob] then
		say(placer, S("This mob (@1) is not available in this world.", mob))
		return itemstack
	end
	-- where: in place of a replaceable block (grass...), else on that side of the block
	local under = core.get_node(pointed_thing.under)
	local udef = core.registered_nodes[under.name]
	local spot = (udef and udef.buildable_to) and pointed_thing.under or pointed_thing.above
	local pname = placer:get_player_name()
	if core.is_protected(spot, pname) and not core.check_player_privs(pname, { protection_bypass = true }) then
		core.record_protection_violation(spot, pname)
		return itemstack
	end
	local def = core.registered_entities[mob]
	local cb = core.deserialize(meta:get_string("cbox")) or (def.initial_properties or def).collisionbox or { -0.4, -0.5, -0.4, 0.4, 0.5, 0.4 }
	local height = cb[5] - cb[2]
	-- Only the chosen spot is used: searching higher could put the mob on the far side of a ceiling.
	local chosen = free_spot(spot, height) and spot or nil
	if not chosen then say(placer, S("There is not enough room (or it is not safe) there.")); return itemstack end
	local pos = vector.new(chosen.x, chosen.y - 0.5 - cb[2] + 0.01, chosen.z)
	local obj = core.add_entity(pos, mob, data ~= "" and data or nil)
	if not obj then say(placer, S("The mob would not come out.")); return itemstack end
	-- face the player
	local yaw = placer:get_look_horizontal() + math.pi
	local ent = obj:get_luaentity()
	if ent and ent.set_yaw then ent:set_yaw(yaw) else obj:set_yaw(yaw) end
	for _, fn in ipairs(mobcrate.on_release) do fn(obj, placer) end
	return ItemStack("mobcrate:crate_empty")
end

----------------------------------------------------------------------------------------------------------------------
-- Right-click on a mob happens before the mob's own right-click (villagers go in instead of opening trading)
----------------------------------------------------------------------------------------------------------------------
core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_entities) do
		local looks_like_mob = def.is_mob or def.type == "animal" or def.type == "monster" or def.type == "npc" or def._mobcrate_ok
		if looks_like_mob then
			local orig = def.on_rightclick
			def.on_rightclick = function(self, clicker, ...)
				if clicker and clicker:is_player() and clicker:get_wielded_item():get_name() == "mobcrate:crate_empty" then
					mobcrate.try_capture(clicker, self.object)
					return
				end
				if orig then return orig(self, clicker, ...) end
			end
		end
	end
end)

----------------------------------------------------------------------------------------------------------------------
-- Settings screen
----------------------------------------------------------------------------------------------------------------------
local function can_edit(name) return core.is_singleplayer() or core.check_player_privs(name, { server = true }) end
uikit.screen({
	name = "mobcrate:main", title = S("Mob Crate"), width = 10, command = "mobcrate", description = S("Open the Mob Crate settings"),
	can = can_edit, denied = S("Only the world owner or an operator can change these."),
	rows = {
		{ type = "toggle", id = "bosses", label = S("Bosses can be put in a crate"), get = function() return setting_bool("allow_bosses") end,
			set = function(_, v) storage:set_string("allow_bosses", v and "true" or "false") end },
		{ type = "toggle", id = "others", label = S("Other players' tamed animals can be put in a crate"), get = function() return setting_bool("allow_other_players_pets") end,
			set = function(_, v) storage:set_string("allow_other_players_pets", v and "true" or "false") end },
		{ type = "gap" },
		{ type = "field", id = "blacklist", label = S("Blacklist (mob ids, separated by commas):"), button_name = "save", button = S("Save"),
			get = function() return storage:get_string("blacklist") end, set = function(_, v) storage:set_string("blacklist", (v:gsub("[%c]", ""))) end },
		{ type = "text", text = S("Example: mobs_mc:villager, mobs_mc:iron_golem"), dim = true },
	},
})

if core.get_modpath("hq") then
	hq.register_shortcut({ id = "mobcrate", name = "Mob Crate", command = "mobcrate", icon = "mobcrate:crate_full", short = "MC" })
end
