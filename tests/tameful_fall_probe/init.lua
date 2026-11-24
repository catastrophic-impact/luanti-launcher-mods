local function log(s) core.log("action", "[TFP_TEST] NOTE " .. s) end
local function deliver(player, form, fields) for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end end
local function tame(player, kind, pos)
	local o = core.add_entity(pos, kind); local e = o:get_luaentity()
	player:get_inventory():add_item("main", "tameful:lead 1"); player:set_wielded_item(ItemStack("tameful:lead"))
	player:set_pos(vector.offset(pos, 2, 0, 0))
	e.on_rightclick(e, player)
	deliver(player, "tameful:tame", { yes = "true" }); core.close_formspec("tester", "tameful:tame")
	return o, e
end
local function run(player, kind, x0, gy, done)
	-- platform 14 blocks up, 5x5, ride off its +x edge
	local P = vector.new(x0, gy + 14, 0)
	for x = -2, 2 do for z = -2, 2 do core.set_node(vector.offset(P, x, 0, z), { name = "mcl_core:stone" }) end end
	local obj, e = tame(player, kind, vector.offset(P, -1, 1.2, 0))
	core.after(1.5, function()
		player:set_pos(vector.offset(obj:get_pos(), 1.0, 0, 0))
		tameful.ride(e, player)
		tameful._ride_input = { forward = true }
		player:set_look_horizontal(-math.pi / 2)
		local samples, t = {}, 0
		local function step()
			t = t + 0.1
			local v = obj:get_velocity(); local p = obj:get_pos()
			if p and p.y < P.y + 0.9 then samples[#samples + 1] = v.y end
			if t > 4 then
				tameful._ride_input = nil
				local mn, sum = 0, 0
				for _, y in ipairs(samples) do mn = math.min(mn, y); sum = sum + y end
				log(string.format("%s airborne samples %d, fastest fall %.2f, mean %.2f, ended y %.1f (floor y %d)", kind, #samples, mn, #samples > 0 and sum / #samples or 0, obj:get_pos().y, gy))
				tameful.untame(e); obj:remove()
				return done()
			end
			core.after(0.1, step)
		end
		step()
	end)
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local gy = vector.round(player:get_pos()).y - 1
		run(player, "mobs_mc:cow", 20, gy, function()
			run(player, "mobs_mc:chicken", 40, gy, function() log("SCENARIO_DONE"); core.request_shutdown("done") end)
		end)
	end)
end)
