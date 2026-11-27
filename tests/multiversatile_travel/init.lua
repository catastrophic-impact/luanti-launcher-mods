local function log(s) core.log("action", "[MV_TRAVEL_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(14, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true, creative = true })
		local g = mv.gaps(); local gap = g[#g - 1]
		check("register transient dim", mv.register{ name = "traveldim", transient = true, ymin = gap.ymin + 200, ymax = gap.ymin + 599,
			look = { sky = { type = "plain", base_color = "#445566", clouds = false } } } == nil)
		local ow = mv.get("overworld")
		local home = { x = 7, y = ow.build_max - 40, z = 5 }
		player:set_pos(home)
		core.after(2, function()
			local start = player:get_pos()
			mv.clear_return_point("tester")
			check("no return point at first", mv.return_point("tester") == nil)
			local target = { x = 100, y = gap.ymin + 300, z = 100 }
			mv.go(player, target, { yaw = 1.0 }, function(ok)
				check("go: callback ok", ok)
				local p = player:get_pos()
				check("go: player arrived", math.abs(p.x - 100) < 3 and math.abs(p.z - 100) < 3 and math.abs(p.y - target.y) < 30, core.pos_to_string(p, 0))
				check("go: now in traveldim", mcl_worlds.pos_to_dimension(p) == "traveldim")
				check("look applied at once (no 1 s wait)", player:get_sky(true).type == "plain" and player:get_sky(true).base_color.r == 0x44)
				local rp = mv.return_point("tester")
				check("return point saved: overworld, where we stood", rp and rp.dim == "overworld" and math.abs(rp.pos.x - start.x) < 0.1 and math.abs(rp.pos.y - start.y) < 0.1, rp and core.write_json(rp))
				-- a second hop inside the same trip with keep = true must not overwrite it
				mv.go(player, { x = 140, y = gap.ymin + 300, z = 100 }, { keep = true }, function()
					local rp2 = mv.return_point("tester")
					check("keep: return point unchanged", rp2 and math.abs(rp2.pos.x - start.x) < 0.1)
					-- login while inside a transient dimension: put back
					mv.handle_login(player, function()
						local p2 = player:get_pos()
						check("login inside transient dim: put back at the return point", math.abs(p2.x - start.x) < 2 and math.abs(p2.y - start.y) < 3, core.pos_to_string(p2, 0))
						check("return point cleared after back", mv.return_point("tester") == nil)
						check("sky back to Mineclonia's", player:get_sky(true).type ~= "plain" or player:get_sky(true).base_color.r ~= 0x44)
						-- back without a return point: spawn
						mv.go(player, target, { remember = false }, function()
							check("remember=false: no point saved", mv.return_point("tester") == nil)
							mv.back(player, nil, function(ok)
								local p3 = player:get_pos()
								check("back with no point: arrives at spawn, outside traveldim", ok and mcl_worlds.pos_to_dimension(p3) ~= "traveldim", core.pos_to_string(p3, 0))
								log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
								log("SCENARIO_DONE"); core.request_shutdown("done")
							end)
						end)
					end)
				end)
			end)
		end)
	end)
end)
