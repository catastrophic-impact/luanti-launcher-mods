local function log(s) core.log("action", "[ID_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function plain(s) return (core.get_translated_string("en", s or ""):gsub("\27", "")) end
local function lines_text(info) local t = { plain(info.title) }; for _, l in ipairs(info.lines) do t[#t + 1] = plain(l.text) end return table.concat(t, " | ") end
local function look(player, from, to) -- stand at `from` and look at `to`
	player:set_pos(vector.offset(from, 0, -1.47, 0))
	local d = vector.direction(from, to)
	player:set_look_horizontal(math.atan2(-d.x, d.z)); player:set_look_vertical(-math.asin(d.y))
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(16, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		mcl_gamemode.set_gamemode(player, "survival")
		local cfg = identifiable.get(player)
		local base = vector.round(player:get_pos())
		local O = vector.offset(base, 0, 30, 0) -- a room in the air so nothing interferes
		local function fill(x0, y0, z0, x1, y1, z1, name) for x = x0, x1 do for y = y0, y1 do for z = z0, z1 do core.set_node(vector.offset(O, x, y, z), { name = name }) end end end end
		-- sealed 7x4x7 room: stone walls, dark
		fill(-4, -1, -4, 4, 5, 4, "mcl_core:stone"); fill(-3, 0, -3, 3, 3, 3, "air")
		core.emerge_area(vector.offset(O, -6, -3, -6), vector.offset(O, 6, 8, 6))
		core.after(3, function()
			local eye = vector.offset(O, 0, 1.47 + 0.0, 0) -- player stands on the floor (y = O.y)
			-- 1. through water: a source block between us and a stone wall
			core.set_node(vector.offset(O, 0, 1, 2), { name = "mcl_core:water_source" })
			core.set_node(vector.offset(O, 0, 1, 3), { name = "mcl_core:stone" }) -- wall is at z=3 (room edge), water in front
			cfg.range = 10
			look(player, vector.offset(O, 0, 1.47, 0), vector.offset(O, 0, 1, 3))
			local t = identifiable.find_target(player, 10, cfg)
			check("through water: the stone behind is named", t and t.kind == "node" and t.node.name == "mcl_core:stone", t and t.node and t.node.name)
			-- water alone (nothing behind): remove the wall inside the room (open the +z side: air 'beyond' is the room edge stone... use a pool in the middle)
			core.set_node(vector.offset(O, 0, 1, 3), { name = "mcl_core:water_source" })
			local t2 = identifiable.find_target(player, 2.9, cfg) -- shorter than the wall: only water in reach
			check("only water in reach: the liquid is named", t2 and t2.kind == "node" and t2.node.name == "mcl_core:water_source", t2 and t2.node and t2.node.name)
			core.set_node(vector.offset(O, 0, 1, 2), { name = "air" }); core.set_node(vector.offset(O, 0, 1, 3), { name = "mcl_core:stone" })

			-- 2. spawnable: dark room floor yes, torch-lit no, lit by sky (not applicable inside): at night dark
			cfg.show_spawnable = true; cfg.light_mode = "both"
			local floor_target = { pointed = { under = vector.offset(O, 1, -1, 1), above = vector.offset(O, 1, 0, 1) }, node = core.get_node(vector.offset(O, 1, -1, 1)), kind = "node" }
			local info = identifiable.describe(player, floor_target, cfg)
			local txt = lines_text(info)
			check("dark sealed room floor: Spawnable", txt:find("Spawnable", 1, true) ~= nil, txt)
			core.set_node(vector.offset(O, 1, 1, 1), { name = "mcl_torches:torch", param2 = 1 })
			core.after(1.5, function()
				local txt2 = lines_text(identifiable.describe(player, floor_target, cfg))
				check("torch nearby: not Spawnable (block light)", txt2:find("Spawnable", 1, true) == nil, txt2)
				-- daylight spot outdoors never counts at noon
				core.set_timeofday(0.5)
				local g = vector.offset(base, 0, -1, 0)
				local out = { pointed = { under = g, above = vector.offset(g, 0, 1, 0) }, node = core.get_node(g), kind = "node" }
				check("open sky at noon: not Spawnable", lines_text(identifiable.describe(player, out, cfg)):find("Spawnable", 1, true) == nil)

				-- 3. villager job + tier; items; invisible
				local v_o = core.add_entity(vector.offset(O, -2, 0.5, -2), "mobs_mc:villager")
				core.after(1.0, function()
					local v = v_o:get_luaentity()
					v._profession = "librarian"; v._tier = 4
					local vi = identifiable.describe(player, { kind = "entity", obj = v_o, ent = v }, cfg)
					check("villager: Librarian · Expert", lines_text(vi):find("Librarian · Expert", 1, true) ~= nil, lines_text(vi))
					v._profession = "nitwit"
					check("nitwit just says Nitwit", lines_text(identifiable.describe(player, { kind = "entity", obj = v_o, ent = v }, cfg)):find("Nitwit", 1, true) ~= nil)
					v_o:remove()
					local it_o = core.add_item(vector.offset(O, 0, 1.0, -2), "mcl_core:diamond 3")
					core.after(0.5, function()
						local ii = identifiable.describe(player, { kind = "item", obj = it_o, ent = it_o:get_luaentity() }, cfg)
						check("item: name and count", plain(ii.title):find("×3", 1, true) ~= nil, plain(ii.title))
						look(player, vector.offset(O, 0, 1.47, 1.5), it_o:get_pos())
						check("items on: the dropped item is found", (identifiable.find_target(player, 5, cfg) or {}).kind == "item")
						cfg.show_items = false
						local t3 = identifiable.find_target(player, 5, cfg)
						check("items off: no panel for it (looks behind)", not t3 or t3.kind ~= "item")
						cfg.show_items = true
						it_o:remove()
						-- invisible entity never shown
						local inv_o = core.add_entity(vector.offset(O, 0, 0.5, -2), "mobs_mc:cow")
						core.after(0.6, function()
							inv_o:set_properties({ is_visible = false })
							look(player, vector.offset(O, 0, 1.47, 1.5), vector.offset(O, 0, 1, -2))
							local t4 = identifiable.find_target(player, 6, cfg)
							check("invisible creature is not shown", not t4 or t4.kind ~= "entity", t4 and t4.kind)
							inv_o:remove()

							-- 4. blacklist command through the live panel
							look(player, vector.offset(O, 0, 1.47, 0), vector.offset(O, 2, 0, 3))
							core.after(0.5, function()
								core.registered_chatcommands.idblacklist.func("tester", "")
								core.after(0.4, function()
									local h = identifiable.hud(player)
									local first = player:hud_get(h.lines[1])
									check("blacklisted: panel says Hidden", first and plain(first.text):find("Hidden", 1, true) ~= nil, first and plain(first.text))
									core.registered_chatcommands.idblacklist.func("tester", "")
									core.after(0.4, function()
										local first2 = player:hud_get(h.lines[1])
										check("blacklist toggled off: shown again", first2 and plain(first2.text):find("Block", 1, true) ~= nil, first2 and plain(first2.text))
										core.registered_chatcommands.idhide.func("tester", "")
										core.after(0.4, function()
											check("hide key: panel text empty", plain(player:hud_get(h.lines[1]).text) == "")
											core.registered_chatcommands.idhide.func("tester", "")
											-- settings screen fields
											for _, f in ipairs(core.registered_on_player_receive_fields) do f(player, "identifiable:cfg", { show_id = "false", b_color = "x" }) end
											check("settings: toggle + colour cycle saved", cfg.show_id == false and cfg.hud_color == "yellow")
											for _, f in ipairs(core.registered_on_player_receive_fields) do f(player, "identifiable:cfg", { reset = "x" }) end
											check("reset restores defaults", cfg.show_id == true and cfg.hud_color == "white")
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
