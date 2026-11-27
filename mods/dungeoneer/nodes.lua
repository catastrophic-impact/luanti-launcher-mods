-- Dungeon blocks: unbreakable like bedrock (only creative mode can break them), blast-proof, not movable by pistons, nothing replaces them.
local S = core.get_translator("dungeoneer")
local function unbreakable(def)
	def.groups = def.groups or {}
	def.groups.creative_breakable = 1; def.groups.unmovable_by_piston = 1; def.groups.features_cannot_replace = 1; def.groups.building_block = 1
	def.is_ground_content = false
	def.drop = ""
	def._mcl_blast_resistance = 3600000
	def._mcl_hardness = -1
	def.on_blast = function() end
	def.sounds = mcl_sounds.node_sound_stone_defaults()
	return def
end
core.register_node("dungeoneer:brick", unbreakable{ description = S("Dungeon Bricks"), tiles = { "dungeoneer_brick.png" } })
core.register_node("dungeoneer:floor", unbreakable{ description = S("Dungeon Floor"), tiles = { "dungeoneer_floor.png", "dungeoneer_brick.png", "dungeoneer_brick.png" } })
core.register_node("dungeoneer:lantern", unbreakable{ description = S("Dungeon Lantern"), tiles = { "dungeoneer_lantern.png" }, light_source = 14,
	sounds = mcl_sounds.node_sound_glass_defaults() })
