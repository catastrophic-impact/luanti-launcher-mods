local function log(s) core.log("action", "[MV_LOOK_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(14, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true, creative = true })
		local ow = mv.get("overworld")
		local g = mv.gaps(); local gap = g[#g - 1]
		local err = mv.register{ name = "lookdim", ymin = gap.ymin + 200, ymax = gap.ymin + 599,
			look = { sky = { type = "plain", base_color = "#112233", clouds = false }, sun = { visible = false, sunrise_visible = false },
				stars = { visible = false }, clouds = { density = 0 }, lighting = { saturation = 0.25 }, ratio = 0.3 } }
		check("registered with a look", err == nil, tostring(err))
		-- start in the Overworld: record what Mineclonia set
		player:set_pos({ x = 0, y = ow.build_max - 30, z = 0 })
		core.after(2.5, function()
			local before = { sat = player:get_lighting().saturation, sky = player:get_sky(true).type, clouds = player:get_clouds().density, stars = player:get_stars().visible }
			log("NOTE overworld look: saturation=" .. tostring(before.sat) .. " sky=" .. tostring(before.sky) .. " clouds=" .. tostring(before.clouds) .. " stars=" .. tostring(before.stars))
			player:set_pos({ x = 0, y = gap.ymin + 300, z = 0 })
			core.after(3, function()
				local sky = player:get_sky(true)
				check("in lookdim: dimension seen", mcl_worlds.pos_to_dimension(player:get_pos()) == "lookdim", "y=" .. math.floor(player:get_pos().y) .. " want " .. (gap.ymin + 200) .. ".." .. (gap.ymin + 599) .. " hp=" .. player:get_hp())
				check("sky is ours", sky.type == "plain" and sky.base_color.r == 0x11 and sky.base_color.g == 0x22 and sky.base_color.b == 0x33, tostring(sky.type) .. " " .. core.write_json(sky.base_color))
				check("lighting is ours", player:get_lighting().saturation == 0.25, tostring(player:get_lighting().saturation))
				check("clouds are ours", player:get_clouds().density == 0, tostring(player:get_clouds().density))
				check("stars hidden", player:get_stars().visible == false)
				player:set_pos({ x = 0, y = ow.build_max - 30, z = 0 })
				core.after(3, function()
					check("back in overworld: lighting restored", player:get_lighting().saturation == before.sat, tostring(player:get_lighting().saturation))
					check("clouds restored", player:get_clouds().density == before.clouds, tostring(player:get_clouds().density))
					check("sky is Mineclonia's again", player:get_sky(true).type == before.sky, tostring(player:get_sky(true).type))
					check("stars as before", player:get_stars().visible == before.stars)
					log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
					log("SCENARIO_DONE"); core.request_shutdown("done")
				end)
			end)
		end)
	end)
end)
