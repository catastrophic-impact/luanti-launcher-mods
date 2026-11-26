-- Bees. Step 1: the bee mob only (flies and wanders). Hives, pollination, taming rules come in later steps.
-- Model and textures: bees_bee.* (credit in LICENSE.txt). Referenced ONLY here, so a replacement is a file swap.
local S = core.get_translator("bees")
bees = bees or {}
dofile(core.get_modpath("bees") .. "/hive.lua")
local mob_class = mcl_mobs.mob_class

local MESH = "bees_bee.obj"
local TORSO, FEATURES, WINGS = "bees_bee_torso.png^[multiply:#f2b822", "bees_bee_features.png", "bees_bee_wings.png"
local FEATURES_ANGRY = "bees_bee_features_angry.png" -- red eyes while angry

local WING_FRAME = { WINGS .. "^[verticalframe:2:0", WINGS .. "^[verticalframe:2:1" }
local WING_PERIOD = 0.12 -- seconds per wing frame
local WING_RANGE = 40 -- only animate bees this close to a player (each change is a network update)

local bee = {
	description = S("Bee"),
	type = "animal",
	_spawn_category = "creature",
	can_despawn = false, -- a beekeeper's bees must never vanish while the player is away
	persistent = true,
	hp_min = 10, hp_max = 10,
	xp_min = 1, xp_max = 3,
	collisionbox = { -0.25, -0.2, -0.25, 0.25, 0.2, 0.25 },
	visual = "mesh",
	mesh = MESH,
	backface_culling = false, -- the wings are flat planes: with culling they vanish or flip depending on the viewing angle
	rotate = 180, -- the model's head is at -z, entities face +z: without this the bee flies tail first
	textures = { { TORSO, FEATURES, WINGS .. "^[verticalframe:2:0" } },
	visual_size = { x = 5.5, y = 5.5 }, -- entity meshes are 1/10 node per unit; the model is ~0.93 wide, so ~0.5 node
	animation = { stand_start = 0, stand_end = 0, walk_start = 0, walk_end = 0, fly_start = 0, fly_end = 0 },
	_no_fall_damage = true,
	gravity_drag = 0.6,
	floats = 1,
	sounds = { random = "bees_bee", damage = { name = "bees_bee", gain = 0.8 }, death = "bees_bee", distance = 14 },
	physical = true,
	movement_speed = 1.5,
	airborne_speed = 4.5, -- in the air mcl_mobs uses this instead of movement_speed (default 8); measured: 1.5 gave ~0.33 nodes/s, so 4.5 ~ 1 node/s
	_hovers = true, -- without a goal an airborne mob falls unless this is set
	airborne = true,
	makes_footstep_sound = false,
	pace_interval = 0.5, -- bees are nearly always on the move (default: idle 5 s, then 1 in 120 per check)
	pace_chance = 1,
	pace_height = 4,
	pace_width = 6,
}

-- Bees drift slowly 1-3 nodes above the ground (or flowers) and never perch.
local function walkable(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return not def or def.walkable ~= false or (def.groups and (def.groups.liquid or 0) > 0)
end

function bee:airborne_pacing_target(pos, width, height, groups)
	local base = vector.round(pos)
	for _ = 1, 10 do
		local t = vector.offset(base, math.random(-width, width), math.random(-1, 1), math.random(-width, width))
		if not walkable(t) and (not self._hive or vector.distance(t, self._hive) < (bees.LEASH or 22) - 2) then
			-- height above the first solid node below, searched 5 nodes down
			local above
			for d = 1, 5 do
				if walkable(vector.offset(t, 0, -d, 0)) then above = d; break end
			end
			if above and above >= 1 and above <= 3 then return t end
		end
	end
end

function bee:ai_step(dtime)
	mob_class.ai_step(self, dtime)
	self._wing_t = (self._wing_t or 0) + dtime
	if self._wing_t < WING_PERIOD then return end
	self._wing_t = 0
	local pos = self.object:get_pos()
	if not pos then return end
	local near = false
	for _, pl in ipairs(core.get_connected_players()) do
		if vector.distance(pl:get_pos(), pos) < WING_RANGE then near = true; break end
	end
	if not near then return end
	self._wing_i = 3 - (self._wing_i or 1)
	self.object:set_properties({ textures = { TORSO, self._angry_until and FEATURES_ANGRY or FEATURES, WING_FRAME[self._wing_i] } })
end

dofile(core.get_modpath("bees") .. "/brain.lua")
dofile(core.get_modpath("bees") .. "/anger.lua")
bee.receive_damage = bees.receive_damage

bee.ai_functions = {
	bees.check_anger,
	mob_class.check_frightened,
	bees.check_hive,
	mob_class.check_pace,
}

mcl_mobs.register_mob("bees:bee", bee)
mcl_mobs.register_egg("bees:bee", S("Bee"), "#f2b822", "#2b2b2b", 0)
