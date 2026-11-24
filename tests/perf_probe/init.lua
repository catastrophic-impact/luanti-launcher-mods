-- perf_probe: server load scenarios, measured without any client (blocks are forceloaded).
-- Scenario name = worldpath/perf_scenario.txt, duration seconds = worldpath/perf_seconds.txt (default 20).
-- Output lines start with "[PERF_TEST]": RESULT (one summary line), TOP (hottest Lua callbacks), SCENARIO_DONE.
local WP = core.get_worldpath()
local function readf(n) local f = io.open(WP .. "/" .. n, "r"); if not f then return nil end local s = f:read("*l"); f:close(); return s end
local SCEN = readf("perf_scenario.txt") or "idle"
local SNAME, SN = SCEN:match("^(%w+):(%d+)$")
if SNAME then SN = tonumber(SN) else SNAME = SCEN end
local DUR = tonumber(readf("perf_seconds.txt") or "") or 20
local function log(s) core.log("action", "[PERF_TEST] " .. s) end

-- own nodes for the timer / ABM scenarios
core.register_node("perf_probe:timer_node", { description = "perf timer", tiles = { "default_stone.png" },
	on_timer = function(pos) local x = 0; for i = 1, 20 do x = x + i end; return true end })
core.register_node("perf_probe:abm_node", { description = "perf abm", tiles = { "default_stone.png" } })
local abm_hits = 0
core.register_abm({ label = "perf abm", nodenames = { "perf_probe:abm_node" }, interval = 1, chance = 1,
	action = function(pos) abm_hits = abm_hits + 1 end })

local function dumb_def(with_step)
	return { initial_properties = { visual = "cube", visual_size = { x = 0.3, y = 0.3, z = 0.3 }, textures = { "default_stone.png", "default_stone.png", "default_stone.png", "default_stone.png", "default_stone.png", "default_stone.png" },
		physical = false, collisionbox = { -0.15, -0.15, -0.15, 0.15, 0.15, 0.15 }, static_save = false },
		on_activate = function(self) self.object:set_velocity({ x = 0.3, y = 0, z = 0.2 }) end,
		on_step = with_step and function(self, dtime) self.t = (self.t or 0) + dtime end or nil }
