local function log(s) core.log("action", "[MOBCRATE_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
local EMPTY, FULL = "mobcrate:crate_empty", "mobcrate:crate_full"

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local inv = player:get_inventory()
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local function spawn(kind, dx, dz) return core.add_entity(vector.offset(base, dx, 0, dz or 0), "mobs_mc:" .. kind) end
		local function hold(stack) player:set_wielded_item(ItemStack(stack)) end
		local function count_full() local n = 0; for _, st in ipairs(inv:get_list("main")) do if st:get_name() == FULL then n = n + 1 end end return n end
		local function count_mobs(kind, r) local n = 0; for _, o in ipairs(core.get_objects_inside_radius(base, r or 30)) do local e = o:get_luaentity(); if e and e.name == "mobs_mc:" .. kind then n = n + 1 end end return n end
		local function pointed(dx, dz) -- a node face on the ground in front
			local under = vector.offset(base, dx, -1, dz)
			return { type = "node", under = under, above = vector.offset(under, 0, 1, 0) }
		end

		-- 1. capture + release round trip keeps health and name
		inv:set_list("main", {})
		local cow_o = spawn("cow", 3)
		core.after(0.7, function()
			local cow = cow_o:get_luaentity()
			cow.health = 7; cow.nametag = "Bessie"
			hold(EMPTY .. " 3")
			check("recipe: 9 planks make a crate", core.get_craft_result({ method = "normal", width = 3, items = { "mcl_core:wood", "mcl_core:wood", "mcl_core:wood", "mcl_core:wood", "mcl_core:wood", "mcl_core:wood", "mcl_core:wood", "mcl_core:wood", "mcl_core:wood" } }).item:get_name() == EMPTY)
			check("recipe: mixed planks too", core.get_craft_result({ method = "normal", width = 3, items = { "mcl_core:wood", "mcl_core:birchwood", "mcl_core:sprucewood", "mcl_core:wood", "mcl_core:wood", "mcl_core:junglewood", "mcl_core:wood", "mcl_core:wood", "mcl_core:acaciawood" } }).item:get_name() == EMPTY)
			cow.on_rightclick(cow, player) -- right-click with a stack of 3 empty crates
			check("cow is out of the world", not cow_o:is_valid() and count_mobs("cow") == 0)
			check("stack of 3: 2 empty left in hand, 1 full in inventory", player:get_wielded_item():get_name() == EMPTY and player:get_wielded_item():get_count() == 2 and count_full() == 1)
			local full
			for _, st in ipairs(inv:get_list("main")) do if st:get_name() == FULL then full = st end end
			local desc = core.get_translated_string("en", full:get_meta():get_string("description"))
			check("full crate shows contents and health", desc:find("Contains", 1, true) and desc:find("Bessie", 1, true) and desc:find("7/", 1, true) ~= nil and desc:find("Cow", 1, true) ~= nil, (desc:gsub("\n", "|")))
			-- survives being stored as a string (inventory save / chest)
			local reloaded = ItemStack(full:to_string())
			check("crate data survives to_string", reloaded:get_meta():get_string("data") ~= "" and reloaded:get_meta():get_string("mob") == "mobs_mc:cow")
			local res = core.registered_items[FULL].on_place(reloaded, player, pointed(4, 0))
			check("release gives back an empty crate", res:get_name() == EMPTY)
			core.after(0.8, function()
				local back
				for _, o in ipairs(core.get_objects_inside_radius(base, 12)) do local e = o:get_luaentity(); if e and e.name == "mobs_mc:cow" then back = e end end
				check("the same cow is back: health 7, name Bessie", back and back.health == 7 and back.nametag == "Bessie", back and (tostring(back.health) .. " " .. tostring(back.nametag)))
				if back then back.object:remove() end

				-- 2. full inventory: the full crate lands on the ground, the mob is not lost
				for i = 1, inv:get_size("main") do inv:set_stack("main", i, ItemStack("mcl_core:stone 64")) end
				local s2 = spawn("sheep", 3)
				core.after(0.7, function()
					hold(EMPTY .. " 2")
					s2:get_luaentity().on_rightclick(s2:get_luaentity(), player)
					local dropped
					for _, o in ipairs(core.get_objects_inside_radius(player:get_pos(), 4)) do local e = o:get_luaentity(); if e and e.name == "__builtin:item" and e.itemstring:find(FULL, 1, true) then dropped = e end end
					check("full inventory: crate dropped at the feet, sheep not lost", dropped ~= nil and not s2:is_valid())
					if dropped then dropped.object:remove() end
					inv:set_list("main", {})

					-- 3. things that must be refused
					hold(EMPTY)
					local ok1 = mobcrate.can_capture(player, player)
					check("a player cannot be crated", ok1 == false)
					local item_o = core.add_item(vector.offset(base, 2, 0, 2), "mcl_core:stone")
					check("dropped item entity refused", mobcrate.can_capture(player, item_o) == false)
					item_o:remove()
					local g = spawn("guardian_elder", 6)
					core.after(0.5, function()
						check("boss refused by default", g:is_valid() and mobcrate.can_capture(player, g) == false)
						deliver(player, "mobcrate:main", { bosses = "true" })
						check("boss allowed after the setting", g:is_valid() and mobcrate.can_capture(player, g) == true)
						deliver(player, "mobcrate:main", { bosses = "false" })
						g:remove()
						local pet_o = spawn("pig", 3)
						core.after(0.5, function()
							local pig = pet_o:get_luaentity()
							pig.tamed = true; pig.owner = "someone_else"
							check("another player's pet refused", mobcrate.can_capture(player, pet_o) == false)
							deliver(player, "mobcrate:main", { others = "true" })
							check("allowed with the setting", mobcrate.can_capture(player, pet_o) == true)
							deliver(player, "mobcrate:main", { others = "false" })
							pig.tamed = false; pig.owner = nil
							deliver(player, "mobcrate:main", { blacklist = "mobs_mc:pig, mobs_mc:cow", save = "x" })
							check("blacklist refuses pig", mobcrate.can_capture(player, pet_o) == false)
							deliver(player, "mobcrate:main", { blacklist = "", save = "x" })
							check("empty blacklist allows again", mobcrate.can_capture(player, pet_o) == true)
							pig.dead = true
							check("dead mob refused", mobcrate.can_capture(player, pet_o) == false)
							pig.dead = nil
							pet_o:remove()

							-- 4. left click works, double capture is safe
							local c2 = spawn("cow", 3)
							core.after(0.5, function()
								hold(EMPTY .. " 2")
								core.registered_items[EMPTY].on_use(player:get_wielded_item(), player, { type = "object", ref = c2 })
								check("left-click captures", not c2:is_valid() and count_full() == 1)
								local ok2 = pcall(function() mobcrate.try_capture(player, c2) end)
								check("capturing the same (gone) mob again is harmless", ok2 and count_full() == 1)
								inv:set_list("main", {})

								-- 5. riders get off
								local p2 = spawn("pig", 3)
								core.after(0.5, function()
									local pe = p2:get_luaentity()
									player:get_inventory():add_item("main", "tameful:lead 1")
									player:set_wielded_item(ItemStack("tameful:lead"))
									pe.on_rightclick(pe, player)
									deliver(player, "tameful:tame", { yes = "true" })
									core.close_formspec("tester", "tameful:tame")
									local id = pe._tameful_id
									tameful.set_attitude(pe, "aggressive")
									tameful.find_record(id).name = "Hamlet"
									player:set_pos(vector.offset(p2:get_pos(), 1, 0, 0))
									tameful.ride(pe, player)
									check("setup: riding", pe.driver == player)
									hold(EMPTY)
									-- wield a crate while mounted: right-click the pig it rides
									pe.on_rightclick(pe, player)
									check("rider lifted off, pig crated", not p2:is_valid() and player:get_attach() == nil)
									local rec = tameful.find_record(id)
									check("pet record kept, last copy saved", rec and rec.snapshot ~= nil and rec.status == "out" and rec.loaded == false)
									-- release: same pet comes back with its Tameful state
									local full
									for _, st in ipairs(inv:get_list("main")) do if st:get_name() == FULL then full = st end end
									core.registered_items[FULL].on_place(full, player, pointed(5, 2))
									core.after(1.2, function()
										local back
										for _, o in ipairs(core.get_objects_inside_radius(base, 15)) do local e = o:get_luaentity(); if e and e._tameful_id == id then back = e end end
										check("released pet is still your pet (id, attitude, name)", back and back.owner == "tester" and back._tameful_attitude == "aggressive" and tameful.find_record(id).name == "Hamlet")
										check("released pet has stats again", back and back._tameful_stats ~= nil and back.damage == 4)
										-- crate it again, stable it from the roster, release the old crate: the stale copy must vanish
										hold(EMPTY)
										back.on_rightclick(back, player)
										for _, st in ipairs(inv:get_list("main")) do if st:get_name() == FULL then full = st end end
										check("stable works for a crated pet (uses the saved copy)", tameful.stable(id, false) == true and tameful.find_record(id).status == "stabled")
										core.registered_items[FULL].on_place(full, player, pointed(5, -2))
										core.after(1.5, function()
											local stale
											for _, o in ipairs(core.get_objects_inside_radius(base, 15)) do local e = o:get_luaentity(); if e and e._tameful_id == id then stale = e end end
											check("crate copy of a stabled pet is deleted when released", stale == nil)
											inv:set_list("main", {})

											-- 6. Populations villager keeps name and family data
											local v_o = spawn("villager", 3)
											core.after(1.5, function()
												local v = v_o:get_luaentity()
												local first = v._pop and v._pop.first
												hold(EMPTY)
												v.on_rightclick(v, player)
												check("villager crated (trading did not open)", not v_o:is_valid())
												for _, st in ipairs(inv:get_list("main")) do if st:get_name() == FULL then full = st end end
												core.registered_items[FULL].on_place(full, player, pointed(4, 3))
												core.after(1.5, function()
													local vv
													for _, o in ipairs(core.get_objects_inside_radius(base, 15)) do local e = o:get_luaentity(); if e and e.name == "mobs_mc:villager" then vv = e end end
													check("villager back with the same name", vv and vv._pop and vv._pop.first == first and first ~= nil, tostring(first))
													if vv then vv.object:remove() end
													inv:set_list("main", {})

													-- 7. release spots: tall mob in a 1-high tunnel is refused, crate kept; tallgrass is replaced
													local gy = base.y
													while gy > base.y - 6 and not (core.registered_nodes[core.get_node({ x = base.x + 10, y = gy, z = base.z }).name] or {}).walkable do gy = gy - 1 end
													for dx = 8, 12 do for dz = -1, 1 do core.set_node({ x = base.x + dx, y = gy + 2, z = base.z + dz }, { name = "mcl_core:stone" }) end end
													local h = spawn("horse", 3)
													core.after(1.0, function()
														hold(EMPTY)
														h:get_luaentity().on_rightclick(h:get_luaentity(), player)
														for _, st in ipairs(inv:get_list("main")) do if st:get_name() == FULL then full = st end end
														local under = { x = base.x + 10, y = gy, z = base.z }
														local before = count_mobs("horse")
														local res = core.registered_items[FULL].on_place(full, player, { type = "node", under = under, above = vector.offset(under, 0, 1, 0) })
														core.after(0.7, function()
															check("tall mob under a low ceiling: refused, crate kept", res:get_name() == FULL and count_mobs("horse") == before, res:get_name() .. " mobs " .. count_mobs("horse") .. " before " .. before .. " full=" .. tostring(full and full:get_name()))
															-- open ground: fine
															local res2 = core.registered_items[FULL].on_place(full, player, pointed(2, 5))
															core.after(0.7, function()
																check("open ground: released", res2:get_name() == EMPTY and count_mobs("horse") == before + 1, res2:get_name() .. " mobs " .. count_mobs("horse") .. " before " .. before)
																for _, o in ipairs(core.get_objects_inside_radius(base, 30)) do local e = o:get_luaentity(); if e and e.name == "mobs_mc:horse" then o:remove() end end
																-- replaceable plant: the mob takes its place
																local tg = vector.offset(base, 2, 0, -5)
																core.set_node(tg, { name = "mcl_flowers:tallgrass" })
																core.set_node(vector.offset(tg, 0, -1, 0), { name = "mcl_core:dirt" })
																local ch = spawn("chicken", 6)
																core.after(0.7, function()
																	hold(EMPTY); ch:get_luaentity().on_rightclick(ch:get_luaentity(), player)
																	for _, st in ipairs(inv:get_list("main")) do if st:get_name() == FULL then full = st end end
																	core.registered_items[FULL].on_place(full, player, { type = "node", under = tg, above = vector.offset(tg, 0, 1, 0) })
																	core.after(0.8, function()
																		local c
																		for _, o in ipairs(core.get_objects_inside_radius(tg, 3)) do local e = o:get_luaentity(); if e and e.name == "mobs_mc:chicken" then c = o end end
																		check("released in place of tall grass, at its height", c and math.abs(c:get_pos().y - tg.y) < 1.2, c and string.format("%.2f vs %d", c:get_pos().y, tg.y))
																		log("SCENARIO_DONE"); core.request_shutdown("done")
																	end)
																end)
															end)
														end)
													end)
												end)
											end)
										end)
									end)
								end)
							end)
						end)
					end)
				end)
			end)
		end)
	end)
end)
