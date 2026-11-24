local function log(s) core.log("action", "[TAMEFUL_STATS_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function fmt(n) return string.format("%.3f", n) end

local function tame(player, kind, off)
	local obj = core.add_entity(vector.offset(vector.round(player:get_pos()), off, 1, 0), kind)
	local ent = obj:get_luaentity()
	player:get_inventory():add_item("main", "tameful:lead 1")
	player:set_wielded_item(ItemStack("tameful:lead"))
	ent.on_rightclick(ent, player)
	for _, f in ipairs(core.registered_on_player_receive_fields) do
		if f(player, "tameful:tame", { yes = "true" }) then break end
	end
	return obj, ent
end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local pig_o, pig = tame(player, "mobs_mc:pig", 3)
		local wolf_o, wolf = tame(player, "mobs_mc:wolf", 6)
		core.after(1.5, function()
			check("pig tamed", pig.tamed == true and pig._tameful_stats ~= nil)
			check("pig hp_max 50 / health 50", pig_o:get_properties().hp_max == 50 and pig.health == 50, tostring(pig.health))
			check("pig attack = wood sword 4", pig.damage == 4, tostring(pig.damage))
			check("wolf hp 30, attack iron 6", wolf_o:get_properties().hp_max == 30 and wolf.damage == 6)
			-- armor: pig = chain (5 pts): damage 10 -> 10*(1-max(1, 5-10/2)/25) = 9.6
			local function lost(ent, obj, dmg, n)
				local sum = 0
				for i = 1, n do
					ent.health = 50
					mcl_util.deal_damage(obj, dmg, { type = "generic", flags = {} })
					sum = sum + (50 - ent.health)
				end
				return sum / n
			end
			local l = lost(pig, pig_o, 10, 5)
			check("pig armor chain: hit of 10 -> 9.6", math.abs(l - 9.6) < 0.01, fmt(l))
			-- bypasses_armor must not be reduced
			pig.health = 50
			mcl_util.deal_damage(pig_o, 10, { type = "generic", flags = { bypasses_armor = true } })
			check("bypasses_armor stays 10", math.abs((50 - pig.health) - 10) < 0.01, fmt(50 - pig.health))
			-- crit: wolf 30% over 600 hits against a cow punching bag
			local cow_o = core.add_entity(vector.offset(wolf_o:get_pos(), 1.5, 0, 0), "mobs_mc:cow")
			core.after(0.6, function()
				local cow = cow_o:get_luaentity()
				local dbl, n = 0, 600
				for i = 1, n do
					cow_o:set_properties({ hp_max = 1000 }); cow.health = 1000
					wolf.attack = cow_o
					wolf:custom_attack()
					wolf.attack = nil
					if 1000 - cow.health > 7 then dbl = dbl + 1 end
				end
				local pct = dbl / n * 100
				check("wolf crit about 30% (20..40)", pct > 20 and pct < 40, fmt(pct))
				check("damage restored after crit", wolf.damage == 6, tostring(wolf.damage))
				-- name tag: ignored on pets (tag kept, name unchanged)
			local tag = ItemStack("mcl_mobitems:nametag"); tag:get_meta():set_string("name", "Bob")
			player:set_wielded_item(tag)
			local before = pig.nametag
			pig.on_rightclick(pig, player)
			check("name tag does nothing on a pet", pig.nametag == before and player:get_wielded_item():get_count() == 1, tostring(pig.nametag))
			-- uniform walking pace
			check("pets share movement_speed 6 and pace 0.95", pig.movement_speed == 6 and pig.pace_bonus == 0.95 and wolf.movement_speed == 6, tostring(pig.movement_speed))
			-- release restores plain behaviour
				tameful.untame(pig)
				check("untame clears stats", pig._tameful_stats == nil and rawget(pig, "custom_attack") == nil)
				check("untame restores speed, pace, name tags", pig.movement_speed == 5 and pig.pace_bonus == 1.0 and not pig.ignores_nametag, tostring(pig.movement_speed) .. " " .. tostring(pig.pace_bonus))
				log("SCENARIO_DONE")
				core.request_shutdown("done")
			end)
		end)
	end)
end)
