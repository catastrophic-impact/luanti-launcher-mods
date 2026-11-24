local function log(s) core.log("action", "[RIDE_SHOTS] " .. s) end
local KINDS = { "cow", "pig", "horse", "wolf", "sheep" }
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local i, mode_i = 0, 99
		local MODES = { "third", "third_front" }
		local obj, ent
		local function nxt()
			mode_i = mode_i + 1
			if not obj or mode_i > #MODES then
				if obj then ent:detach(player, vector.new(0, 0.5, 0)); obj:remove() end
				mode_i = 1; i = i + 1
				if not KINDS[i] then log("SHOTS_DONE"); return core.request_shutdown("done") end
				obj = core.add_entity(base, "mobs_mc:" .. KINDS[i])
				ent = obj:get_luaentity()
				player:get_inventory():add_item("main", "tameful:lead 1")
				player:set_wielded_item(ItemStack("tameful:lead"))
				ent.on_rightclick(ent, player)
				for _, f in ipairs(core.registered_on_player_receive_fields) do
					if f(player, "tameful:tame", { yes = "true" }) then break end
				end
				core.close_formspec("tester", "tameful:tame")
				core.after(1.5, function()
					player:set_pos(vector.offset(obj:get_pos(), 1, 0, 0))
					local ok, why = tameful.ride(ent, player)
					log(KINDS[i] .. " ride: " .. tostring(ok) .. " " .. tostring(why))
					player:set_look_horizontal(-math.pi / 2)
					core.after(1.5, function() mode_i = 0; nxt() end)
				end)
				return
			end
			player:set_camera({ mode = MODES[mode_i] })
			core.after(2, function()
				-- the mob keeps still: ent should have no velocity; freeze it so the shot is steady
				log("SHOT_READY ride_" .. KINDS[i] .. "_" .. MODES[mode_i])
				core.after(3, nxt)
			end)
		end
		nxt()
	end)
end)
