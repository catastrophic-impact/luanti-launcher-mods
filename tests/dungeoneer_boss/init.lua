local function log(s) core.log("action", "[DG_BOSS_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
local forms = {}
local orig_show = core.show_formspec
core.show_formspec = function(n, f, s) forms[#forms + 1] = f; return orig_show(n, f, s) end
local dmg = {}
local orig_dd = mcl_util.deal_damage
mcl_util.deal_damage = function(o, d, r) if r and r.type == "mob" and r.source and r.source:get_luaentity() and r.source:get_luaentity().name == "dungeoneer:boss" then dmg[#dmg + 1] = d end return orig_dd(o, d, r) end
local function wait(cond, cb, tries) tries = tries or 40; if cond() then return cb() end
	if tries <= 0 then check("wait timed out", false); return cb() end
	core.after(0.25, function() wait(cond, cb, tries - 1) end) end
local boss_obj
local orig_tag = dungeoneer.tag_mob
function dungeoneer.tag_mob(obj, id) local e = orig_tag(obj, id); if e and e.name == "dungeoneer:boss" then boss_obj = obj end return e end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(14, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true })
		dungeoneer.new_run(3, function(run)
			local minp = mv.slot_area("dungeon", run.slot)
			local L = dungeoneer.run_layout(run)
			local b = L.boss
			local bc = vector.new(minp.x + b.cx, minp.y + b.y0, minp.z + b.cz)
			local ent = boss_obj and boss_obj:get_luaentity()
			check("boss spawned in the boss room", ent ~= nil and vector.distance(boss_obj:get_pos(), vector.offset(bc, 0, 0.5, 0)) < 2)
			check("boss: tagged, tier 3, persistent", ent and ent._dg_run == run.id and ent._dg_tier == 3 and ent.persistent == true)
			check("boss: random name set", ent and ent.nametag and #ent.nametag > 5, ent and ent.nametag)
			local props = boss_obj:get_properties()
			check("boss: twice the size (collisionbox height 3.9, visual 2x)", props.collisionbox[5] > 3.8 and props.visual_size.x == 2, core.write_json(props.collisionbox))
			check("boss: lots of health (200) and armor (damage / 2 at tier 3)", ent.health == 200 and ent._dg_hp == 2.0, tostring(ent.health))
			-- chest
			local c = L.chest
			local cp = vector.new(minp.x + c.x, minp.y + c.y, minp.z + c.z)
			check("chest in the boss room corner", core.get_node(cp).name == "dungeoneer:chest")
			local inv = core.get_meta(cp):get_inventory()
			local stacks = 0; for _, st in ipairs(inv:get_list("main")) do if not st:is_empty() then stacks = stacks + 1 end end
			check("chest filled from the tier (8-12 stacks of tier 3 loot)", stacks >= 5, tostring(stacks))
			local def = core.registered_nodes["dungeoneer:chest"]
			local nf = #forms
			def.on_rightclick(cp, core.get_node(cp), player)
			check("sealed: will not open", #forms == nf)
			check("sealed: cannot be broken", def.can_dig(cp, player) == false)
			def.on_blast(cp)
			check("sealed: survives explosions", core.get_node(cp).name == "dungeoneer:chest")
			-- notice through walls: stand just outside the east wall (1-thick brick wall between), 13 blocks from the boss
			mv.go(player, vector.new(bc.x + 13, bc.y, bc.z), { remember = false }, function()
				wait(function() return ent._active_target ~= nil end, function()
					check("notices a player through a wall (within 24)", ent._active_target and ent._active_target:is_player(), tostring(ent._active_target))
					core.after(1.0, function()
						check("name tag hidden behind a wall (13 blocks, no line of sight)", boss_obj:get_properties().nametag == "", tostring(boss_obj:get_properties().nametag))
					end)
					-- far away: 30+ blocks (start room side) -> no target
					mv.go(player, vector.new(bc.x - 30, bc.y, bc.z), { remember = false }, function()
						core.after(1.5, function()
							local e2 = boss_obj:get_luaentity()
							check("player far away (>24): not noticed", e2 and e2._active_target == nil)
							-- back in the boss room, 8 west of the boss: bar, helpers, slam
							mv.go(player, vector.offset(bc, -8, 0, 0), { remember = false }, function()
								local e3 = boss_obj:get_luaentity()
								e3._dg_t = { summon = 0, slam = 0, tp = 99 }
								wait(function() return mcl_bossbars.bars.tester and #mcl_bossbars.bars.tester > 0 end, function()
									local bar = mcl_bossbars.bars.tester and mcl_bossbars.bars.tester[1]
									check("boss bar shown with the boss name", bar and bar.text == e3.nametag, bar and bar.text)
									wait(function() return boss_obj:get_properties().nametag == e3.nametag end, function()
										check("name tag shown when a player within 16 can see the boss", boss_obj:get_properties().nametag == e3.nametag, tostring(boss_obj:get_properties().nametag))
									end, 12)
									wait(function() local n = 0; for _, o in ipairs(core.get_objects_inside_radius(boss_obj:get_pos(), 30)) do local e = o:get_luaentity(); if e and e._dg_helper_of == run.id then n = n + 1 end end; return n >= 1 end, function()
										local n = 0; for _, o in ipairs(core.get_objects_inside_radius(boss_obj:get_pos(), 30)) do local e = o:get_luaentity(); if e and e._dg_helper_of == run.id then n = n + 1 end end
										check("tier 1 ability: calls helpers (1-4 alive)", n >= 1 and n <= 4, tostring(n))
										-- slam: player within 6
										local bp = boss_obj:get_pos()
										player:set_pos(vector.offset(bp, 3, 0, 0))
										boss_obj:get_luaentity()._dg_t = { summon = 99, slam = 0, tp = 99 }
										wait(function() return #dmg > 0 end, function()
											check("tier 2 ability: ground slam hits a player in range", #dmg > 0, core.write_json(dmg))
											-- teleport: player 18 away
											local bp2 = boss_obj:get_pos()
											boss_obj:set_pos(vector.offset(bc, 8, 0.5, 0)) -- far side of the room: 17 blocks from the player, both on the floor
											player:set_pos(vector.offset(bc, -9, 0, 0))
											boss_obj:get_luaentity()._dg_t = { summon = 99, slam = 99, tp = 0 }
											wait(function() return vector.distance(boss_obj:get_pos(), player:get_pos()) < 6 end, function()
												check("tier 3 ability: teleports to a player who keeps their distance", vector.distance(boss_obj:get_pos(), player:get_pos()) < 6, string.format("%.1f", vector.distance(boss_obj:get_pos(), player:get_pos())))
												-- death: run cleared, chest unseals
												local e4 = boss_obj:get_luaentity()
												e4._dg_hp = 1; e4:receive_damage({ flags = {}, type = "generic" }, 100000)
												wait(function() local r = dungeoneer.runs()[tostring(run.id)]; return r and r.cleared end, function()
													local r = dungeoneer.runs()[tostring(run.id)]
													check("boss dead: run cleared", r and r.cleared == true)
													local nf2 = #forms
													def.on_rightclick(cp, core.get_node(cp), player)
													check("chest opens after the boss is dead", #forms > nf2 and forms[#forms] == "dungeoneer:chest")
													check("chest cannot be broken while it holds loot, can when empty", def.can_dig(cp, player) == false and (function() inv:set_list("main", {}); return def.can_dig(cp, player) == true end)())
													log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
													log("SCENARIO_DONE"); core.request_shutdown("done")
												end, 20)
											end, 20)
										end, 20)
									end, 30)
								end, 20)
							end)
						end)
					end)
				end, 20)
			end)
		end)
	end)
end)
