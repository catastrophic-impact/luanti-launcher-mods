-- Probe: do far-flung item entities get activated twice (duplicate GUID error)?
local P = "[DUP_PROBE] "
local function log(s) core.log("action", P .. s) end
core.register_on_joinplayer(function(player)
	core.after(15, function()
		local base = vector.new(0, 8, 0)
		player:set_pos(base)
		local n = 0
		for i = 1, 24 do
			local a = i * math.pi / 12
			local o = core.add_item(vector.offset(base, 0, 2, 0), "mcl_core:stick")
			if o then
				n = n + 1
				-- fast outward + downward, to cross the active range
				o:set_velocity(vector.new(math.cos(a) * 40, -10, math.sin(a) * 40))
			end
		end
		log("spawned " .. n .. " items")
		core.after(8, function()
			player:set_pos(vector.new(900, 8, 900)) -- far: items outside range get deactivated
			log("player moved far")
			core.after(10, function()
				player:set_pos(base)
				log("player back")
				core.after(10, function()
					local c = 0
					for _, o in pairs(core.object_refs) do
						local e = o:get_luaentity()
						if e and e.name == "__builtin:item" then c = c + 1 end
					end
					log("items alive: " .. c)
					log("SCENARIO_DONE"); core.request_shutdown("done")
				end)
			end)
		end)
	end)
end)
