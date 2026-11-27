local function log(s) core.log("action", "[DG_PORTAL_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
local forms = {}
local orig_show = core.show_formspec
core.show_formspec = function(n, f, s) forms[#forms + 1] = f; return orig_show(n, f, s) end
local function last_form() return forms[#forms] end
local function fields(player, form, f) for _, cb in ipairs(core.registered_on_player_receive_fields) do cb(player, form, f) end end
local function wait(cond, cb, tries) tries = tries or 60; if cond() then return cb() end
	if tries <= 0 then check("wait timed out", false); return cb() end
	core.after(0.25, function() wait(cond, cb, tries - 1) end) end
local function run_count() local n = 0; for _ in pairs(dungeoneer.runs()) do n = n + 1 end; return n end
local function portal_nodes(o) local n = 0; for i = 0, 1 do for j = 0, 1 do local nm = core.get_node(vector.new(o.x + i, o.y + j, o.z)).name; if nm:find("dungeoneer:portal") then n = n + 1 end end end; return n end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(14, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true })
		local inv = player:get_inventory()
		-- recipes
		local function craft(items) local out = core.get_craft_result({ method = "normal", width = 3, items = items }); return out.item:to_string() end
		check("frame recipe: ring of 4 stone bricks + 4 obsidian -> 8",
			craft({ "mcl_core:stonebrick", "mcl_core:obsidian", "mcl_core:stonebrick", "mcl_core:obsidian", "", "mcl_core:obsidian", "mcl_core:stonebrick", "mcl_core:obsidian", "mcl_core:stonebrick" }) == "dungeoneer:frame 8")
		check("keys have no crafting recipe any more", craft({ "mcl_core:iron_ingot", "mcl_core:gold_ingot" }) == "" and craft({ "dungeoneer:key_1", "mcl_core:diamond" }) == "")

		-- a portal ring in the air above the dev world: opening lower corner o, plane x/y at z = o.z
		local o = { x = 40, y = 20, z = 40 }
		mv.go(player, { x = 40, y = 17, z = 36 }, { remember = false }, function()
			core.emerge_area(vector.offset(o, -4, -4, -4), vector.offset(o, 4, 5, 4), function(_, _, rem)
				if rem > 0 then return end
				for x = -2, 3 do for y = -2, 3 do core.set_node(vector.new(o.x + x, o.y + y, o.z), { name = "air" }) end end
				for i = -1, 2 do for j = -1, 2 do
					local corner = (i == -1 or i == 2) and (j == -1 or j == 2); local opening = i >= 0 and i <= 1 and j >= 0 and j <= 1
					if not corner and not opening then core.set_node(vector.new(o.x + i, o.y + j, o.z), { name = "dungeoneer:frame" }) end
				end end
				check("ring found from a frame block", dungeoneer.find_portal(vector.new(o.x - 1, o.y, o.z)) ~= nil)
				check("ring found from another side (top frame)", dungeoneer.find_portal(vector.new(o.x, o.y + 2, o.z)) ~= nil)
				core.set_node(vector.new(o.x + 1, o.y + 2, o.z), { name = "air" })
				check("missing frame block: no portal", dungeoneer.find_portal(vector.new(o.x, o.y + 2, o.z)) == nil)
				core.set_node(vector.new(o.x + 1, o.y + 2, o.z), { name = "dungeoneer:frame" })

				-- key I on the frame: consumed, run built, portal lit
				local key = ItemStack("dungeoneer:key_1 3")
				local runs0 = run_count()
				local res = core.registered_items["dungeoneer:key_1"].on_place(key, player, { type = "node", under = vector.new(o.x - 1, o.y, o.z), above = vector.new(o.x - 2, o.y, o.z) })
				check("key used up (3 -> 2)", res:get_count() == 2, tostring(res:get_count()))
				wait(function() return portal_nodes(o) == 4 end, function()
					check("opening lit (4 portal nodes)", portal_nodes(o) == 4)
					check("one new run, tier 1", run_count() == runs0 + 1)
					local run1; for _, r in pairs(dungeoneer.runs()) do run1 = r end
					check("run knows its portal", run1.portal and run1.portal.axis == "x" and run1.portal.origin.y == o.y)
					check("portal cell stores the run id", core.get_meta(vector.new(o.x, o.y, o.z)):get_int("dungeoneer_run") == run1.id)
					-- step into the portal from the -z side: window appears
					local n0 = #forms
					player:set_pos({ x = o.x + 0.5, y = o.y, z = o.z - 0.2 })
					wait(function() return last_form() == "dungeoneer:window" and #forms > n0 end, function()
						check("stepping in opens the window", last_form() == "dungeoneer:window")
						-- cancel: no second window while still standing in it
						fields(player, "dungeoneer:window", { cancel = "true", quit = "true" })
						local n1 = #forms
						core.after(1.0, function()
							check("cancel: not asked again while inside the portal", #forms == n1)
							-- step out and in again: asked again
							player:set_pos({ x = o.x + 0.5, y = o.y, z = o.z - 3 })
							core.after(0.8, function()
								player:set_pos({ x = o.x + 0.5, y = o.y, z = o.z - 0.2 })
								wait(function() return #forms > n1 end, function()
									check("step out and in: asked again", last_form() == "dungeoneer:window")
									-- Enter
									fields(player, "dungeoneer:window", { enter = "true" })
									wait(function() return mcl_worlds.pos_to_dimension(player:get_pos()) == "dungeon" end, function()
										check("Enter: player is in the dungeon dimension", mcl_worlds.pos_to_dimension(player:get_pos()) == "dungeon")
										local rp = mv.return_point("tester")
										check("return point: just outside the portal on the side we came from, ~1.8 away", rp and math.abs(rp.pos.z - (o.z - 1.8)) < 0.1 and rp.pos.y == o.y and math.abs(rp.yaw - math.pi) < 0.01, rp and core.write_json(rp))
										check("run has somebody inside", #dungeoneer.players_inside(run1) == 1)
										-- key while somebody is inside: nothing happens, key kept
										local k2 = ItemStack("dungeoneer:key_2")
										local r2 = core.registered_items["dungeoneer:key_2"].on_place(k2, player, { type = "node", under = vector.new(o.x - 1, o.y, o.z), above = vector.new(o.x - 2, o.y, o.z) })
										check("key with somebody inside: kept, dungeon unchanged", r2:get_count() == 1 and run_count() == runs0 + 1 and dungeoneer.runs()[tostring(run1.id)] ~= nil)
										-- reset is refused while inside (the Reset button comes back to the window)
										-- (the player is inside the dungeon, so the portal window is not opened here; call the handler as if it were)
										-- leave, then check timers and replacing
										-- the exit portal in the start room: Stay, then Leave
										local lay = dungeoneer.run_layout(run1)
										local sminp = mv.slot_area("dungeon", run1.slot)
										local ex = vector.new(sminp.x + lay.exits.start.x, sminp.y + lay.exits.start.y, sminp.z + lay.exits.start.z)
										check("exit portal lit in the start room (4 nodes with the exit flag)", core.get_node(ex).name == "dungeoneer:portal_x" and core.get_meta(ex):get_int("dungeoneer_exit") == 1 and core.get_node(vector.offset(ex, 1, 1, 0)).name == "dungeoneer:portal_x")
										check("exit ring is unbreakable bricks", core.get_node(vector.offset(ex, -1, 0, 0)).name == "dungeoneer:brick" and core.get_node(vector.offset(ex, 0, 2, 0)).name == "dungeoneer:brick")
										local bex = vector.new(sminp.x + lay.exits.boss.x, sminp.y + lay.exits.boss.y, sminp.z + lay.exits.boss.z)
										check("exit portal lit in the boss room too", core.get_node(bex).name == "dungeoneer:portal_x" and core.get_meta(bex):get_int("dungeoneer_exit") == 1)
										local nf = #forms
										player:set_pos(ex)
										wait(function() return #forms > nf and last_form() == "dungeoneer:exit" end, function()
											check("exit portal: Leave/Stay window", last_form() == "dungeoneer:exit")
											fields(player, "dungeoneer:exit", { stay = "true", quit = "true" })
											local nf2 = #forms
											core.after(1.0, function()
												check("Stay: not asked again while standing in it", #forms == nf2 and mcl_worlds.pos_to_dimension(player:get_pos()) == "dungeon")
												player:set_pos(vector.offset(ex, 0, 0, -3))
												core.after(0.8, function()
													player:set_pos(ex)
													wait(function() return #forms > nf2 end, function()
														check("step out and in: asked again", last_form() == "dungeoneer:exit")
														fields(player, "dungeoneer:exit", { leave = "true" })
														wait(function() return mcl_worlds.pos_to_dimension(player:get_pos()) ~= "dungeon" end, function()
															check("back: outside, near the portal", mcl_worlds.pos_to_dimension(player:get_pos()) ~= "dungeon" and math.abs(player:get_pos().z - (o.z - 1.8)) < 1.5, core.pos_to_string(player:get_pos(), 1))
											check("nobody inside now", #dungeoneer.players_inside(run1) == 0)
											-- key II on the lit portal with nobody inside replaces the dungeon
											local r3 = core.registered_items["dungeoneer:key_2"].on_place(ItemStack("dungeoneer:key_2"), player, { type = "node", under = vector.new(o.x - 1, o.y, o.z), above = vector.new(o.x - 2, o.y, o.z) })
											check("replace: key used up", r3:get_count() == 0)
											wait(function() local r; for _, x in pairs(dungeoneer.runs()) do r = x end; return r and r.id ~= run1.id and r.portal end, function()
												local run2; for _, x in pairs(dungeoneer.runs()) do run2 = x end
												check("replace: new run of tier 2, old one gone", run2.tier == 2 and run2.id ~= run1.id and run_count() == runs0 + 1 and dungeoneer.runs()[tostring(run1.id)] == nil)
												check("portal lit with the new run", portal_nodes(o) == 4 and core.get_meta(vector.new(o.x, o.y, o.z)):get_int("dungeoneer_run") == run2.id)
												-- the empty timer: pretend it has been empty for 11 minutes
												dungeoneer.empty_since[run2.id] = os.time() - 11 * 60
												wait(function() return run_count() == runs0 end, function()
													check("empty timer: run removed", run_count() == runs0)
													check("empty timer: portal out, frame stays", portal_nodes(o) == 0 and core.get_node(vector.new(o.x - 1, o.y, o.z)).name == "dungeoneer:frame")
													check("slot freed", next(mv.slot_used("dungeon")) == nil)
													-- light again, then break a frame: portal closes, empty run removed at once
													local r4 = core.registered_items["dungeoneer:key_1"].on_place(ItemStack("dungeoneer:key_1"), player, { type = "node", under = vector.new(o.x - 1, o.y, o.z), above = vector.new(o.x - 2, o.y, o.z) })
													wait(function() return portal_nodes(o) == 4 end, function()
														-- Reset flow: step in, Reset -> confirm, Back -> window, Reset + Really -> gone, frame stays
														player:set_pos({ x = o.x + 0.5, y = o.y, z = o.z - 3 })
														core.after(0.8, function()
															local nr = #forms
															player:set_pos({ x = o.x + 0.5, y = o.y, z = o.z - 0.2 })
															wait(function() return #forms > nr and last_form() == "dungeoneer:window" end, function()
																fields(player, "dungeoneer:window", { reset = "true" })
																check("Reset asks again first (confirm window)", last_form() == "dungeoneer:confirm")
																fields(player, "dungeoneer:confirm", { back = "true" })
																check("Back returns to the window, dungeon still there", last_form() == "dungeoneer:window" and run_count() == runs0 + 1)
																fields(player, "dungeoneer:window", { reset = "true" })
																fields(player, "dungeoneer:confirm", { really = "true" })
																wait(function() return run_count() == runs0 end, function()
																check("Really: dungeon removed", run_count() == runs0 and next(mv.slot_used("dungeon")) == nil)
																check("Really: portal out, frame stays", portal_nodes(o) == 0 and core.get_node(vector.new(o.x - 1, o.y, o.z)).name == "dungeoneer:frame")
																-- light again and break a frame
																core.registered_items["dungeoneer:key_1"].on_place(ItemStack("dungeoneer:key_1"), player, { type = "node", under = vector.new(o.x - 1, o.y, o.z), above = vector.new(o.x - 2, o.y, o.z) })
																wait(function() return portal_nodes(o) == 4 end, function()
																	core.remove_node(vector.new(o.x - 1, o.y + 1, o.z))
																	wait(function() return run_count() == runs0 end, function()
																		check("frame broken: portal closed", portal_nodes(o) == 0)
																		check("frame broken: empty dungeon removed at once", run_count() == runs0 and next(mv.slot_used("dungeon")) == nil)
																		log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
																		log("SCENARIO_DONE"); core.request_shutdown("done")
																	end)
																end)
																end, 80)
															end)
														end)
														do return end
														core.remove_node(vector.new(o.x - 1, o.y + 1, o.z))
														wait(function() return run_count() == runs0 end, function()
															check("frame broken: portal closed", portal_nodes(o) == 0)
															check("frame broken: empty dungeon removed at once", run_count() == runs0 and next(mv.slot_used("dungeon")) == nil)
															log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
															log("SCENARIO_DONE"); core.request_shutdown("done")
														end)
													end)
												end, 100)
											end, 80)
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
				end, 80)
			end)
		end)
	end)
end)
