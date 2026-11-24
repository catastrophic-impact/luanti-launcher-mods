-- The zombie body: a clean humanoid with standard 8x8x8 head UVs (a player skin fits it; the piglin head does not).
-- Used for zombie villagers (ordinary zombie look) and for the people themselves (with their skins and the arms lowered).
function populations.borrow_zombie_body(target)
	local z = core.registered_entities["mobs_mc:zombie"]
	local zv = target
	local function get(f) return rawget(z, f) or z[f] end
	for _, f in ipairs({ "mesh", "visual_size", "collisionbox", "head_swivel", "bone_eye_height", "head_eye_height",
		"head_pitch_multiplier", "animation", "wielditem_info", "_armor_texture_slots", "_armor_transforms",
		"_head_armor_bone", "_head_armor_position", "_head_armor_visual_scale", "_head_armor_rotation", "_arm_poses",
		"_arm_pose_continuous" }) do
		zv[f] = get(f)
	end
	zv.animation = table.copy(get("animation"))
	local ip, zip = zv.initial_properties, z.initial_properties
	for _, f in ipairs({ "mesh", "visual_size", "collisionbox" }) do ip[f] = zip[f] end
	return z, zip, ip
end

core.register_on_mods_loaded(function()
	local zv = core.registered_entities["mobs_mc:villager_zombie"]
	if not (zv and core.registered_entities["mobs_mc:zombie"]) then return end
	local z, zip, ip = populations.borrow_zombie_body(zv)
	local skin = { "mobs_mc_empty.png", "mobs_mc_zombie.png" }
	ip.textures = skin
	zv.get_overlaid_texture = function() return skin[1] end
	zv.update_textures = function(self)
		self.base_texture = { skin[1], skin[2] }
		self:set_textures(self.base_texture)
		self.base_mesh = zip.mesh
		self.base_size = zip.visual_size
		self.base_colbox = zip.collisionbox
		self.base_selbox = zip.selectionbox or zip.collisionbox
	end
end)