end
core.register_entity("perf_probe:dumb", dumb_def(true))   -- trivial Lua on_step
core.register_entity("perf_probe:mute", dumb_def(false))  -- no Lua step at all
local S = {} -- scenarios: function(ground_pos) sets the scene up
local function node(...) for _, n in ipairs({ ... }) do if core.registered_nodes[n] then return n end end return "air" end
local R = PcgRandom(12345)
function S.idle(g) end
function S.mobs(g)
	local names = {}
	for _, n in ipairs({ "mobs_mc:cow", "mobs_mc:pig", "mobs_mc:sheep", "mobs_mc:chicken", "mobs_mc:zombie" }) do
		if core.registered_entities[n] then names[#names + 1] = n end
	end
	local N = SN or 150
	for i = 1, N do
		core.add_entity({ x = g.x + R:next(-30, 30), y = g.y + 1, z = g.z + R:next(-30, 30) }, names[(i % #names) + 1])
	end
	log("NOTE spawned " .. N .. " mobs of " .. table.concat(names, ","))
end
local function spawn_n(name, g)
	for i = 1, (SN or 3000) do
		core.add_entity({ x = g.x + R:next(-40, 40), y = g.y + 2 + R:next(0, 10), z = g.z + R:next(-40, 40) }, name)
	end
end
function S.dumb(g) spawn_n("perf_probe:dumb", g) end
function S.mute(g) spawn_n("perf_probe:mute", g) end
local redstone_blocks = {}
function S.redstone(g) -- SN lines (default 20) of 30 dust, each fed by a power block toggled every second. 90 lines per layer, layers 3 apart, all inside the loaded +-47 area.
	local wire
	for n in pairs(core.registered_nodes) do if n:match("^mcl_redstone:wire_") and (not wire or n < wire) then wire = n end end
	if not wire then log("SCENARIO_ABORT no mcl_redstone wire node") return end
	local stone = node("mcl_core:stone")
	local lines = SN or 20
	for l = 0, lines - 1 do
		local layer, k = math.floor(l / 90), l % 90
		local col, row = k % 2, math.floor(k / 2)             -- two columns of 45 rows
		local x0 = col == 0 and -44 or 15
		local y, z = g.y + 1 + layer * 3, g.z - 44 + row * 2
		redstone_blocks[#redstone_blocks + 1] = { x = x0, y = y, z = z }
		core.set_node({ x = x0, y = y, z = z }, { name = stone })       -- the power block replaces this stone when "on"
		for x = 1, 30 do
			core.set_node({ x = x0 + x, y = y - 1, z = z }, { name = stone })
			core.set_node({ x = x0 + x, y = y, z = z }, { name = wire })
		end
	end
	local on, logged = false, 0
	local last = { x = redstone_blocks[1].x + 12, y = redstone_blocks[1].y, z = redstone_blocks[1].z }
	local function toggle()
		on = not on
		local before = core.get_node(last).param2 % 16 -- redstone power lives in the low 4 bits of param2
		local t0 = core.get_us_time()
		local function poll()
			if core.get_node(last).param2 % 16 ~= before then
				if logged < 4 then log(string.format("NOTE redstone propagation to dust #12 of line 1: %.0f ms (%s)", (core.get_us_time() - t0) / 1000, on and "on" or "off")) end
				logged = logged + 1
			elseif core.get_us_time() - t0 < 900000 then core.after(0.05, poll)
			else log("NOTE redstone signal did NOT reach dust #12 within 900 ms") end
		end
		core.after(0.05, poll)
		for _, bp in ipairs(redstone_blocks) do core.set_node(bp, { name = on and "mcl_redstone_torch:redstoneblock" or stone }) end
		core.after(1, toggle)
	end
	core.after(1, toggle)
	log("NOTE redstone: " .. #redstone_blocks .. " lines x 30 dust = " .. (#redstone_blocks * 30) .. " dust, toggled every 1 s, wire node " .. wire)
end
function S.items(g)
	local it = node("mcl_core:cobble", "mcl_core:stone")
	for i = 1, (SN or 1500) do
		core.add_item({ x = g.x + R:next(-15, 15), y = g.y + 2 + R:next(0, 6), z = g.z + R:next(-15, 15) }, it)
	end
end
function S.falling(g)
	local sand = node("mcl_core:sand")
	for x = -10, 9 do for z = -10, 9 do for y = 20, 23 do core.set_node({ x = g.x + x, y = g.y + y, z = g.z + z }, { name = sand }) end end end
	for x = -10, 9 do for z = -10, 9 do core.check_for_falling({ x = g.x + x, y = g.y + 20, z = g.z + z }) end end
end
function S.liquid(g)
	local w = node("mcl_core:water_source")
	for x = -15, 14 do for z = -15, 14 do for y = -6, 0 do core.set_node({ x = g.x + x, y = g.y + y, z = g.z + z }, { name = "air" }) end end end
	for x = -15, 14 do core.set_node({ x = g.x + x, y = g.y, z = g.z - 15 }, { name = w }) end
end
function S.timers(g)
	for i = 0, 2999 do
		local p = { x = g.x - 25 + (i % 50), y = g.y + 30 + math.floor(i / 2500), z = g.z - 25 + math.floor(i / 50) % 50 }
		core.set_node(p, { name = "perf_probe:timer_node" }); core.get_node_timer(p):start(1)
	end
end
function S.abms(g)
	for i = 0, 2999 do
		core.set_node({ x = g.x - 25 + (i % 50), y = g.y + 30 + math.floor(i / 2500), z = g.z - 25 + math.floor(i / 50) % 50 }, { name = "perf_probe:abm_node" })
	end
end

-- measurement
local steps, sum, mx, over, budget = 0, 0, 0, 0, tonumber(core.settings:get("dedicated_server_step")) or 0.09
local lagmax, lagsum, lagn = 0, 0, 0
local measuring = false
core.register_globalstep(function(dtime)
	if not measuring then return end
	steps = steps + 1; sum = sum + dtime; if dtime > mx then mx = dtime end
	if dtime > 0.1 then over = over + 1 end
end)
local function count_entities() local n = 0 for _ in pairs(core.luaentities) do n = n + 1 end return n end

local function finish()
	measuring = false
	local avg = steps > 0 and sum / steps or 0
	local prof = core.registered_chatcommands["profiler"]
	log(string.format("RESULT scenario=%s secs=%d steps_per_s=%.1f avg_step_ms=%.1f max_step_ms=%.1f slow_steps(>100ms)=%d max_lag_avg=%.3f max_lag_peak=%.3f entities=%d abm_hits=%d redstone_pending=%s",
		SCEN, DUR, steps / DUR, avg * 1000, mx * 1000, over, lagn > 0 and lagsum / lagn or 0, lagmax, count_entities(), abm_hits, (rawget(_G, "mcl_redstone") and (function() local n = 0 for _ in pairs(mcl_redstone._pending_updates) do n = n + 1 end return n end)() or "n/a")))
	if prof then
		local ok, msg = prof.func("perf", "save json")
		local path = type(msg) == "string" and msg:match("(/%S+%.json)") or nil
		local f = path and io.open(path, "r")
		if f then
			local data = core.parse_json(f:read("*a")); f:close()
			local rows, total = {}, 0
			for mod, st in pairs(data or {}) do
				if mod ~= "??" then -- the profiler lists entity callbacks twice (once under "??")
				for what, v in pairs(st.instruments or {}) do
					rows[#rows + 1] = { k = mod .. " " .. what, t = v.time_all or 0, c = v.samples }
					total = total + (v.time_all or 0)
				end
				end
			end
			table.sort(rows, function(a, b) return a.t > b.t end)
			log(string.format("LUA instrumented_lua_ms=%.0f of wall_ms=%d (%.1f%% of one thread)", total / 1000, DUR * 1000, total / 1000 / (DUR * 1000) * 100))
			for i = 1, math.min(8, #rows) do log(string.format("TOP %d %s total_ms=%.0f calls=%s", i, rows[i].k, rows[i].t / 1000, tostring(rows[i].c))) end
			if #rows == 0 then log("NOTE profiler JSON had no rows with time_us; keys: " .. tostring(path)) end
		else log("NOTE profiler save: " .. tostring(msg)) end
	else log("NOTE profiler not loaded (set profiler.load = true)") end
	log("SCENARIO_DONE")
	core.request_shutdown("perf done", false, 0)
end

local function start_measure()
	local prof = core.registered_chatcommands["profiler"]
	if prof then prof.func("perf", "reset") end
	steps, sum, mx, over, lagmax, lagsum, lagn = 0, 0, 0, 0, 0, 0, 0
	measuring = true
	local t = 0
	local function tick()
		t = t + 1
		local l = core.get_server_max_lag() or 0
		lagsum = lagsum + l; lagn = lagn + 1; if l > lagmax then lagmax = l end
		if t >= DUR then finish() else core.after(1, tick) end
	end
	core.after(1, tick)
end

core.after(0.5, function()
	local minp, maxp = { x = -48, y = -64, z = -48 }, { x = 47, y = 64, z = 47 }
	core.emerge_area(minp, maxp, function(_, _, remaining)
		if remaining > 0 then return end
		for bx = -3, 2 do for bz = -3, 2 do for by = -4, 4 do core.forceload_block({ x = bx * 16, y = by * 16, z = bz * 16 }, true) end end end
		local g
		for y = 64, -64, -1 do if core.get_node({ x = 0, y = y, z = 0 }).name ~= "air" then g = { x = 0, y = y, z = 0 } break end end
		g = g or { x = 0, y = 0, z = 0 }
		log("NOTE ground y=" .. g.y .. " scenario=" .. SCEN)
		if not S[SNAME] then log("SCENARIO_ABORT unknown scenario " .. SCEN) core.request_shutdown("bad scenario", false, 0) return end
		S[SNAME](g)
		core.after(4, start_measure) -- let the scene settle for 4 s, then measure
	end)
end)
