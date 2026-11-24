local function log(s) core.log("action", "[CR_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function deliver(player, form, fields)
	for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end
end
-- damage dealt the way Mineclonia does it; returns the damage that got through
local function hit(target, dmg, src, direct, typ)
	local reason = { type = typ or "player", source = src, direct = direct or src }
	mcl_damage.finish_reason(reason)
	return mcl_util.deal_damage(target, dmg, reason)
end
local function mods(victim, dmg, src, direct, typ) -- what the modifier chain lets through for a victim
	local reason = { type = typ or "player", source = src, direct = direct or src }
	mcl_damage.finish_reason(reason)
	return mcl_damage.run_modifiers(victim, dmg, reason)
end
local function hp(o) local e = o:get_luaentity(); return e and e.health or o:get_hp() end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		local cr = conflictresolution
		log("DIAG armor groups before: " .. dump(player:get_armor_groups()):gsub("%s+", " "))
		player:set_armor_groups({ fleshy = 100 }) -- dev.conf has enable_damage=false (player is immortal)
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		check("defaults: pvp off, pets protected, own pets protected", cr.get("pvp") == false and cr.get("protect_pets") == true and cr.get("protect_own") == true)
		-- a pet owned by someone else, and one owned by the tester
		local function tamed_cow(dx, owner)
			local o = core.add_entity(vector.offset(base, dx, 0, 3), "mobs_mc:cow")
			local e = o:get_luaentity(); e.tamed = true; e.owner = owner
			core.after(0.6, function() o:set_properties({ hp_max = 100 }); e.health = 100 end)
			return o, e
		end
		local alice_cow, mine = tamed_cow(0, "alice"), nil
		local my_cow = select(1, tamed_cow(3, "tester"))
		local wild = core.add_entity(vector.offset(base, -3, 0, 3), "mobs_mc:cow")
		core.after(0.6, function() wild:set_properties({ hp_max = 100 }); wild:get_luaentity().health = 100 end)
		local alice_pet2
		local function fresh_pig() -- (Tameful may remove a stale pig: spawn a new one right before it is used)
			if alice_pet2 and alice_pet2:is_valid() then alice_pet2:remove() end
			alice_pet2 = core.add_entity(vector.offset(base, 6, 0, 3), "mobs_mc:pig")
			alice_pet2:get_luaentity().tamed = true; alice_pet2:get_luaentity().owner = "alice"
			return alice_pet2
		end
		fresh_pig()
		core.after(1.5, function()
			local function st(o) local e = o:is_valid() and o:get_luaentity(); if not e then return "GONE" end return e.name .. " tamed=" .. tostring(e.tamed) .. " owner=" .. tostring(e.owner) .. " hp=" .. tostring(e.health) end
			log("DIAG alice_cow " .. st(alice_cow) .. " | my_cow " .. st(my_cow) .. " | pig " .. st(alice_pet2) .. " | wild " .. st(wild))
			-- pets (protect_own defaults to ON since 2026-11-20: check that, then switch it off for the checks that need the old behaviour)
			check("protect_own defaults to ON", cr.get("protect_own") == true)
			cr.set("protect_own", false)
			local before = hp(alice_cow)
			check("player cannot hurt another player's pet", hit(alice_cow, 4, player) == 0 and hp(alice_cow) == before, tostring(hp(alice_cow)))
			check("a pet of the same owner is the owner: allowed while own pets unprotected", hit(alice_cow, 4, fresh_pig(), alice_pet2, "mob") > 0)
			check("another player's pet cannot hurt it (attacker owner = tester)", (function() fresh_pig(); local ent = alice_pet2:get_luaentity(); ent.owner = "tester"; local d = hit(alice_cow, 4, alice_pet2, alice_pet2, "mob"); ent.owner = "alice"; return d == 0 end)())
			check("own pet can be hurt while protect_own is off", hit(my_cow, 4, player) > 0)
			check("wild mob can be hurt", hit(wild, 4, player) > 0)
			check("damage with no source is not blocked", hit(alice_cow, 3, nil, nil, "lava") > 0)
			check("wild mob can hurt another's pet", (function() return hit(alice_cow, 2, wild, wild, "mob") > 0 end)())
			-- projectile: source is the player, direct is some arrow entity
			check("arrow shot by the player is blocked (source = player)", hit(alice_cow, 5, player, fresh_pig(), "arrow") == 0)
			-- settings
			cr.set("protect_own", true)
			local own_hit = hit(my_cow, 4, player)
			check("protect own pets: owner cannot hurt own pet", own_hit == 0 and math.abs(hp(my_cow) - 96) < 1, "hit=" .. tostring(own_hit) .. " hp=" .. tostring(hp(my_cow)))
			check("protect own pets: wild mobs still can", hit(my_cow, 1, wild, wild, "mob") > 0)
			cr.set("protect_own", false)
			cr.set("protect_pets", false)
			check("protect pets off: another's pet can be hurt", hit(alice_cow, 4, player) > 0)
			cr.set("protect_pets", true)
			-- players: tester as victim, attacker a pet owned by alice (stands in for alice's own hit)
			local mob = fresh_pig()
			check("pvp off: alice's pet cannot hurt tester", mods(player, 4, mob, mob, "mob") == 0)
			check("pvp off: damage with no attacker passes", mods(player, 2, nil, nil, "lava") > 0)
			check("pvp off: a wild mob still hurts the player", mods(player, 2, wild, wild, "mob") > 0)
			check("pvp off: self damage allowed", mods(player, 2, player, player, "generic") > 0)
			check("pvp off: arrow shot by alice's pet owner blocked", mods(player, 2, mob, mob, "arrow") == 0)
			cr.set("pvp", true)
			check("pvp on: alice's pet can hurt tester", mods(player, 2, mob, mob, "mob") > 0)
			cr.set("pvp", false)
			-- TNT lit by a player carries the player
			local e = mcl_tnt.ignite(vector.offset(base, 0, 0, -4))
			check("TNT ignited without a player has no igniter", e and e:get_luaentity()._cr_igniter == nil)
			e:remove()
			core.set_node(vector.offset(base, 0, 0, -4), { name = "mcl_tnt:tnt" })
			local def = core.registered_nodes["mcl_tnt:tnt"]
			def._on_ignite(player, { under = vector.offset(base, 0, 0, -4) })
			local found
			for _, o in ipairs(core.get_objects_inside_radius(vector.offset(base, 0, 0, -4), 2)) do
				local en = o:get_luaentity(); if en and en.name == "mcl_tnt:tnt" then found = en; o:remove() end
			end
			check("TNT lit by the tester remembers them", found and found._cr_igniter == "tester")
			check("TNT of alice's (tagged) blocked on alice's pet? (own igniter alice vs bob's)", cr.attacker_name({ direct = { is_player = function() return false end, get_luaentity = function() return { _cr_igniter = "alice" } end } }) == "alice")
			-- commands
			local cmd = core.registered_chatcommands["pvp"]
			local ok, msg = cmd.func("tester", "")
			check("/pvp shows settings", ok and msg:find("PvP", 1, true) ~= nil, tostring(msg))
			cmd.func("tester", "on"); check("/pvp on", cr.get("pvp") == true)
			cmd.func("tester", "off"); check("/pvp off", cr.get("pvp") == false)
			cmd.func("tester", "pets off"); check("/pvp pets off", cr.get("protect_pets") == false)
			cmd.func("tester", "pets on"); check("/pvp pets on", cr.get("protect_pets") == true)
			cmd.func("tester", "ownpets on"); check("/pvp ownpets on", cr.get("protect_own") == true)
			cmd.func("tester", "ownpets off")
			local ok2 = cmd.func("tester", "banana"); check("bad argument refused", ok2 == false)
			core.set_player_privs("tester", { interact = true, shout = true })
			local ok3 = cmd.func("tester", "on"); check("no server priv: cannot change", ok3 == false and cr.get("pvp") == false)
			deliver(player, "conflictresolution:main", { pvp = "true" }); check("screen also refuses without the priv", cr.get("pvp") == false)
			core.set_player_privs("tester", { interact = true, shout = true, server = true })
			deliver(player, "conflictresolution:main", { pvp = "true" }); check("screen toggles PvP", cr.get("pvp") == true)
			deliver(player, "conflictresolution:main", { pvp = "false" })
			check("screen builds", core.registered_chatcommands["cr"].func("tester", "") == true)
			log("SCENARIO_DONE"); core.request_shutdown("done")
		end)
	end)
end)
