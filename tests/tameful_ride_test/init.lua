local function log(s) core.log("action", "[TAMEFUL_RIDE_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function f2(n) return string.format("%.2f", n) end
local KINDS = { "cow", "pig", "wolf", "horse", "sheep", "chicken", "rabbit" }

local function tame(player, kind, base)
	local obj = core.add_entity(base, "mobs_mc:" .. kind)
	local ent = obj:get_luaentity()
	player:get_inventory():add_item("main", "tameful:lead 1")
	player:set_wielded_item(ItemStack("tameful:lead"))
	ent.on_rightclick(ent, player)
	for _, f in ipairs(core.registered_on_player_receive_fields) do
		if f(player, "tameful:tame", { yes = "true" }) then break end
	end
	return obj, ent
end

local function run_kind(player, kind, base, done)
	local obj, ent = tame(player, kind, base)
	core.after(2, function()
		player:set_pos(vector.offset(obj:get_pos(), 1.5, 0, 0))
		local want = tameful.mount_speed(ent)
		local ok, why = tameful.ride(ent, player)
		check(kind .. ": ride accepted", ok == true, tostring(why))
		check(kind .. ": player attached, driver set", player:get_attach() == obj and ent.driver == player)
		tameful._ride_input = { forward = true }
		player:set_look_horizontal(-math.pi / 2) -- +x
		local p0 = obj:get_pos()
		core.after(0.6, function() p0 = obj:get_pos() end) -- skip the start-up
		core.after(2.6, function()
			local p1 = obj:get_pos()
			local d = math.sqrt((p1.x - p0.x) ^ 2 + (p1.z - p0.z) ^ 2) / 2.0
			check(kind .. ": speed ~ " .. want .. " b/s", math.abs(d - want) <= want * 0.2, f2(d) .. " b/s")
			-- one-block wall 3 blocks ahead
			local ux, uz = 1, 0
			local gy = math.floor(p1.y + 0.5)
			local walls = {}
			for k = -2, 2 do
				local pos = { x = math.floor(p1.x + 3.5), y = gy, z = math.floor(p1.z + k + 0.5) }
				core.set_node(pos, { name = "mcl_core:stone" }); walls[#walls + 1] = pos
			end
			local y0, peak = p1.y, p1.y
			local t = 0
			local function watch()
				t = t + 0.05; peak = math.max(peak, obj:get_pos().y)
				if t < 2.5 then return core.after(0.05, watch) end
				local p2 = obj:get_pos()
				check(kind .. ": climbs a 1-block step", p2.x > walls[1].x + 0.6 and peak > y0 + 0.5, "x " .. f2(p2.x) .. " wall " .. walls[1].x .. " peak dy " .. f2(peak - y0))
				tameful._ride_input = { forward = false, jump = false }
				for _, w in ipairs(walls) do core.set_node(w, { name = "air" }) end
				-- jump on the spot
				core.after(1, function()
					local py = obj:get_pos().y
					local mx = py
					tameful._ride_input = { forward = false, jump = true }
					local tt = 0
					local function sample()
						tt = tt + 0.05; mx = math.max(mx, obj:get_pos().y)
						if tt < 1.2 then return core.after(0.05, sample) end
						tameful._ride_input = nil
						local want_j = tameful.stats_for(ent.name).jump
						check(kind .. ": jump clears " .. want_j .. " block(s)", mx - py >= want_j and mx - py <= want_j + 0.7, f2(mx - py))
						ent:detach(player, vector.new(0, 0.5, 0))
						core.after(0.5, function()
							check(kind .. ": dismounted, overrides gone", player:get_attach() == nil and ent.driver == nil and ent._tameful_riding == nil and rawget(ent, "apply_driver_input") == nil)
							obj:remove()
							player:set_pos(vector.offset(base, 0, 0, 0))
							done()
						end)
					end
					sample()
				end)
			end
			watch()
		end)
	end)
end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local i = 0
		local function nxt()
			i = i + 1
			if not KINDS[i] then log("SCENARIO_DONE"); return core.request_shutdown("done") end
			local ok, err = pcall(run_kind, player, KINDS[i], base, nxt)
			if not ok then log("FAIL " .. KINDS[i] .. " error: " .. tostring(err)); nxt() end
		end
		nxt()
	end)
end)
