-- Per-species pet stats (the Fabric Tameful 1.0.3 chart, for the animals Mineclonia has) + armor/crit/health application.
-- speed/jump are used by riding (not built yet); attack/armor/hp/crit are applied here.
tameful.WALK_SPEED = 6
tameful.RABBIT_HOP_DELAY = 0.1
tameful.MAX_LEG_CYCLES = 2.5 -- walk-cycle frames cap = animation length x this (cycles per second)
-- species whose movement does not follow movement_speed 1:1 (rabbits hop): measured by tests/tameful_speed_probe
tameful.SPEED_FACTOR = {} -- rabbits tried 2x and 3x: hops became 30 b/s bursts with no better average, so they stay at 1
local WEAPON = { wood = 4, stone = 5, iron = 6, diamond = 7, netherite = 8 }
local ARMOR = { -- armor points, toughness
	leather = { 3, 0 }, chain = { 5, 0 }, iron = { 6, 0 }, diamond = { 8, 2 }, netherite = { 8, 3 },
}
local function S(speed, jump, weapon, armor, hp, crit)
	return { speed = speed, jump = jump, weapon = weapon, armor = armor, hp = hp, crit = crit }
end
local horse = S(8, 2, "stone", "leather", 40, 10)
local cat = S(8, 2, "iron", "leather", 40, 20)
local wolf = S(8, 1, "iron", "chain", 30, 30)
local cow = S(7, 1, "wood", "leather", 40, 5)
local STATS = {
	["mobs_mc:bat"] = S(8, "fly", "stone", "leather", 30, 10),
	["mobs_mc:cat"] = cat, ["mobs_mc:ocelot"] = cat,
	["mobs_mc:chicken"] = S(8, 1, "wood", "leather", 30, 5),
	["mobs_mc:cow"] = cow, ["mobs_mc:mooshroom"] = cow,
	["mobs_mc:donkey"] = S(8, 1, "stone", "leather", 40, 10),
	["mobs_mc:mule"] = S(8, 1, "stone", "leather", 40, 10),
	["mobs_mc:horse"] = horse, ["mobs_mc:skeleton_horse"] = horse, ["mobs_mc:zombie_horse"] = horse,
	["mobs_mc:llama"] = S(6, 1, "wood", "leather", 40, 5),
	["mobs_mc:parrot"] = S(8, "fly", "wood", "leather", 30, 5),
	["mobs_mc:pig"] = S(8, 1, "wood", "chain", 50, 10),
	["mobs_mc:polar_bear"] = S(6, 1, "netherite", "netherite", 60, 10),
	["mobs_mc:rabbit"] = S(8, 2, "wood", "leather", 30, 5),
	["mobs_mc:sheep"] = S(6, 1, "wood", "leather", 30, 5),
	["mobs_mc:strider"] = S(6, 1, "stone", "chain", 40, 5),
	["mobs_mc:turtle"] = S(4, 1, "stone", "netherite", 40, 5),
	["mobs_mc:wolf"] = wolf, ["mobs_mc:dog"] = wolf,
}
local DEFAULT = S(8, 1, "wood", "leather", 40, 5) -- animals from other mods

-- Resolved numbers for an entity name.
function tameful.stats_for(name)
	local s = STATS[name] or DEFAULT
	local a = ARMOR[s.armor]
	return {
		speed = s.speed, jump = s.jump, attack = WEAPON[s.weapon], armor_points = a[1], toughness = a[2],
		hp = s.hp, crit = s.crit, weapon = s.weapon, armor = s.armor,
	}
end

-- Put the stats on a pet entity. full_heal = set health to the maximum (at taming).
function tameful.apply_stats(ent, full_heal)
	local st = tameful.stats_for(ent.name)
	ent._tameful_stats = st
	ent.damage = st.attack
	ent.object:set_properties({ hp_max = st.hp })
	-- every pet walks at a wolf's pace (movement_speed 6): wandering ~3.3 b/s, following 7 b/s (FOLLOW_BONUS in pets.lua), measured by tests/tameful_speed_probe.
	-- movement_speed is persisted by Mineclonia, so the species value is kept and put back on release.
	if st.jump ~= "fly" and ent.movement_speed then
		if not ent._tameful_orig_speed then ent._tameful_orig_speed = ent.movement_speed end
		ent.movement_speed = tameful.WALK_SPEED * (tameful.SPEED_FACTOR[ent.name] or 1)
		if ent.pace_bonus ~= 0.95 then -- calm walk (measured 3.5 b/s); horses and llamas paced slower, others faster
			if not ent._tameful_orig_pace then ent._tameful_orig_pace = ent.pace_bonus end
			ent.pace_bonus = 0.95
		end
	end
	-- every pet swims instead of sinking (skeleton and zombie horses have floats = 0); striders keep their lava logic
	if ent.name ~= "mobs_mc:strider" and (ent.floats or 0) == 0 and ent._tameful_orig_floats == nil then
		ent._tameful_orig_floats = ent.floats or 0
		ent.floats = 1
	end
	-- name tags do nothing on pets (names are set in the pet window)
	if ent._tameful_orig_ign == nil then ent._tameful_orig_ign = ent.ignores_nametag or false end
	ent.ignores_nametag = true
	-- behaviour settings (persist with the entity); animals without an attack get plain melee
	ent._tameful_attitude = ent._tameful_attitude or "defensive"
	ent._tameful_range = ent._tameful_range or 16
	ent._tameful_wander = ent._tameful_wander or 12
	if not ent.attack_type then ent.attack_type = "melee"; ent._tameful_set_melee = true end
	if full_heal or (ent.health or 0) > st.hp then ent.health = st.hp end
	-- crit: double the hit with the given chance (the mob attack reads self.damage on every punch)
	ent.custom_attack = function(self)
		local base = self.damage
		self._tameful_engaged_at = core.get_gametime()
		if math.random() * 100 < st.crit then self.damage = base * 2 end
		mcl_mobs.mob_class.custom_attack(self)
		self.damage = base
	end
end

-- Armor: same formula as Mineclonia's mcl_armor, fed with the fixed numbers (pets wear nothing visible). Runs before mcl_armor
-- (mcl_armor finds no armor_list items on a pet, so it changes nothing).
mcl_damage.register_modifier(function(obj, damage, reason)
	local ent = obj:get_luaentity()
	local st = ent and ent._tameful_stats
	if not st or reason.flags.bypasses_armor then return damage end
	local pts, tough = st.armor_points, st.toughness
	return damage * (1 - math.min(20, math.max(pts / 5, pts - damage / (2 + tough / 4))) / 25)
end, -10)
