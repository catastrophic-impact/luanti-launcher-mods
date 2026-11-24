local function log(s) core.log("action", "[SPEED_PROBE_TEST] NOTE " .. s) end
local KINDS = { "rabbit" }
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
local function hv(o) local v = o:get_velocity(); return math.sqrt(v.x * v.x + v.z * v.z) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, fly = true })
		tameful.cfg.set("max_summoned", 0)
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local i = 0
		local function nxt()
			i = i + 1
			local kind = KINDS[i]
			if not kind then log("SCENARIO_DONE"); return core.request_shutdown("done") end
			player:set_pos(base)
			local obj = core.add_entity(vector.offset(base, 2, 0, 0), "mobs_mc:" .. kind)
			local ent = obj:get_luaentity()
			player:get_inventory():add_item("main", "tameful:lead 1")
			player:set_wielded_item(ItemStack("tameful:lead"))
			ent.on_rightclick(ent, player)
			deliver(player, "tameful:tame", { yes = "true" })
			core.close_formspec("tester", "tameful:tame")
			core.after(1.5, function()
				-- wander: relax, sample horizontal speed 20 s, keep the moving samples
				tameful.set_mode(ent, "relax")
				ent._tameful_wander = 24
				local samples = {}
				local t = 0
				local function sample()
					t = t + 0.25
					local s = hv(obj)
					if s > 0.3 then samples[#samples + 1] = s end
					if t < 20 then return core.after(0.25, sample) end
					table.sort(samples)
					local med = samples[math.ceil(#samples / 2)] or 0
					local mx = samples[#samples] or 0
					-- follow: owner 20 blocks away, measure 2 s peak
					tameful.set_mode(ent, "follow")
					player:set_pos(vector.offset(obj:get_pos(), 22, 0, 0))
					local best, tt = 0, 0
					local p0 = obj:get_pos()
					local function fs()
						tt = tt + 0.2
						best = math.max(best, hv(obj))
						if tt < 6 then return core.after(0.2, fs) end
						local p1 = obj:get_pos()
						local avg = math.sqrt((p1.x - p0.x) ^ 2 + (p1.z - p0.z) ^ 2) / 6
						log(string.format("%s: avg follow %.2f b/s | movement_speed=%s wander median %.2f max %.2f (n=%d) | follow peak %.2f", kind, avg, tostring(ent.movement_speed), med, mx, #samples, best))
						obj:remove()
						core.after(0.5, nxt)
					end
					fs()
				end
				sample()
			end)
		end
		nxt()
	end)
end)
