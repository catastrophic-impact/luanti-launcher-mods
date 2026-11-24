local storage = core.get_mod_storage()
local phase = storage:get_int("phase")
local function log(s) core.log("action", "[TAMEFUL_PERSIST_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
if phase == 0 then
	core.register_on_joinplayer(function(player)
		if player:get_player_name() ~= "tester" then return end
		core.after(18, function()
			core.set_player_privs("tester", { interact = true, shout = true, server = true })
			tameful.cfg.set("max_summoned", 0)
			local obj = core.add_entity(vector.offset(vector.round(player:get_pos()), 3, 1, 0), "mobs_mc:pig")
			local ent = obj:get_luaentity()
			player:get_inventory():add_item("main", "tameful:lead 1")
			player:set_wielded_item(ItemStack("tameful:lead"))
			ent.on_rightclick(ent, player)
			deliver(player, "tameful:tame", { yes = "true" })
			core.close_formspec("tester", "tameful:tame")
			core.after(1.5, function()
				local id = ent._tameful_id
				tameful.set_attitude(ent, "aggressive")
				ent._tameful_range = 24; ent._tameful_wander = 6
				tameful.set_mode(ent, "relax")
				ent._tameful_home = { x = 11, y = 12, z = 13 }
				tameful.find_record(id).name = "Hamlet"
				check("stabled with settings", tameful.stable(id, false))
				storage:set_int("phase", 1); storage:set_string("pet_id", tostring(id))
				storage:set_string("pet_pos", core.serialize(vector.round(player:get_pos())))
				log("SCENARIO_DONE")
				core.request_shutdown("done", false, 1)
			end)
		end)
	end)
else
	local id = tonumber(storage:get_string("pet_id"))
	local pos = core.deserialize(storage:get_string("pet_pos"))
	core.after(1, function()
		local rec = tameful.roster.tester and tameful.roster.tester[id]
		check("restart: record there, stabled, order relax", rec and rec.status == "stabled" and rec.order == "")
		local snap = core.deserialize(rec.snapshot)
		check("snapshot keeps attitude/range/wander/home", snap._tameful_attitude == "aggressive" and snap._tameful_range == 24 and snap._tameful_wander == 6 and snap._tameful_home and snap._tameful_home.x == 11,
			core.serialize({ snap._tameful_attitude, snap._tameful_range, snap._tameful_wander }):gsub("\n", " "))
		core.forceload_block(pos, true)
		core.after(2, function()
			-- the real resummon path needs a player; spawn the snapshot as a live pet copy the way resummon does (state first)
			rec.status = "out"; rec.epoch = (rec.epoch or 0) + 1; rec.loaded = true
			snap._tameful_epoch = rec.epoch; snap.order = "relax"
			local obj = core.add_entity(vector.offset(pos, 0, 3, 0), rec.kind, core.serialize(snap))
			core.after(2, function()
				local e = obj and obj:get_luaentity()
				check("resummoned copy has behaviour and stats", e and e._tameful_attitude == "aggressive" and e._tameful_range == 24 and e._tameful_stats ~= nil and e.damage == 4 and e.order == "relax",
					e and (tostring(e._tameful_attitude) .. " " .. tostring(e.damage) .. " " .. tostring(e.order)))
				check("targeting rule present on the copy", e and e._targeting_rules and e._targeting_rules[1] == tameful.target_rule)
				storage:set_int("phase", 0)
				log("PERSIST_DONE")
				core.request_shutdown("done", false, 1)
			end)
		end)
	end)
end
