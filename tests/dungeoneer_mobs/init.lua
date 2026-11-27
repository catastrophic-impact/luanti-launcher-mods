local function log(s) core.log("action", "[DG_MOBS_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
local function tagged(minp, maxp, id) local t = {}; for _, o in ipairs(core.get_objects_in_area(minp, maxp)) do local e = o:get_luaentity(); if e and e._dg_run == id then t[#t + 1] = o end end; return t end
local made = {}
local orig_tag = dungeoneer.tag_mob
function dungeoneer.tag_mob(obj, id) local e = orig_tag(obj, id); if e then made[#made + 1] = { obj = obj, name = e.name, pos = obj:get_pos(), persistent = e.persistent, id = id } end return e end
core.after(2, function()
	dungeoneer.new_run(3, function(run)
		local minp, maxp = mv.slot_area("dungeon", run.slot)
		local layout = dungeoneer.run_layout(run)
		do
			local mobs = made
			check("monsters placed (28 rooms x 3-5)", #mobs >= 28 * 3 - 5 and #mobs <= 28 * 5, tostring(#mobs))
			local kinds, in_start, outside = {}, 0, 0
			local s = layout.start
			for _, o in ipairs(mobs) do
				kinds[o.name] = (kinds[o.name] or 0) + 1
				local p = o.pos
				if math.abs(p.x - (minp.x + s.cx)) <= s.hs and math.abs(p.z - (minp.z + s.cz)) <= s.hs then in_start = in_start + 1 end
				if p.x < minp.x or p.x > maxp.x or p.z < minp.z or p.z > maxp.z then outside = outside + 1 end
				if not o.persistent then check("monster is persistent", false, o.name) end
			end
			local n = 0; for k, v in pairs(kinds) do n = n + 1 end
			check("several kinds for tier 3", n >= 4, core.write_json(kinds))
			check("none in the start room, none outside the slot", in_start == 0 and outside == 0, in_start .. " / " .. outside)
			check("no stray/wither kinds beyond tier 3", kinds["mobs_mc:witherskeleton"] == nil)
			-- tougher with the tier: health multiplier applied
			local e1 = mobs[1].obj:get_luaentity()
			e1.health = 20; e1:receive_damage({ flags = {}, type = "generic" }, 6)
			check("tier 3: damage divided by 1.5 (6 -> 4)", math.abs(e1.health - 16) < 0.01, tostring(e1.health))
			-- no friendly fire: two tagged monsters
			local a = core.add_entity(vector.offset(minp, 5, 20, 5), "mobs_mc:zombie")
			local b = core.add_entity(vector.offset(minp, 6, 20, 5), "mobs_mc:zombie")
			dungeoneer.tag_mob(a, run.id); dungeoneer.tag_mob(b, run.id)
			local eb = b:get_luaentity(); eb.health = 20
			local r = eb:receive_damage({ source = a, direct = a, flags = {}, type = "mob" }, 5)
			check("dungeon monster hurting another: no damage", eb.health == 20 and r == false, tostring(eb.health))
			-- an arrow shot by a dungeon monster (direct = arrow entity with _source_object)
			local arrow = core.add_entity(vector.offset(minp, 7, 20, 5), "mcl_bows:arrow_entity")
			if arrow and arrow:get_luaentity() then
				arrow:get_luaentity()._source_object = a
				eb:receive_damage({ source = a, direct = arrow, flags = {}, type = "arrow" }, 5)
				check("arrow from a dungeon monster: no damage", eb.health == 20, tostring(eb.health))
			end
			-- an untagged monster (a wild mob) can hurt it, and damage without a source still works
			local w = core.add_entity(vector.offset(minp, 8, 20, 5), "mobs_mc:zombie")
			eb:receive_damage({ source = w, direct = w, flags = {}, type = "mob" }, 5)
			check("wild monster can hurt a dungeon monster", eb.health == 15, tostring(eb.health))
			eb:receive_damage({ flags = {}, type = "generic" }, 5)
			check("damage without a source works (fall, fire...)", eb.health == 10, tostring(eb.health))
			a:remove(); b:remove(); w:remove(); if arrow then arrow:remove() end
			dungeoneer.remove_run(run.id)
			log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
			log("SCENARIO_DONE"); core.request_shutdown("done")
		end
	end)
end)
