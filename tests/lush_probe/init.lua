-- Probe: generate the lush cave area of the dad_survival seed and count dropped plant items (with / without the luanti_fixes guard).
local P = "[LUSH_PROBE] "
local function log(s) core.log("action", P .. s) end
local nofix = core.settings:get_bool("lush_probe_nofix", false)
if nofix then core.register_on_mods_loaded(function()
	if luanti_fixes_orig_flood then
		local f = luanti_fixes_orig_flood
		mcl_core.basic_flood = f
		for name, def in pairs(core.registered_nodes) do if def.on_flood then core.override_item(name, {on_flood = f}) end end
	end
end) end
local by = {}
local oadd = core.add_item
core.add_item = function(pos, item)
	local tb = debug.traceback("", 2):gsub("\n%s*", " | "):sub(1, 330)
	local k = tb:match("^%s*|?%s*(.-) | .-$") or tb
	by[tb] = (by[tb] or 0) + 1
	return oadd(pos, item)
end
core.after(40, function() end)
local function dump() local t = {} for k, v in pairs(by) do t[#t+1] = {v, k} end table.sort(t, function(a, b) return a[1] > b[1] end) for i = 1, math.min(4, #t) do log("ADD x" .. t[i][1] .. " " .. t[i][2]) end end
log("guard " .. (nofix and "OFF" or "ON"))
core.register_on_joinplayer(function(player)
	core.after(5, function()
		local c = vector.new(-137, -85, -153)
		player:set_pos(c)
		local p1, p2 = vector.offset(c, -112, -48, -112), vector.offset(c, 112, 48, 112)
		core.emerge_area(p1, p2, function(_, _, remaining)
			if remaining == 0 then
				log("emerged")
				core.after(25, function()
					local items, kinds = 0, {}
					for _, o in pairs(core.object_refs) do
						local e = o:get_luaentity()
						if e and e.name == "__builtin:item" then
							items = items + 1
							local n = ItemStack(e.itemstring):get_name()
							kinds[n] = (kinds[n] or 0) + 1
						end
					end
					local lush = #core.find_nodes_in_area(p1, p2, {"mcl_lush_caves:moss_carpet", "mcl_lush_caves:azalea", "mcl_lush_caves:dripleaf_big", "mcl_lush_caves:moss"})
					log("lush nodes in area: " .. lush .. ", item entities: " .. items .. " " .. core.serialize(kinds))
					dump(); log("SCENARIO_DONE"); core.request_shutdown("done")
				end)
			end
		end)
	end)
end)
