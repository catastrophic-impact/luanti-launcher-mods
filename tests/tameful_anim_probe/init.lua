local function log(s) core.log("action", "[ANIM_PROBE_TEST] NOTE " .. s) end
local KINDS = { "pig", "cow", "horse" }
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
local function hv(o) local v = o:get_velocity(); return math.sqrt(v.x * v.x + v.z * v.z) end
local function fs(o) local _, sp = o:get_animation(); return sp or -1 end
-- sample (velocity, frame speed, anim name) over secs; report max/median of moving samples
local function sample(obj, ent, secs, label, done)
	local t, vs, fr = 0, {}, {}
	local function step()
		t = t + 0.25
		local v = hv(obj)
		if v > 0.3 then vs[#vs + 1] = v; fr[#fr + 1] = fs(obj) end
		if t < secs then return core.after(0.25, step) end
		table.sort(vs); table.sort(fr)
		local function med(a) return a[math.ceil(#a / 2)] or 0 end
		log(string.format("%s %s: n=%d vel med %.2f max %.2f | frame_speed med %.1f max %.1f | anim=%s walk_speed=%s speed_normal=%s fsm=%s",
			ent.name, label, #vs, med(vs), vs[#vs] or 0, med(fr), fr[#fr] or 0, tostring(ent._current_animation),
			tostring(ent.animation and ent.animation.walk_speed), tostring(ent.animation and ent.animation.speed_normal), tostring(ent.frame_speed_multiplier)))
		done()
	end
	step()
end
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
			-- wild
			local obj = core.add_entity(vector.offset(base, 6, 0, 0), "mobs_mc:" .. kind)
			local ent = obj:get_luaentity()
			sample(obj, ent, 12, "WILD wander", function()
				player:set_pos(base)
				obj:set_pos(vector.offset(base, 2, 0, 0))
				player:get_inventory():add_item("main", "tameful:lead 1")
				player:set_wielded_item(ItemStack("tameful:lead"))
				ent.on_rightclick(ent, player)
				deliver(player, "tameful:tame", { yes = "true" })
				core.close_formspec("tester", "tameful:tame")
				core.after(1.5, function()
					tameful.set_mode(ent, "relax")
					ent._tameful_wander = 24
					sample(obj, ent, 12, "PET wander", function()
						tameful.set_mode(ent, "follow")
						player:set_pos(vector.offset(obj:get_pos(), 22, 0, 0))
						sample(obj, ent, 6, "PET follow", function() obj:remove(); core.after(0.5, nxt) end)
					end)
				end)
			end)
		end
		nxt()
	end)
end)
