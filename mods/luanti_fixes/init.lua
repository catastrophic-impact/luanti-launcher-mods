-- Small fixes for upstream Mineclonia behaviour that need no game patch. (Also ships textures upstream is missing.)

-- New players always start as the boy (Mineclonia picks the boy or the girl at random). Players who already have a saved skin keep it.
if core.get_modpath("mcl_skins") then
	core.register_on_newplayer(function(player)
		if mcl_skins.steve and mcl_skins.steve.base_color then
			player:get_meta():set_string("mcl_skins:skin", core.serialize(table.copy(mcl_skins.steve)))
		end
	end)
end
