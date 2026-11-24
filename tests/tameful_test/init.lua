-- Scenario test: real server + one real client ("tester"). Results go to the server log as [TAMEFUL_TEST] lines.
local storage = core.get_mod_storage()
local phase = storage:get_int("phase")
local function log(s) core.log("action", "[TAMEFUL_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function dist(a, b) return vector.distance(a, b) end
local function fmt(n) return string.format("%.1f", n) end

local function deliver(player, formname, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do
		if f(player, formname, fields) then return end
	end
end

-- Poll cond() every second up to `limit` seconds, then call done(ok, seconds_waited).
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

-- Standing position above open ground at (x, z): highest solid non-leaf node with two free nodes above.
local function ground_at(x, z, y0)
	for y = y0 + 60, y0 - 30, -1 do
		local n = core.get_node_or_nil({ x = x, y = y, z = z })
		if not n then return nil end
		local def = core.registered_nodes[n.name]
		if n.name ~= "air" and def and def.walkable and core.get_item_group(n.name, "leaves") == 0 then
			local a1 = core.get_node_or_nil({ x = x, y = y + 1, z = z })
			local a2 = core.get_node_or_nil({ x = x, y = y + 2, z = z })
			if a1 and a2 and a1.name == "air" and a2.name == "air" then
				return { x = x, y = y + 1.5, z = z }
			end
			return nil
		end
	end
end

local function find_ground_near(x, z, y0)
	for r = 0, 12, 3 do
		for _, d in ipairs({ { 0, 0 }, { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r, r }, { -r, -r }, { r, -r }, { -r, r } }) do
			local g = ground_at(x + d[1], z + d[2], y0)
			if g then return g end
		end
	end
end

local function abort(why)
	log("SCENARIO_ABORT " .. why)
	core.request_shutdown("abort", false, 1)
end

local function teleport_safe(player, x, z, y0, done)
	core.emerge_area({ x = x - 20, y = y0 - 30, z = z - 20 }, { x = x + 20, y = y0 + 60, z = z + 20 })
	wait_until(40, function() return find_ground_near(x, z, y0) ~= nil end, function(ok)
		if not ok then return abort("no safe ground near " .. x .. "," .. z) end
		local pos = find_ground_near(x, z, y0)
		player:set_pos(pos)
		done(pos)
	end)
end

local function diag(ent, player, tag)
	local pp = player:get_pos()
	log(string.format("DIAG %s: pet=%s player=%s activity=%s order=%s", tag,
		core.pos_to_string(vector.round(ent.object:get_pos())), core.pos_to_string(vector.round(pp)),
		tostring(ent._active_activity), tostring(ent.order)))
end

local function pets_of(name)
	local n = 0
	for _ in pairs(tameful.roster[name] or {}) do n = n + 1 end
	return n
end

-- Run steps one after another; every step gets (player, next).
local function run_steps(player, steps)
	local i = 0
	local function nxt()
		i = i + 1
		if steps[i] then steps[i](player, nxt) end
	end
	nxt()
end

local S = {} -- shared scenario state

local steps = {
	function(player, nxt) -- setup + tame
		S.start = vector.round(player:get_pos())
		log("start pos " .. core.pos_to_string(S.start))
		tameful.cfg.set("downed_seconds", 3)
		tameful.cfg.set("max_summoned", 1)
		player:get_inventory():add_item("main", "tameful:lead 3")
		player:set_wielded_item(ItemStack("tameful:lead"))
		S.obj = core.add_entity(vector.offset(S.start, 2, 1, 0), "mobs_mc:pig")
		S.ent = S.obj and S.obj:get_luaentity()
		check("pig spawned", S.ent ~= nil)
		if not S.ent then return abort("no pig") end
		S.ent.on_rightclick(S.ent, player)
		check("not tamed before answering", not S.ent.tamed)
		deliver(player, "tameful:tame", { yes = "true" })
		S.id = S.ent._tameful_id
		local rec = tameful.roster.tester and tameful.roster.tester[S.id]
		check("tamed after Yes", S.ent.tamed == true and S.ent.owner == "tester" and rec ~= nil)
		check("record is out in the world", rec and rec.status == "out")
		nxt()
	end,

	function(player, nxt) -- keep up with a walking player (7 blocks/s for 14 s along +x at 7 b/s, a fast sprint)
		local sx, sz, sy = S.start.x, S.start.z, S.start.y
		core.emerge_area({ x = sx - 10, y = sy - 30, z = sz - 10 }, { x = sx + 110, y = sy + 60, z = sz + 10 })
		wait_until(60, function() return ground_at(sx + 100, sz, sy) ~= nil end, function(ok)
			if not ok then return abort("corridor not loaded") end
			local x, y = sx, sy
			local maxd, t, travelled = 0, 0, 0
			local last = S.obj:get_pos()
			local function step()
				t = t + 0.1
				x = x + 0.70
				local g = ground_at(math.floor(x), sz, math.floor(y)) or { y = y }
				y = g.y
				player:set_pos({ x = x, y = y, z = sz })
				local d = dist(S.obj:get_pos(), player:get_pos())
				if d > maxd then maxd = d end
				local pp = S.obj:get_pos()
				travelled = travelled + vector.distance({ x = pp.x, y = 0, z = pp.z }, { x = last.x, y = 0, z = last.z })
				last = pp
				if t < 14 then return core.after(0.1, step) end
				log("NOTE keep-up: max distance " .. fmt(maxd) .. ", final " .. fmt(d) .. ", pet average speed " .. fmt(travelled / t) .. " b/s (player 7.0)")
				check("pet keeps up while walking (max distance < 14)", maxd < 14, fmt(maxd))
				nxt()
			end
			step()
		end)
	end,

	function(player, nxt) -- follow after a far teleport, then Stay / Follow with the empty hand
		teleport_safe(player, S.start.x - 40, S.start.z + 20, S.start.y, function()
			wait_until(40, function() return dist(S.obj:get_pos(), player:get_pos()) < 8 end, function(ok, t)
				log("far follow took " .. t .. " s")
				if not ok then diag(S.ent, player, "far follow") end
				check("pet follows after a far teleport", ok)
				player:set_wielded_item(ItemStack(""))
				S.ent.on_rightclick(S.ent, player)
				check("empty hand click = Stay", S.ent.order == "sit")
				local stay_pos = S.obj:get_pos()
				teleport_safe(player, math.floor(stay_pos.x), math.floor(stay_pos.z) + 30, S.start.y, function()
					core.after(8, function()
						local moved = dist(S.obj:get_pos(), stay_pos)
						check("staying pet stays put", moved < 3, fmt(moved))
						S.ent.on_rightclick(S.ent, player)
						check("second click = Follow", S.ent.order ~= "sit")
						wait_until(40, function() return dist(S.obj:get_pos(), player:get_pos()) < 8 end, function(ok2)
							if not ok2 then diag(S.ent, player, "refollow") end
							check("pet follows again", ok2)
							nxt()
						end)
					end)
				end)
			end)
		end)
	end,

	function(player, nxt) -- stable via the screen, then resummon
		deliver(player, "tameful:roster", { pets = "CHG:1" })
		deliver(player, "tameful:roster", { pets = "CHG:1", stable = "true" })
		local rec = tameful.roster.tester[S.id]
		check("stable: status stabled", rec.status == "stabled")
		core.after(1, function()
			check("stable: entity gone from the world", tameful._find_loaded_ok == nil and tameful.find_loaded(S.id) == nil)
			deliver(player, "tameful:roster", { resummon = "true" })
			check("resummon: status out", rec.status == "out")
			core.after(1, function()
				S.ent = tameful.find_loaded(S.id)
				check("resummon: pet is back and tamed", S.ent ~= nil and S.ent.tamed and S.ent.owner == "tester")
				if S.ent then S.obj = S.ent.object end
				check("resummon: next to the player", S.obj and dist(S.obj:get_pos(), player:get_pos()) < 5)
				nxt()
			end)
		end)
	end,

	function(player, nxt) -- summon limit: second pet goes straight to the stable
		player:set_wielded_item(ItemStack("tameful:lead"))
		local cow = core.add_entity(vector.offset(player:get_pos(), 2, 1, 2), "mobs_mc:cow")
		local cent = cow and cow:get_luaentity()
		check("cow spawned", cent ~= nil)
		if not cent then return abort("no cow") end
		cent.on_rightclick(cent, player)
		deliver(player, "tameful:tame", { yes = "true" })
		S.cow_id = cent._tameful_id
		local rec = tameful.roster.tester[S.cow_id]
		check("limit: second pet is stabled", rec and rec.status == "stabled")
		core.after(1, function()
			check("limit: cow removed from the world", tameful.find_loaded(S.cow_id) == nil)
			deliver(player, "tameful:roster", { pets = "CHG:2", resummon = "true" })
			check("limit: resummon refused at the limit", rec.status == "stabled")
			nxt()
		end)
	end,

	function(player, nxt) -- downed: lethal damage through the real punch path
		-- conflictresolution now protects an owner's own pets by default (2026-11-20): switch that off so the owner's punch is a real hit
		if rawget(_G, "conflictresolution") and conflictresolution.set then conflictresolution.set("protect_own", false) end
		local rec = tameful.roster.tester[S.id]
		local before = S.ent.health
		S.obj:punch(player, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 1000 } }, nil)
		core.after(1.5, function()
			check("downed: record is downed", rec.status == "downed", rec.status)
			check("downed: entity removed, no death", tameful.find_loaded(S.id) == nil)
			deliver(player, "tameful:roster", { pets = "CHG:1", resummon = "true" })
			check("downed: resummon refused while recovering", rec.status == "downed")
			core.after(3.5, function()
				deliver(player, "tameful:roster", { pets = "CHG:1", resummon = "true" })
				check("downed: resummon works after recovery", rec.status == "out")
				core.after(1, function()
					S.ent = tameful.find_loaded(S.id)
					check("downed: back with full health", S.ent ~= nil and S.ent.health >= (before or 1) - 0.01,
						S.ent and tostring(S.ent.health) .. "/" .. tostring(before))
					if S.ent then S.obj = S.ent.object end
					nxt()
				end)
			end)
		end)
	end,

	function(player, nxt) -- rename, screen content, release
		deliver(player, "tameful:roster", { pets = "CHG:1", rename = "true", newname = "Rex" })
		local rec = tameful.roster.tester[S.id]
		check("rename: record", rec.name == "Rex")
		check("rename: nametag on the pet", S.ent and S.ent.nametag == "Rex", S.ent and S.ent.nametag)
		local fs = tameful._roster_formspec("tester")
		check("screen: pet name shown", fs:find("Rex", 1, true) ~= nil)
		check("screen: picture (model) shown", fs:find("model[", 1, true) ~= nil)
		check("screen: settings shown read-only for a normal player", fs:find("Max pets out at once", 1, true) ~= nil
			and fs:find("s_max_summoned", 1, true) == nil)
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		fs = tameful._roster_formspec("tester")
		check("screen: settings editable for an operator", fs:find("s_max_summoned", 1, true) ~= nil)
		deliver(player, "tameful:roster", { pets = "CHG:1", s_max_summoned = "2", s_max_tames = "7", save_settings = "true" })
		check("settings: saved by an operator", tameful.cfg.get("max_summoned") == 2 and tameful.cfg.get("max_tames") == 7)
		core.set_player_privs("tester", { interact = true, shout = true })
		deliver(player, "tameful:roster", { pets = "CHG:1", s_max_summoned = "9", save_settings = "true" })
		check("settings: refused for a normal player", tameful.cfg.get("max_summoned") == 2)
		deliver(player, "tameful:roster", { pets = "CHG:2", release = "true" })
		deliver(player, "tameful:release", { yes = "true" })
		check("release: record removed", tameful.roster.tester[S.cow_id] == nil)
		check("one pet left", pets_of("tester") == 1)
		nxt()
	end,

	function(player, nxt) -- logout: the following pet waits in the stable
		core.kick_player("tester", "test logout")
		core.after(3, function()
			local rec = tameful.roster.tester[S.id]
			check("logout: following pet is stabled", rec and rec.status == "stabled")
			storage:set_int("phase", 1)
			storage:set_string("pet_id", tostring(S.id))
			storage:set_string("pet_pos", core.serialize(S.start))
			log("SCENARIO_DONE")
			core.request_shutdown("done", false, 1)
		end)
	end,
}

if phase == 0 then
	core.register_on_joinplayer(function(player)
		if player:get_player_name() ~= "tester" then return end
		core.after(20, run_steps, player, steps)
	end)
elseif phase == 1 then
	-- Restart: roster and stable survive; a stale copy of a stabled pet is removed when its block loads.
	local pos = core.deserialize(storage:get_string("pet_pos"))
	local id = tonumber(storage:get_string("pet_id"))
	core.after(1, function()
		local rec = tameful.roster.tester and tameful.roster.tester[id]
		check("restart: record restored as stabled", rec ~= nil and rec.status == "stabled")
		local snap = rec and rec.snapshot and core.deserialize(rec.snapshot)
		check("restart: snapshot readable", snap ~= nil and snap.tamed == true and snap.owner == "tester")
		core.forceload_block(pos, true)
		core.after(2, function()
			local obj = core.add_entity(vector.offset(pos, 0, 3, 0), rec.kind, rec.snapshot)
			core.after(1, function()
				local gone = (not obj) or (not obj:get_pos())
				check("restart: stale copy of a stabled pet is removed", gone)
				storage:set_int("phase", 0)
				log("PERSIST_DONE")
				core.request_shutdown("done", false, 1)
			end)
		end)
	end)
end
