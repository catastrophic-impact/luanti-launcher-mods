-- Night: one bee per hive, many hive shapes, bees starting 8 and 16 nodes away on the open (+x) side. Every bee must get into its hive.
-- Hives sit on two planes (x = -36 and x = -12), 7 nodes apart in z, so no bee starts inside or passes through another hive's walls.
local function log(s) core.log("action", "[BEES_ENTER_TEST] " .. s) end
local function check(name, cond, extra) log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
bees.find_home = function() return nil end -- no adopting of neighbouring hives: every bee must use its own
local entered = {}
local orig_enter = bees.enter_hive
bees.enter_hive = function(obj, pos)
	local p = obj:get_pos(); local d = p and vector.distance(p, pos)
	local ok = orig_enter(obj, pos)
	if ok then entered[core.hash_node_position(pos)] = d end
	return ok
end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(15, function()
		core.settings:set("time_speed", "0"); core.set_timeofday(0.0) -- midnight, frozen
		local base = vector.offset(vector.round(player:get_pos()), 0, 30, 0)
		player:set_pos(vector.offset(base, 0, 3, 0)); player:set_physics_override({ gravity = 0 })
		core.after(1, function()
			for x = -44, 14 do for y = 0, 12 do for z = -46, 46 do core.set_node(vector.offset(base, x, y, z), { name = y == 0 and "mcl_core:stone" or "air" }) end end end
			local S, L = "mcl_core:stone", "mcl_core:leaves"
			local shapes = { -- neighbour at (+x -x +z -z +y -y)
				{ "open air", {} }, { "on the ground", { [6] = S } }, { "against a wall", { [2] = S, [3] = S, [4] = S } },
				{ "corner pocket", { [2] = S, [3] = S, [4] = S, [5] = S, [6] = S } }, { "under a roof", { [5] = S } },
				{ "leaf cage", { [2] = L, [3] = L, [4] = L, [5] = L, [6] = L } },
			}
			local dirs = { {1,0,0}, {-1,0,0}, {0,0,1}, {0,0,-1}, {0,1,0}, {0,-1,0} }
			local cases = {}
			for plane, dist in ipairs({ 8, 16 }) do
				local idx = 0
				for _, sh in ipairs(shapes) do for _, kind in ipairs({ "mcl_beehives:beehive", "mcl_beehives:bee_nest" }) do
					local hp = vector.offset(base, plane == 1 and -36 or -12, 4, -40 + idx * 7); idx = idx + 1
					for k, d in ipairs(dirs) do core.set_node(vector.offset(hp, d[1], d[2], d[3]), { name = sh[2][k] or "air" }) end
					core.set_node(hp, { name = kind }); core.get_meta(hp):set_int("bees:init", 1); core.get_meta(hp):set_int("bees:count", 0)
					local ang = (math.random() - 0.5) * 1.2
					local bp = vector.add(hp, vector.new(math.cos(ang) * dist, math.random(0, 2), math.sin(ang) * dist))
					local b = core.add_entity(bp, "bees:bee"); local le = b:get_luaentity()
					le._hive = hp; le._out_since = core.get_gametime(); le._forage_for = 9999
					cases[#cases + 1] = { series = {}, name = sh[1] .. " / " .. (kind:find("nest") and "nest" or "beehive") .. " / " .. dist, hp = hp, bee = b }
				end end
			end
			for step = 1, 14 do core.after(step * 5, function()
				for _, c in ipairs(cases) do
					local p = c.bee:get_pos()
					c.series[#c.series + 1] = p and string.format("%.0f", vector.distance(p, c.hp)) or "in"
				end
			end) end
			core.after(75, function()
				local failed = 0
				for _, c in ipairs(cases) do
					local in_hive = bees.hive_count(c.hp) == 1 and c.bee:get_pos() == nil
					if not in_hive then
						failed = failed + 1
						local le = c.bee:get_luaentity()
						log(string.format("STUCK %s: node=%s count=%s dist every 5s: %s | home=%s tries=%s hive=%s", c.name, core.get_node(c.hp).name, tostring(bees.hive_count(c.hp)), table.concat(c.series, " "), tostring(le and le.heading_home), tostring(le and le._home_tries), tostring(le and le._hive ~= nil)))
					else
						log(string.format("ok %s entered at %.2f nodes from the hive centre", c.name, entered[core.hash_node_position(c.hp)] or -1))
					end
				end
				check("every bee went into its hive at night (" .. #cases .. " bees)", failed == 0, failed .. " stuck")
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end)
		end)
	end)
end)
