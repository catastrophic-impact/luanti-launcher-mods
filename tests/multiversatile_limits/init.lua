local function log(s) core.log("action", "[MV_LIMITS_TEST] " .. s) end
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end; log((cond and "PASS " or "FAIL ") .. name .. (extra and (" (" .. extra .. ")") or "")) end
local mv = multiversatile
multiversatile.message_interval_us = 0
local bars = {}
local orig = mcl_title.set
mcl_title.set = function(p, t, d) if t == "actionbar" then bars[#bars + 1] = d.text end return orig(p, t, d) end

local function try_place(player, under, above)
	local stack = ItemStack("mcl_core:stone 5")
	local left = core.item_place_node(stack, player, { type = "node", under = under, above = above })
	return left
end

local function emerge(p, cb)
	core.emerge_area(vector.offset(p, -3, -3, -3), vector.offset(p, 3, 3, 3), function(_, _, remaining) if remaining == 0 then cb() end end)
end

-- one dimension: floor at limit-1... place at the top (allowed), above the top (refused), dig above (allowed), a deep position (allowed)
local function run_dim(player, name, d, y_top, y_low, done)
	local x, z = 0, 0
	local top = { x = x, y = y_top, z = z }
	emerge(top, function()
		core.set_node(vector.offset(top, 0, -1, 0), { name = "mcl_core:stone" })
		core.set_node(top, { name = "air" }); core.set_node(vector.offset(top, 0, 1, 0), { name = "air" })
		-- at the limit: allowed
		try_place(player, vector.offset(top, 0, -1, 0), top)
		check(name .. ": placing AT the limit y=" .. y_top .. " works", core.get_node(top).name == "mcl_core:stone", core.get_node(top).name)
		-- above the limit: refused, item kept, message shown
		local n0 = #bars; local gate = 0
		local above = vector.offset(top, 0, 1, 0)
		local left = try_place(player, top, above)
		check(name .. ": placing above the limit is refused", core.get_node(above).name == "air", core.get_node(above).name)
		check(name .. ": item not used up", left and left:get_count() == 5, left and tostring(left:get_count()))
		check(name .. ": message shown", #bars > n0 and bars[#bars]:find("Height limit for building is " .. d.build_max, 1, true) ~= nil, tostring(bars[#bars]))
		-- breaking a block above the limit is allowed
		core.set_node(above, { name = "mcl_core:stone" })
		core.node_dig(above, core.get_node(above), player)
		check(name .. ": digging above the limit is allowed", core.get_node(above).name == "air", core.get_node(above).name)
		-- low inside the band: allowed
		local low = { x = x + 2, y = y_low, z = z }
		emerge(low, function()
			core.set_node(vector.offset(low, 0, -1, 0), { name = "mcl_core:stone" }); core.set_node(low, { name = "air" })
			try_place(player, vector.offset(low, 0, -1, 0), low)
			check(name .. ": placing low in the band works (y=" .. y_low .. ")", core.get_node(low).name == "mcl_core:stone")
			done()
		end)
	end)
end

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(12, function()
		core.set_player_privs("tester", { interact = true, shout = true, server = true, creative = true })
		local ow, ne, en = mv.get("overworld"), mv.get("nether"), mv.get("end")
		log("NOTE limits: overworld " .. ow.build_min .. ".." .. ow.build_max .. ", nether " .. ne.build_min .. ".." .. ne.build_max .. ", end " .. en.build_min .. ".." .. en.build_max)
		-- a custom dimension in the gap under the overworld, limit 40 nodes into the band
		local g = mv.gaps(); local gap = g[#g - 1]
		check("custom registration", mv.register{ name = "limdim", ymin = gap.ymin + 200, ymax = gap.ymin + 399, build_max = gap.ymin + 240 } == nil)
		local ld = mv.get("limdim")
		local steps = {
			function(nxt) run_dim(player, "overworld", ow, ow.build_max, ow.build_min + 40, nxt) end,
			function(nxt) run_dim(player, "nether", ne, ne.build_max, ne.build_min + 40, nxt) end,
			function(nxt) run_dim(player, "end", en, en.build_max, en.build_min + 40, nxt) end,
			function(nxt) run_dim(player, "limdim", ld, ld.build_max, ld.ymin + 10, nxt) end,
			function(nxt) -- void: no limit
				local p = { x = 0, y = gap.ymin + 20, z = 0 }
				emerge(p, function()
					core.set_node(vector.offset(p, 0, -1, 0), { name = "mcl_core:stone" })
					check("void: no limit from us", mv.can_build(p) and select(2, mcl_worlds.y_to_layer(p.y)) == "void")
					log("NOTE the void is filled with " .. core.get_node(p).name .. " by Mineclonia (not buildable-to); a dimension of ours has to generate its own terrain")
					nxt()
				end)
			end,
		}
		local i = 0
		local function nxt()
			i = i + 1
			if steps[i] then steps[i](nxt) else
				log("== " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")) .. " ==")
				log("SCENARIO_DONE"); core.request_shutdown("done")
			end
		end
		nxt()
	end)
end)
