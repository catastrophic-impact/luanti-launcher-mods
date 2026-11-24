-- Scenario test: real server + one real client ("tester"). Results: [POPULATIONS_TEST] lines in the server log.
local function log(s) core.log("action", "[POPULATIONS_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end

local function wait_until(limit, cond, done)
	local t = 0
	local function tick()
		if cond() then return done(true, t) end
		if t >= limit then return done(false, t) end
		t = t + 1
		core.after(1, tick)
	end
	tick()
end

local function spawn(pos, data)
	local obj = core.add_entity(pos, "mobs_mc:villager", data and core.serialize(data) or nil)
	return obj, obj and obj:get_luaentity()
end

local S
local steps = {
	function(player, nxt) -- identity for ten villagers, balanced genders
		local base = vector.round(player:get_pos())
		local men, women, bad = 0, 0, 0
		local ents = {}
		for i = 1, 10 do
			local _, ent = spawn(vector.offset(base, (i % 5) * 2 - 4, 1, math.floor(i / 5) * 2 + 3))
			ents[#ents + 1] = ent
			local p = ent and ent._pop
			if not p or not p.first or not p.last or not p.skin or not p.id then bad = bad + 1
			elseif p.gender == "male" then men = men + 1 else women = women + 1 end
		end
		check("every villager has an identity", bad == 0, bad .. " without")
		check("genders balanced within 1", math.abs(men - women) <= 1, men .. " men / " .. women .. " women")
		local e = ents[1]
		local props = e.object:get_properties()
		check("player-shaped mesh", props.mesh == "mobs_mc_zombie.b3d", props.mesh)
		check("skin texture applied", props.textures[2] == "populations_" .. e._pop.skin .. ".png", tostring(props.textures[2]))
		check("name tag shows name and health", props.nametag:find(e._pop.first, 1, true) and props.nametag:find("40/40", 1, true), tostring(props.nametag))
		log("NOTE tag=[" .. props.nametag:gsub("\n", " | ") .. "] pos=" .. core.pos_to_string(vector.round(e.object:get_pos())))
		-- profession shows in the tag
		e:set_profession("armorer")
		populations.refresh_tag(e)
		check("job in name tag", e.object:get_properties().nametag:find("Armorer", 1, true) ~= nil, e.object:get_properties().nametag)
		-- a player's name tag renames, the tag keeps health and job
		e.nametag = "Bob Rename"
		populations.refresh_tag(e)
		check("name tag item renames", e.object:get_properties().nametag:find("Bob Rename", 1, true) ~= nil)
		check("death messages use the custom name", mcl_util.get_object_name(e.object) == "Bob Rename", mcl_util.get_object_name(e.object))
		e._pop_custom = nil; e.nametag = nil; populations.refresh_tag(e)
		check("death messages use the full name", mcl_util.get_object_name(e.object) == e._pop.first .. " " .. e._pop.last, mcl_util.get_object_name(e.object))
		S = { base = base, ents = ents }
		nxt()
	end,

	function(player, nxt) -- pairing rules and birth
		local men, women = {}, {}
		for _, e in ipairs(S.ents) do
			if e._pop.gender == "male" then men[#men + 1] = e else women[#women + 1] = e end
		end
		check("have 2 men and 2 women to pair", #men >= 2 and #women >= 2)
		local m1, m2, w1, w2 = men[1], men[2], women[1], women[2]
		check("two men cannot pair", not populations.can_pair(m1, m2))
		check("two women cannot pair", not populations.can_pair(w1, w2))
		check("man and woman can pair", populations.can_pair(m1, w1))
		local bed = vector.offset(S.base, 0, 0, 0)
		local before = 0
		for _, o in ipairs(core.get_objects_inside_radius(S.base, 30)) do local e = o:get_luaentity(); if e and e.child then before = before + 1 end end
		local ok = pcall(function() m1:conceive_child(w1, bed) end)
		local babies = {}
		for _, o in ipairs(core.get_objects_inside_radius(S.base, 30)) do local e = o:get_luaentity(); if e and e.child and e.name == "mobs_mc:villager" then babies[#babies + 1] = e end end
		check("baby spawned", ok and #babies == before + 1, tostring(ok) .. " babies=" .. #babies)
		local baby = babies[#babies]
		check("baby has an identity", baby and baby._pop ~= nil)
		check("partners for life", m1._pop.partner == w1._pop.id and w1._pop.partner == m1._pop.id)
		check("she takes his last name", w1._pop.last == m1._pop.last)
		check("baby has father's last name", baby and baby._pop.last == m1._pop.last)
		check("baby is half size", baby and baby.object:get_properties().visual_size.x < 0.9)
		check("father cannot pair with another woman", not populations.can_pair(m1, w2))
		check("mother cannot pair with another man", not populations.can_pair(m2, w1))
		check("partners can pair again", populations.can_pair(m1, w1))
		-- partner dies -> free again
		populations._mark_dead(w1._pop.id)
		check("widower may start a new family", populations.can_pair(m1, w2))
		S.m1, S.w2 = m1, w2
		nxt()
	end,

	function(player, nxt) -- zombify and cure: same person
		local e = S.ents[3]
		local id, first = e._pop.id, e._pop.first
		local data = e:export_villager_data()
		local zobj = e:replace_with("mobs_mc:villager_zombie", false, { _previous_incarnation = data })
		check("zombie villager created", zobj ~= nil)
		local z = zobj and zobj:get_luaentity()
		check("zombie keeps the person", z and z._previous_incarnation and z._previous_incarnation.pop and z._previous_incarnation.pop.id == id)
		local vobj = z and z:replace_with("mobs_mc:villager", false, z:previous_staticdata())
		local v = vobj and vobj:get_luaentity()
		check("cured villager is the same person", v and v._pop and v._pop.id == id and v._pop.first == first)
		-- persistence round trip (what a restart does)
		local sd = v and v:get_staticdata()
		local obj2 = sd and core.add_entity(vector.offset(S.base, 0, 1, -3), "mobs_mc:villager", sd)
		local v2 = obj2 and obj2:get_luaentity()
		check("person survives staticdata round trip", v2 and v2._pop and v2._pop.id == id)
		nxt()
	end,

	function(player, nxt) -- health, regeneration
		local base = vector.offset(S.base, 4, 1, 4)
		local _, adult = spawn(base)
		local _, kid = spawn(base, { child = true })
		check("adult has 40 max health", adult.object:get_properties().hp_max == 40, tostring(adult.object:get_properties().hp_max))
		check("child has 20 max health", kid.object:get_properties().hp_max == 20, tostring(kid.object:get_properties().hp_max))
		adult.health = 30
		populations._fight_state[adult] = nil
		core.after(7, function()
			check("heals 1 hp per 2 s out of combat", adult.health >= 33, tostring(adult.health))
			nxt()
		end)
	end,

	function(player, nxt) -- fights back with gear, calls a helper
		local base = vector.offset(S.base, -4, 1, 4)
		local _, v = spawn(base)
		local cobj = core.add_entity(vector.offset(base, 3, 0, 0), "mobs_mc:cow")
		local cow = cobj:get_luaentity()
		-- mobs set their own health after activation: make the cow a durable punching bag one step later
		core.after(0.5, function()
		cow.object:set_properties({ hp_max = 1000 })
		cow.health = 1000
		v:receive_damage({ type = "mob", source = cobj }, 1)
		local st = populations._fight_state[v]
		check("hit villager remembers the attacker", st and st.enemy == cobj)
		for i = 1, 8 do v:receive_damage({ type = "mob", source = cobj }, 0.1) end
		local called = 0
		for _, o in ipairs(core.get_objects_inside_radius(base, 32)) do
			local e = o:get_luaentity()
			local s2 = e and populations._fight_state[e]
			if e and e ~= v and s2 and s2.called then called = called + 1 end
		end
		check("a helper was called", called >= 1, tostring(called))
		local seen_sword, seen_head, hit = false, false, false
		local cow_hp = cow.health
		local function poll()
			if v:get_wielditem():get_name() == "mcl_tools:sword_stone" then seen_sword = true end
			if v.armor_list and v.armor_list.head == "mcl_armor:helmet_leather" then seen_head = true end
			if cow.health < cow_hp then hit = true end
		end
		local t = 0
		local function loop()
			t = t + 0.2
			poll()
			if t < 12 and not (hit and seen_sword and seen_head) then return core.after(0.2, loop) end
			check("villager fights back and hurts the attacker", hit)
			check("villager wields the sword while fighting", seen_sword)
			check("villager wears armor while fighting", seen_head)
			if cobj:get_pos() then cobj:remove() end
			wait_until(20, function() local s3 = populations._fight_state[v]; return not (s3 and s3.geared) end, function(ok2)
				check("gear is gone after the fight", ok2 and v:get_wielditem():is_empty() and v.armor_list.head == "")
				nxt()
			end)
		end
		loop()
		end)
	end,

	function(player, nxt) -- flees at half health: no fighting
		local _, v = spawn(vector.offset(S.base, 6, 0, -4))
		v.health = 15
		local cobj = core.add_entity(vector.offset(S.base, 8, 0, -4), "mobs_mc:cow")
		v:receive_damage({ type = "mob", source = cobj }, 0.1)
		local st = populations._fight_state[v]
		check("hurt villager at half health does not fight", not (st and st.enemy))
		cobj:remove()
		-- children never fight
		local _, kid = spawn(vector.offset(S.base, 6, 0, -6), { child = true })
		local c2 = core.add_entity(vector.offset(S.base, 8, 0, -6), "mobs_mc:cow")
		kid:receive_damage({ type = "mob", source = c2 }, 0.1)
		local ks = populations._fight_state[kid]
		check("children never fight", not (ks and ks.enemy))
		c2:remove()
		nxt()
	end,

	function(player, nxt) -- golems
		local gobj = core.add_entity(vector.offset(S.base, 0, 0, 8), "mobs_mc:iron_golem")
		local g = gobj:get_luaentity()
		local def = core.registered_entities["mobs_mc:iron_golem"]
		check("golem 30% faster", math.abs(g.movement_speed - def.movement_speed * 1.3) < 0.01, tostring(g.movement_speed))
		check("golem 25% stronger", math.abs(g.damage - def.damage * 1.25) < 0.01, tostring(g.damage))
		check("golem sees 32 blocks", g.view_range >= 32, tostring(g.view_range))
		populations.cfg.set("stronger_golems", false)
		populations.refresh_golems()
		check("setting off restores golem", g.movement_speed == def.movement_speed and g.damage == def.damage)
		populations.cfg.set("stronger_golems", true)
		-- settings screen
		local fs = populations.cfg.formspec("tester")
		local plain = fs:gsub("\27%(T@[^)]*%)", ""):gsub("\27E", "") -- translated strings carry hidden markers
		check("settings formspec builds", plain:find("Armor in a fight", 1, true) ~= nil and plain:find("Stronger iron golems", 1, true) ~= nil)
		nxt()
	end,

	function(player, nxt) -- gait: a real villager panicking and then wandering; limbs must not flail
		local base = vector.offset(S.base, 12, 1, 0)
		local _, v = spawn(base)
		local cobj = core.add_entity(vector.offset(base, 2, 0, 0), "mobs_mc:cow")
		v.health = 10 -- below half: it runs instead of fighting
		v:receive_damage({ type = "mob", source = cobj }, 1)
		cobj:remove()
		local phases = { panic = {}, wander = {} }
		local phase, t = "panic", 0
		local function tick()
			t = t + 0.25
			if t > 3 and phase == "panic" then phase = "wander"; v._panic_time = nil; v._panic_source = nil end
			local vel = v:get_velocity()
			local range, fps = v.object:get_animation()
			if vel > 0.3 and fps and v._current_animation ~= "stand" then
				table.insert(phases[phase], { vel = vel, fps = fps, frames = range.y - range.x + 1, anim = v._current_animation })
			end
			if t < 25 then return core.after(0.25, tick) end
			for name, list in pairs(phases) do
				local n = #list
				if n == 0 then
					log("NOTE gait " .. name .. ": no moving samples")
				else
					local worst_cycles, lo, hi, sv = 0, 1e9, 0, 0
					for _, s2 in ipairs(list) do
						local cycles = s2.fps / s2.frames
						worst_cycles = math.max(worst_cycles, cycles)
						local per = s2.vel / cycles
						if s2.vel >= 1.5 then lo, hi = math.min(lo, per), math.max(hi, per) end -- slow starts/stops are ignored
						sv = sv + s2.vel
					end
					log(string.format("NOTE gait %s: %d samples, mean %.2f b/s, worst %.2f cycles/s, %.2f-%.2f blocks per cycle (anim %s)", name, n, sv / n, worst_cycles, lo, hi, tostring(list[1].anim)))
					check("gait " .. name .. ": at most 1.6 cycles/s (a player walks at 1.5)", worst_cycles <= 1.6, string.format("%.2f", worst_cycles))
					check("gait " .. name .. ": at least 2 blocks per cycle at speed", lo >= 2.0 or lo == 1e9, string.format("%.2f", lo))
				end
			end
			check("villager moved in both phases", #phases.panic > 0 and #phases.wander > 0, #phases.panic .. "/" .. #phases.wander)
			nxt()
		end
		tick()
	end,

	function(player, nxt)
		log("SCENARIO_DONE")
		core.request_shutdown("done", false, 1)
	end,
}

-- Step names, in order of the steps above. `lt test populations_test --only fight,gait` runs just those
-- (identity always runs: it sets up the shared scene); no --only = everything.
local NAMES = { "identity", "pairing", "zombie", "health", "fight", "flee", "golems", "gait" }
local only
do
	local f = io.open(core.get_worldpath() .. "/test_only.txt", "r")
	if f then
		only = {}
		for name in f:read("*a"):gmatch("[%w_]+") do only[name] = true end
		f:close()
	end
end
local function wanted(i) return not only or i == 1 or i == #steps or only[NAMES[i]] end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(20, function()
		local i = 0
		local function nxt()
			i = i + 1
			while steps[i] and not wanted(i) do i = i + 1 end
			if steps[i] then
				local ok, err = pcall(steps[i], player, nxt)
				if not ok then log("FAIL step " .. tostring(NAMES[i] or i) .. " error: " .. tostring(err)); log("SCENARIO_ABORT error"); core.request_shutdown("abort", false, 1) end
			end
		end
		nxt()
	end)
end)
