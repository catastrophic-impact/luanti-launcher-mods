-- Conflict Resolution (Luanti/Mineclonia port of the Fabric mod): PvP on/off and pet protection.
-- Everything goes through one mcl_damage modifier. The attacker is the player behind the damage: a player's own hit, an arrow/trident/potion
-- they shot (reason.source), a tamed animal of theirs (its owner) or a TNT they lit (tagged below). Damage with no player behind it
-- (lava, fire, wild mobs, poison already ticking) is never blocked.
local S = core.get_translator("conflictresolution")
local esc = core.formspec_escape
local storage = core.get_mod_storage()
conflictresolution = {}
local cr = conflictresolution

-- Settings (per world, mod storage): pvp (default off), protect_pets (on), protect_own (off) ---------------------------------
local DEFAULTS = { pvp = false, protect_pets = true, protect_own = true }
function cr.get(key)
	local v = storage:get_string(key)
	if v == "" then return DEFAULTS[key] end
	return v == "true"
end
local function can_edit(name) return core.is_singleplayer() or core.check_player_privs(name, { server = true }) end
cr.can_edit = can_edit

local function announce(text) core.chat_send_all(core.colorize("#ffcc55", "[Conflict Resolution] ") .. text) end
local ANNOUNCE = {
	pvp = function(on) return on and S("PvP is now ON: players can hurt each other.") or S("PvP is now OFF: players can't hurt each other.") end,
	protect_pets = function(on) return on and S("Other players' pets are now protected.") or S("Other players' pets are no longer protected.") end,
	protect_own = function(on) return on and S("Owners can no longer hurt their own pets.") or S("Owners can hurt their own pets again.") end,
}
function cr.set(key, on)
	if DEFAULTS[key] == nil then return false end
	if cr.get(key) == on then return true end
	storage:set_string(key, on and "true" or "false")
	announce(ANNOUNCE[key](on))
	return true
end

-- TNT: remember who lit it (explosions carry no source in Mineclonia) ---------------------------------------------------------
local igniter -- player name while a player's ignite call runs
if core.registered_nodes["mcl_tnt:tnt"] and mcl_tnt then
	local orig_ignite = mcl_tnt.ignite
	mcl_tnt.ignite = function(pos, ...)
		local e = orig_ignite(pos, ...)
		local ent = e and e:get_luaentity()
		if ent and igniter then ent._cr_igniter = igniter end
		return e
	end
	local def = core.registered_nodes["mcl_tnt:tnt"]
	local orig_on_ignite = def._on_ignite
	if orig_on_ignite then
		core.override_item("mcl_tnt:tnt", { _on_ignite = function(player, pointed_thing, ...)
			igniter = player and player.is_player and player:is_player() and player:get_player_name() or nil
			local r = orig_on_ignite(player, pointed_thing, ...)
			igniter = nil
			return r
		end })
	end
end

-- Who is behind a damage event? ----------------------------------------------------------------------------------------------
local function owner_of(obj)
	if not obj then return nil end
	if obj:is_player() then return obj:get_player_name() end
	local ent = obj:get_luaentity()
	if not ent then return nil end
	if ent._cr_igniter then return ent._cr_igniter end
	if ent.tamed and ent.owner and ent.owner ~= "" then return ent.owner end
	local shooter = ent._shooter or ent._source_object
	if shooter and shooter ~= obj and shooter.is_valid and shooter:is_valid() then return owner_of(shooter) end
	return nil
end
function cr.attacker_name(reason)
	if not reason then return nil end
	return owner_of(reason.source) or owner_of(reason.direct)
end

local last_msg = {}
local function tell(name, text)
	local p = core.get_player_by_name(name)
	if not p then return end
	local now = core.get_gametime()
	if last_msg[name] and last_msg[name].t == now and last_msg[name].text == text then return end
	last_msg[name] = { t = now, text = text }
	if mcl_title then mcl_title.set(p, "actionbar", { text = text, color = "white", stay = 40 })
	else core.chat_send_player(name, text) end
end

-- the decision, separate from the engine so tests can ask it directly: returns nil (allowed) or the reason text
function cr.blocked(victim, attacker)
	if not attacker then return nil end
	if victim:is_player() then
		local vn = victim:get_player_name()
		if attacker ~= vn and not cr.get("pvp") then return S("PvP is off.") end
		return nil
	end
	local ent = victim:get_luaentity()
	if not (ent and ent.tamed and ent.owner and ent.owner ~= "") then return nil end
	if attacker == ent.owner then
		if cr.get("protect_own") then return S("You can't hurt your own pet.") end
	elseif cr.get("protect_pets") then
		return S("This pet belongs to @1.", ent.owner)
	end
	return nil
end

mcl_damage.register_modifier(function(obj, damage, reason)
	if damage <= 0 then return damage end
	local attacker = cr.attacker_name(reason)
	local why = cr.blocked(obj, attacker)
	if why then
		tell(attacker, why)
		return 0
	end
	return damage
end, -100)

-- Commands -----------------------------------------------------------------------------------------------------------------
local function onoff(v) return v and S("on") or S("off") end
local function status()
	return S("PvP: @1, protect pets: @2, protect own pets: @3", onoff(cr.get("pvp")), onoff(cr.get("protect_pets")), onoff(cr.get("protect_own")))
end
local function parse(v) if v == "on" then return true elseif v == "off" then return false end end

core.register_chatcommand("pvp", {
	params = "[on|off | pets on|off | ownpets on|off]",
	description = S("Show or change the PvP and pet protection settings"),
	func = function(name, param)
		local a, b = param:match("^%s*(%S*)%s*(%S*)%s*$")
		if not a or a == "" then return true, status() end
		local key, val
		if a == "pets" then key, val = "protect_pets", parse(b)
		elseif a == "ownpets" then key, val = "protect_own", parse(b)
		else key, val = "pvp", parse(a) end
		if val == nil then return false, S("Usage: /pvp [on|off | pets on|off | ownpets on|off]") end
		if not can_edit(name) then return false, S("Only the world owner or an operator can change this.") end
		cr.set(key, val)
		return true
	end,
})

-- Settings screen (/cr) ----------------------------------------------------------------------------------------------------------
uikit.screen({
	name = "conflictresolution:main", title = S("Conflict Resolution"), command = "cr", description = S("Open the Conflict Resolution settings"),
	can = can_edit, denied = S("Only the world owner or an operator can change this."),
	rows = (function()
		local rows = {}
		for _, r in ipairs({ { "pvp", S("PvP (players can hurt each other)") }, { "protect_pets", S("Protect other players' pets") }, { "protect_own", S("Protect own pets from you") } }) do
			rows[#rows + 1] = { type = "toggle", id = r[1], label = r[2], get = function() return cr.get(r[1]) end, set = function(_, v) cr.set(r[1], v) end }
		end
		return rows
	end)(),
})

if core.get_modpath("hq") then
	hq.register_shortcut({ id = "conflictresolution", name = "Conflict Resolution", command = "cr", icon = "mcl_tools:sword_iron", short = "CR" })
end
