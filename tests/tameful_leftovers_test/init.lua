local function log(s) core.log("action", "[TLO_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local function deliver(player, form, fields) for _, f in ipairs(core.registered_on_player_receive_fields) do if f(player, form, fields) then return end end end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(18, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true })
		tameful.cfg.set("max_summoned", 0)
		local inv = player:get_inventory()
		local base = vector.offset(vector.round(player:get_pos()), 0, 1, 0)
		local function tame(kind, dx)
			local o = core.add_entity(vector.offset(base, dx, 0, 3), kind)
			local e = o:get_luaentity()
			inv:add_item("main", "tameful:lead 1"); player:set_wielded_item(ItemStack("tameful:lead"))
			e.on_rightclick(e, player)
			deliver(player, "tameful:tame", { yes = "true" })
			core.close_formspec("tester", "tameful:tame")
			return e
		end
		local function count(name) local n = 0 for _, s in ipairs(inv:get_list("main")) do if s:get_name() == name then n = n + s:get_count() end end return n end
		local function near(kind) local out = {} for _, o in ipairs(core.get_objects_inside_radius(base, 25)) do local e = o:get_luaentity(); if e and e.name == kind then out[#out + 1] = e end end return out end

		-- 8. skeleton / zombie horse
		local sk, zh = tame("mobs_mc:skeleton_horse", 0), tame("mobs_mc:zombie_horse", 3)
		check("skeleton horse can be tamed", sk._tameful_id ~= nil and tameful.find_record(sk._tameful_id) ~= nil)
		check("zombie horse can be tamed", zh._tameful_id ~= nil and tameful.find_record(zh._tameful_id) ~= nil)
		check("tamed skeleton/zombie horses float (swim instead of sinking)", sk.floats == 1 and zh.floats == 1, tostring(sk.floats) .. "/" .. tostring(zh.floats))
		tameful.release("tester", sk._tameful_id); tameful.release("tester", zh._tameful_id)
		check("released: back to sinking like in vanilla", sk.floats == 0 and zh.floats == 0, tostring(sk.floats) .. "/" .. tostring(zh.floats))

		-- 7a. release a loaded pig with a saddle
		local pig = tame("mobs_mc:pig", 6)
		local pid = pig._tameful_id
		pig.saddle = "yes"
		local s0 = count("mcl_mobitems:saddle")
		tameful.release("tester", pid)
		check("release: saddle back in the inventory (pig)", count("mcl_mobitems:saddle") == s0 + 1, tostring(count("mcl_mobitems:saddle")))
		check("release: pig is a normal animal without saddle", pig.saddle ~= "yes" and not pig.tamed and pig._tameful_id == nil and tameful.find_record(pid) == nil)

		-- 7b. release a stabled horse with saddle and armor: it appears next to the player, saddle + armor come back
		local horse = tame("mobs_mc:horse", -3)
		local hid = horse._tameful_id
		horse:set_saddle(ItemStack("mcl_mobitems:saddle"), nil)
		horse:set_armor_1("mcl_mobitems:iron_horse_armor", ItemStack("mcl_mobitems:iron_horse_armor"))
		check("saddle + armor are on the horse before", horse._saddle ~= "" and horse._horse_armor_stack ~= "")
		check("stable ok", tameful.stable(hid, false))
		core.after(0.5, function()
			check("horse is gone from the world while stabled", tameful.find_loaded(hid) == nil)
			local before_h = #near("mobs_mc:horse")
			local a0, s1 = count("mcl_mobitems:iron_horse_armor"), count("mcl_mobitems:saddle")
			tameful.release("tester", hid)
			core.after(0.5, function()
				local after = near("mobs_mc:horse")
				check("released stabled horse appears in the world", #after == before_h + 1, #after .. " vs " .. before_h)
				local h = after[#after]
				check("it is a normal animal (not tame)", h and not h.tamed and h._tameful_id == nil)
				check("saddle back in the inventory (horse)", count("mcl_mobitems:saddle") == s1 + 1)
				check("armor back in the inventory (horse)", count("mcl_mobitems:iron_horse_armor") == a0 + 1)
				check("horse has no saddle/armor any more", h and h._saddle == "" and (h._horse_armor_stack or "") == "")
				check("record gone, id remembered as released", tameful.find_record(hid) == nil and tameful.is_released(hid))

				-- 4. mooshroom sheared -> cow stays a pet
				local mo = tame("mobs_mc:mooshroom", 0)
				local mid = mo._tameful_id
				check("mooshroom tamed", mid ~= nil)
				mcl_util.replace_mob(mo.object, "mobs_mc:cow")
				core.after(1, function()
					local found = {}
					for _, e in pairs(core.luaentities) do if e._tameful_id == mid and e.object and e.object:get_pos() then found[#found + 1] = e end end
					check("exactly one entity carries the pet id", #found == 1, tostring(#found))
					local rec = tameful.find_record(mid)
					check("the cow is the pet now", found[1] and found[1].name == "mobs_mc:cow" and found[1].tamed and found[1].owner == "tester" and rec and rec.kind == "mobs_mc:cow",
						found[1] and found[1].name)

					-- 5. wild ocelot vs chicken pet
					local chick_pet = tame("mobs_mc:chicken", 6)
					local wild_chick = core.add_entity(vector.offset(base, -6, 0, 3), "mobs_mc:chicken"):get_luaentity()
					local oc = core.add_entity(vector.offset(base, -9, 0, 3), "mobs_mc:ocelot"):get_luaentity()
					check("wild ocelot ignores a chicken pet", oc:is_valid_target(chick_pet.object) == false)
					check("wild ocelot still hunts a wild chicken", oc:is_valid_target(wild_chick.object) == true)
					-- provoked: the pet hits the ocelot
					mcl_damage.damage_mob = nil
					local ok = pcall(function() oc.object:punch(chick_pet.object, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 1 } }) end)
					core.after(0.5, function()
						check("after a pet hit it, the ocelot may target pets (10 s)", oc:is_valid_target(chick_pet.object) == true, tostring(ok))
						log("SCENARIO_DONE"); core.request_shutdown("done")
					end)
				end)
			end)
		end)
	end)
end)
