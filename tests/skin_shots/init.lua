local function log(s) core.log("action", "[SKIN_SHOTS] " .. s) end
local dir = core.get_modpath("skin_shots") .. "/skins/"
local function media(file, name)
	core.dynamic_add_media({ filename = name, filepath = dir .. file, ephemeral = true }, function() end)
	return name
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		core.set_player_privs("tester", { interact = true, shout = true })
		local steve = media("steve.png", "sk_steve.png")
		local alex = media("alex.png", "sk_alex.png")
		local cape = media("cape.png", "sk_cape.png")
		-- stop Mineclonia re-applying its own skin
		mcl_skins.update_player_skin = function() end
		local scenes = {
			{ "cape_slot3_back", "mcl_armor_character.b3d", "[combine:64x32:0,0=" .. steve, "blank.png", cape, "third_front" },
			{ "cape_slot2_back", "mcl_armor_character.b3d", "[combine:64x32:0,0=" .. steve, cape, "blank.png", "third_front" },
		}
		local i = 0
		local function nxt()
			i = i + 1
			local s = scenes[i]
			if not s then log("SHOTS_DONE"); return core.request_shutdown("done") end
			mcl_player.player_set_model(player, s[2])
			mcl_player.players[player].textures = { s[3], s[4], s[5] }
			player:set_properties({ textures = { s[3], s[4], s[5] } })
			player:set_camera({ mode = s[6] })
			core.after(3, function()
				log("state " .. s[1] .. " mesh=" .. player:get_properties().mesh .. " tex=" .. table.concat(player:get_properties().textures, ","))
				log("SHOT_READY " .. s[1])
				core.after(3, nxt)
			end)
		end
		nxt()
	end)
end)
