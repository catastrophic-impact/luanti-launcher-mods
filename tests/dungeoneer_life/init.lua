local function log(s) core.log("action", "[DG_LIFE_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
local function wait(cond, cb, tries) tries = tries or 40; if cond() then return cb() end
	if tries <= 0 then check("wait timed out", false); return cb() end
	core.after(0.5, function() wait(cond, cb, tries - 1) end) end
local function run_count() local n = 0; for _ in pairs(dungeoneer.runs()) do n = n + 1 end; return n end

core.after(2, function()
	-- settings
	check("defaults: 10 min, 60 grace, reset_on_death off", dungeoneer.reset_minutes() == 10 and dungeoneer.grave_grace_minutes() == 60 and dungeoneer.reset_on_death() == false)
	check("set reset_minutes 5", dungeoneer.set_setting("reset_minutes", "5") and dungeoneer.reset_minutes() == 5)
	check("reset_minutes 0 / 2000 / abc refused", not dungeoneer.set_setting("reset_minutes", "0") and not dungeoneer.set_setting("reset_minutes", "2000") and not dungeoneer.set_setting("reset_minutes", "abc") and dungeoneer.reset_minutes() == 5)
	check("grave_grace_minutes 0..10080", dungeoneer.set_setting("grave_grace_minutes", "0") and dungeoneer.set_setting("grave_grace_minutes", "10080") and not dungeoneer.set_setting("grave_grace_minutes", "10081"))
	dungeoneer.set_setting("grave_grace_minutes", "60")
	check("reset_on_death true/false, junk refused", dungeoneer.set_setting("reset_on_death", "true") and dungeoneer.reset_on_death() and dungeoneer.set_setting("reset_on_death", "false") and not dungeoneer.reset_on_death() and not dungeoneer.set_setting("reset_on_death", "maybe"))
	local cmd = core.registered_chatcommands.dungeon
	local ok = cmd.func("nobody", "setting reset_minutes 7")
	check("/dungeon setting works", ok == true and dungeoneer.reset_minutes() == 7)
	dungeoneer.set_setting("reset_minutes", "10")

	dungeoneer.new_run(1, function(run)
		local minp, maxp = mv.slot_area("dungeon", run.slot)
		local L = dungeoneer.run_layout(run)
		-- grave grace: our own loot chest does not count; a chest with items does
		check("no contents at first (the boss chest does not count)", dungeoneer.has_contents(run) == false)
		local cp = vector.new(minp.x + L.start.cx + 2, minp.y + L.start.y0, minp.z + L.start.cz + 2)
		core.set_node(cp, { name = "mcl_chests:chest_small" })
		core.get_meta(cp):get_inventory():set_stack("main", 1, ItemStack("mcl_core:diamond 2"))
		check("a chest with items counts", dungeoneer.has_contents(run) == true)
		dungeoneer.empty_since[run.id] = os.time() - 11 * 60
		local left = dungeoneer.seconds_left(run)
		check("grace: 11 min empty, 10 + 60 allowed -> ~59 min left", left > 58 * 60 and left <= 59 * 60 + 5, tostring(left))
		core.get_meta(cp):get_inventory():set_list("main", {})
		check("chest emptied: no grace, time is up", dungeoneer.has_contents(run) == false and dungeoneer.seconds_left(run) == 0)
		-- reset on death
		dungeoneer.set_setting("reset_on_death", "true")
		dungeoneer.empty_since[run.id] = os.time()
		local r = dungeoneer.runs()[tostring(run.id)]; r.death = true; dungeoneer.update_run(r)
		wait(function() return run_count() == 0 end, function()
			check("reset_on_death: empty run with a death is removed at once", run_count() == 0)
			dungeoneer.set_setting("reset_on_death", "false")
			-- sweep: a monster tagged with a run that does not exist is removed
			dungeoneer.new_run(1, function(run2)
				local m2 = mv.slot_area("dungeon", run2.slot)
				local obj = core.add_entity(vector.offset(m2, 20, 20, 20), "mobs_mc:zombie")
				dungeoneer.tag_mob(obj, 9999)
				wait(function() return not obj:get_pos() end, function()
					check("leftover monster of a run that is gone is removed", not obj:get_pos())
					dungeoneer.remove_run(run2.id)
					log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
					log("SCENARIO_DONE"); core.request_shutdown("done")
				end, 40)
			end)
		end, 20)
	end)
end)
