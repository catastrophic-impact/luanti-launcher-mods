local function log(s) core.log("action", "[SHOTS_TEST] " .. s) end
-- Freeze a mob completely (no AI, no head swivel, no gait) so a shot shows the model and nothing else.
local function freeze(ent, yaw)
	ent.on_step = function() end
	ent.object:set_velocity(vector.zero())
	ent.object:set_acceleration(vector.zero())
	ent.object:set_animation({ x = 40, y = 49 }, 2, 0, true) -- the zombie body's stand frames
	if yaw then ent.object:set_yaw(yaw) end
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true })
		local pos = vector.round(player:get_pos())
		player:set_look_horizontal(-math.pi / 2) -- +x
		player:set_look_vertical(0.1)
		for i, dz in ipairs({ -3, -1, 1, 3 }) do
			local sd = (i == 3) and core.serialize({ child = true }) or nil
			local obj = core.add_entity(vector.offset(pos, 3.5, 1, dz * 0.9), "mobs_mc:villager", sd)
			local ent = obj and obj:get_luaentity()
			if ent then
				if i == 2 then ent:set_profession("armorer") end
				ent.object:set_yaw(-math.pi / 2) -- face the player
				log(string.format("villager %d: %s %s", i, ent._pop.gender, ent._pop.skin))
			end
		end
		core.after(4, function()
			for _, o in ipairs(core.get_objects_inside_radius(pos, 15)) do
				local e = o:get_luaentity()
				if e and e.name == "mobs_mc:villager" then freeze(e, math.pi / 2) end
			end
			local names = {}
			for _, o in ipairs(core.get_objects_inside_radius(pos, 15)) do
				local e = o:get_luaentity()
				names[#names + 1] = (e and e.name or "player") .. core.pos_to_string(vector.round(o:get_pos()))
			end
			log(string.format("scene: player pos=%s look h=%.2f v=%.2f; objects: %s", core.pos_to_string(vector.round(player:get_pos())),
				player:get_look_horizontal(), player:get_look_vertical(), table.concat(names, " ")))
			log("SHOT_READY villagers")
			-- backs: turn every villager around and verify the yaw before the shot
			core.after(2.5, function()
				local yaws = {}
				for _, o in ipairs(core.get_objects_inside_radius(pos, 15)) do
					local e = o:get_luaentity()
					if e and e.name == "mobs_mc:villager" then freeze(e, -math.pi / 2); yaws[#yaws + 1] = string.format("%.2f/vel%.2f", o:get_yaw() % (2 * math.pi), vector.length(o:get_velocity())) end
				end
				player:set_look_vertical(0.25)
				log("backs: yaws " .. table.concat(yaws, " "))
				core.after(0.5, function()
					log("SHOT_READY backs")
					-- close-up of one back: stand 1.6 blocks behind the second villager, look slightly up
					core.after(3, function()
						for _, o in ipairs(core.get_objects_inside_radius(pos, 15)) do
							local e = o:get_luaentity()
							if e and e.name == "mobs_mc:villager" and not e.child then
								local vp = o:get_pos()
								player:set_pos(vector.offset(vp, -1.8, 0, 0))
								player:set_look_horizontal(-math.pi / 2)
								player:set_look_vertical(-0.1)
								break
							end
						end
						core.after(1, function() log("SHOT_READY closeback") end)
					end)
				end)
			end)
		end)
		core.after(19, function()
			for _, o in ipairs(core.get_objects_inside_radius(pos, 20)) do
				if not o:is_player() then o:remove() end
			end
			core.after(1, function()
				local kinds = { { "mobs_mc:villager_zombie" }, { "mobs_mc:villager_zombie", { child = true } }, { "mobs_mc:zombie" } }
				for i, k in ipairs(kinds) do
					local zo = core.add_entity(vector.offset(pos, 3.5, 1, (i - 2) * 1.6), k[1], k[2] and core.serialize(k[2]) or nil)
					local ze = zo:get_luaentity()
					ze.ai_functions = {}; ze.ignited_by_sunlight = false
					ze.object:set_yaw(-math.pi / 2)
					log(k[1] .. (k[2] and " (child)" or "") .. " mesh=" .. zo:get_properties().mesh .. " tex=" .. table.concat(zo:get_properties().textures, "||"))
				end
				core.after(3, function() log("SHOT_READY zombies") end)
			end)
		end)
		core.after(27, function()
			-- back to the starting spot and view
			player:set_pos(vector.offset(pos, 0, 0, 0))
			player:set_look_horizontal(-math.pi / 2)
			player:set_look_vertical(0.1)
			-- Fight scene: shot is taken only once the state is verified (gear on, enemy in reach), never on a timer.
			for _, o in ipairs(core.get_objects_inside_radius(pos, 20)) do
				if not o:is_player() then o:remove() end
			end
			core.after(1, function()
				local v = core.add_entity(vector.offset(pos, 4, 1, 0), "mobs_mc:villager"):get_luaentity()
				local cobj = core.add_entity(vector.offset(pos, 6, 1, 0), "mobs_mc:cow")
				local cow = cobj:get_luaentity()
				-- the cow sets its own health after activation, so make it a durable punching bag one step later
				core.after(0.5, function()
				cow.object:set_properties({ hp_max = 1000 })
				cow.health = 1000
				v:receive_damage({ type = "mob", source = cobj }, 1)
				local t = 0
				local function poll()
					t = t + 0.2
					local st = populations._fight_state[v]
					local d = vector.distance(v.object:get_pos(), cobj:get_pos())
					log(string.format("fight t=%.1f gear=%s sword=%s head=%s dist=%.1f cowhp=%s act=%s", t, tostring(st and st.geared),
						v:get_wielditem():get_name(), tostring(v.armor_list.head), d, tostring(cow.health), tostring(v._active_activity)))
					local tex = v.object:get_properties().textures
					log("  textures: " .. table.concat(tex, " || "):sub(1, 400) .. " | cow dead=" .. tostring(cow.dead) .. " base_texture=" .. #(v.base_texture or {}))
					if st and st.geared and d < 3 and v.armor_list.head ~= "" and not cow.dead and tex[1] ~= "blank.png" then
						log("SHOT_READY fight")
						return core.after(2.5, function() log("SHOTS_DONE"); core.request_shutdown("done") end)
					end
					if t > 20 then log("SHOT_ABORT fight never reached state"); return core.request_shutdown("done") end
					core.after(0.2, poll)
				end
				poll()
				end)
			end)
		end)
	end)
end)
