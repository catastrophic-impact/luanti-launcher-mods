-- Dungeon Portal Frame and the four Dungeon Keys (tiers I-IV).
local S = core.get_translator("dungeoneer")

core.register_node("dungeoneer:frame", {
	description = S("Dungeon Portal Frame"),
	_doc_items_longdesc = S("Build a ring of these standing up around a 2x2 opening (corners are not needed), then use a Dungeon Key on it."),
	tiles = { "dungeoneer_frame.png" },
	is_ground_content = false,
	sounds = mcl_sounds.node_sound_stone_defaults(),
	groups = { pickaxey = 5, building_block = 1, material_stone = 1, unmovable_by_piston = 1 }, -- needs a diamond pickaxe, like obsidian
	_mcl_blast_resistance = 1200,
	_mcl_hardness = 50,
	after_destruct = function(pos) dungeoneer.on_frame_destroyed(pos) end,
})

core.register_craft({
	output = "dungeoneer:frame 8",
	recipe = {
		{ "mcl_core:stonebrick", "mcl_core:obsidian", "mcl_core:stonebrick" },
		{ "mcl_core:obsidian", "", "mcl_core:obsidian" },
		{ "mcl_core:stonebrick", "mcl_core:obsidian", "mcl_core:stonebrick" },
	},
})

local names = { "I", "II", "III", "IV" }
for tier = 1, 4 do
	core.register_craftitem("dungeoneer:key_" .. tier, {
		description = S("Dungeon Key (Tier @1)", names[tier]),
		_doc_items_longdesc = S("Use it on a ring of Dungeon Portal Frames to build a dungeon of tier @1. The key is used up. Tier 1 keys drop from hostile mobs; every other key is in the chest of the dungeon one tier below.", names[tier]),
		inventory_image = "dungeoneer_key_" .. tier .. ".png",
		stack_max = 1, -- one key at a time (see keys.lua)
		on_pickup = function(...) return dungeoneer.key_on_pickup(...) end,
		on_place = function(stack, placer, pt)
			if pt and pt.type == "node" then return dungeoneer.use_key(placer, stack, pt.under, tier) end
			return stack
		end,
	})
end
