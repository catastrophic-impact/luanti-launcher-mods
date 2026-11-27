-- The Dungeon dimension (a band under the Overworld), its slot pool, and runs (one dungeon each, in its own slot).
-- Runs are saved in mod storage as { id = { tier, slot, seed, created } }; the layout is recomputed from the seed.
local storage = core.get_mod_storage()
local mv = multiversatile
local SLOTS = 10
local SZ = dungeoneer.slot_size

-- the dimension -------------------------------------------------------------------------------------------------------------
local function setup_dimension()
	local ow = mv.get("overworld")
	local gap
	for _, g in ipairs(mv.gaps()) do if g.ymax == ow.ymin - 1 then gap = g end end
	if not gap then error("[dungeoneer] no free height gap under the Overworld") end
	local C, O = mcl_vars.chunk_size_in_nodes, mcl_vars.central_chunk_offset_in_nodes
	local ymin = storage:get_int("band_ymin")
	if ymin == 0 then
		ymin = O + math.ceil((gap.ymin + 2 * C - O) / C) * C -- two chunks of margin above the gap's bottom
		storage:set_int("band_ymin", ymin)
	end
	local err = mv.register{
		name = "dungeon", transient = true, ymin = ymin, ymax = ymin + 2 * C - 1, build_max = ymin + SZ.y - 1,
		slots = { count = SLOTS, size = SZ, gap = C },
		look = { -- dark and closed in: no sky, no sun, no moon, no stars, no clouds, no weather light
			sky = { type = "plain", base_color = "#000000", clouds = false },
			sun = { visible = false, sunrise_visible = false }, moon = { visible = false }, stars = { visible = false },
			clouds = { density = 0 }, ratio = 0, night_vision_ratio = 0.7 },
	}
	if err then error("[dungeoneer] " .. err) end
end
setup_dimension()

-- runs ------------------------------------------------------------------------------------------------------------------------
local function load_runs() local t = core.parse_json(storage:get_string("runs") ~= "" and storage:get_string("runs") or "{}"); return type(t) == "table" and t or {} end
local function save_runs(t) storage:set_string("runs", core.write_json(t)) end
local function next_id() local n = storage:get_int("next_id") + 1; storage:set_int("next_id", n); return n end

function dungeoneer.runs() return load_runs() end
function dungeoneer.update_run(run) local t = load_runs(); if t[tostring(run.id)] then t[tostring(run.id)] = run; save_runs(t) end end

-- settings (per world, mod storage); the settings screen comes later
function dungeoneer.reset_minutes() local n = storage:get_int("reset_minutes"); return n > 0 and n or 10 end
function dungeoneer.reset_on_death() return storage:get_string("reset_on_death") == "true" end
function dungeoneer.grave_grace_minutes() local v = storage:get_string("grave_grace_minutes"); return v == "" and 60 or (tonumber(v) or 60) end
dungeoneer.setting_limits = { reset_minutes = { 1, 1440 }, grave_grace_minutes = { 0, 10080 } }
-- name, value (string or bool) -> true | false, reason
function dungeoneer.set_setting(name, value)
	if name == "reset_on_death" then
		if value == "true" or value == true then storage:set_string(name, "true") elseif value == "false" or value == false then storage:set_string(name, "false") else return false, "true or false" end
		return true
	end
	local lim = dungeoneer.setting_limits[name]
	local n = tonumber(value)
	if not lim then return false, "unknown setting" end
	if not n or n ~= math.floor(n) or n < lim[1] or n > lim[2] then return false, ("a whole number from %d to %d"):format(lim[1], lim[2]) end
	storage:set_string(name, tostring(n))
	return true
end

-- A block with contents left in a run (a chest, a grave, a barrel ...; our own loot chest does not count) keeps it alive a while longer.
function dungeoneer.has_contents(run)
	local minp, maxp = mv.slot_area("dungeon", run.slot)
	for _, p in ipairs(core.find_nodes_with_meta(minp, maxp)) do
		local m = core.get_meta(p)
		if m:get_int("dungeoneer_run") == 0 then
			local inv = m:get_inventory()
			for list, stacks in pairs(inv:get_lists()) do
				for _, st in ipairs(stacks) do if not st:is_empty() then return true end end
			end
		end
	end
	return false
end

-- players whose position is inside a run's slot area
function dungeoneer.players_inside(run)
	local minp, maxp = mv.slot_area("dungeon", run.slot)
	local t = {}
	for _, p in ipairs(core.get_connected_players()) do
		local pos = p:get_pos()
		if pos.x >= minp.x and pos.x <= maxp.x + 1 and pos.y >= minp.y and pos.y <= maxp.y + 1 and pos.z >= minp.z and pos.z <= maxp.z + 1 then t[#t + 1] = p:get_player_name() end
	end
	return t
end

-- seconds until an empty run closes (nil while somebody is inside or while the timer has not started)
dungeoneer.empty_since = {} -- run id -> os.time() (memory only: after a restart the timer starts again)
function dungeoneer.seconds_left(run)
	local since = dungeoneer.empty_since[run.id]
	if not since then return nil end
	local minutes = dungeoneer.reset_minutes()
	if dungeoneer.has_contents(run) then minutes = minutes + dungeoneer.grave_grace_minutes() end
	return math.max(0, since + minutes * 60 - os.time())
end
function dungeoneer.run_layout(run) return dungeoneer.layout(run.seed, run.tier) end

-- Build a new dungeon (type "castle") of a tier. cb(run) or cb(nil, reason).
function dungeoneer.new_run(tier, cb)
	local id = next_id()
	local slot, minp, maxp = mv.slot_alloc("dungeon", "run" .. id)
	if not slot then if cb then cb(nil, "all " .. SLOTS .. " dungeon slots are in use") end return end
	local run = { id = id, tier = tier, slot = slot, seed = math.random(1, 2 ^ 30), created = os.time() }
	local runs = load_runs(); runs[tostring(id)] = run; save_runs(runs)
	local layout = dungeoneer.run_layout(run)
	dungeoneer.build(minp, maxp, layout, function()
		dungeoneer.light_exits(run, minp, layout)
		dungeoneer.spawn_mobs(run, minp, layout)
		dungeoneer.spawn_boss(run, minp, layout)
		dungeoneer.setup_chest(run, minp, layout)
		if cb then cb(run) end
	end)
end

function dungeoneer.run_start_pos(run)
	local minp = mv.slot_area("dungeon", run.slot)
	local sp = dungeoneer.run_layout(run).start_pos
	return vector.new(minp.x + sp.x, minp.y + sp.y, minp.z + sp.z)
end

-- Remove a run: clean its slot (refuses while a player is inside), then free it. Returns true/false+reason at once; cb(true) when it is gone.
function dungeoneer.remove_run(id, cb)
	local runs = load_runs(); local run = runs[tostring(id)]
	if not run then return false, "no such dungeon" end
	if run.removing then return true end
	local ok, why = mv.slot_clean("dungeon", run.slot, function()
		mv.slot_free("dungeon", run.slot)
		local t = load_runs(); t[tostring(id)] = nil; save_runs(t)
		if cb then cb(true) end
	end)
	if not ok then return false, why end
	run.removing = true; runs[tostring(id)] = run; save_runs(runs)
	return true
end

-- lifecycle: an empty run closes (portal goes out, dungeon removed) after reset_minutes; a run whose portal was closed goes as soon as it is empty
local tick = 0
core.register_globalstep(function(dtime)
	tick = tick + dtime
	if tick < 2 then return end
	tick = 0
	for id, run in pairs(load_runs()) do
		if run.removing then -- already being cleaned
		elseif #dungeoneer.players_inside(run) > 0 then
			dungeoneer.empty_since[run.id] = nil
		else
			dungeoneer.empty_since[run.id] = dungeoneer.empty_since[run.id] or os.time()
			if run.closed or (run.death and dungeoneer.reset_on_death()) or dungeoneer.seconds_left(run) == 0 then
				if dungeoneer.close_portal then dungeoneer.close_portal(run) end
				dungeoneer.remove_run(run.id)
				dungeoneer.empty_since[run.id] = nil
			end
		end
	end
end)

-- a player who dies inside a run marks it (reset_on_death: it resets as soon as it is empty)
core.register_on_dieplayer(function(player)
	local pos = player:get_pos()
	for _, run in pairs(load_runs()) do
		local minp, maxp = mv.slot_area("dungeon", run.slot)
		if pos.x >= minp.x and pos.x <= maxp.x + 1 and pos.y >= minp.y and pos.y <= maxp.y + 1 and pos.z >= minp.z and pos.z <= maxp.z + 1 then
			run.death = true; dungeoneer.update_run(run)
		end
	end
end)

-- monsters of a run that is gone (left in saved chunks, found when they load) are removed
local sweep = 0
core.register_globalstep(function(dtime)
	sweep = sweep + dtime
	if sweep < 10 then return end
	sweep = 0
	local runs = load_runs()
	for _, e in pairs(core.luaentities) do
		if e._dg_run and not runs[tostring(e._dg_run)] and e.object and e.object:get_pos() then e.object:remove() end
	end
end)

-- commands (operators) -----------------------------------------------------------------------------------------------------
core.register_chatcommand("dungeon", {
	params = "spawn castle <tier 1-4> | list | leave | reset <id> | setting <name> <value> | settings", privs = { server = true },
	description = "Dungeoneer: build, list, leave or remove dungeons",
	func = function(name, param)
		local player = core.get_player_by_name(name)
		local a, b, c = param:match("^(%S*)%s*(%S*)%s*(%S*)")
		if a == "spawn" then
			local tier = tonumber(c)
			if b ~= "castle" or not tier or tier < 1 or tier > 4 or tier ~= math.floor(tier) then return false, "usage: /dungeon spawn castle <1-4>" end
			dungeoneer.new_run(tier, function(run, why)
				if not run then return core.chat_send_player(name, why) end
				if player and player:is_valid() then
					mv.go(player, dungeoneer.run_start_pos(run), { yaw = 0 }, function() core.chat_send_player(name, "Dungeon " .. run.id .. " (tier " .. tier .. ") built.") end)
				end
			end)
			return true, "Building..."
		elseif a == "list" then
			local lines = {}
			for id, run in pairs(load_runs()) do lines[#lines + 1] = ("#%s tier %d slot %d"):format(id, run.tier, run.slot) end
			table.sort(lines)
			return true, #lines == 0 and "No dungeons." or table.concat(lines, "\n")
		elseif a == "leave" then
			if not player then return false end
			mv.back(player); return true
		elseif a == "setting" then
			if b == "" then return false, "usage: /dungeon setting reset_minutes <1-1440> | reset_on_death <true|false> | grave_grace_minutes <0-10080>" end
			local ok, why = dungeoneer.set_setting(b, c)
			return ok, ok and (b .. " = " .. c) or why
		elseif a == "settings" then
			dungeoneer.settings_screen.show(name); return true
		elseif a == "reset" then
			local id = tonumber(b)
			if not id then return false, "usage: /dungeon reset <id>" end
			local ok, why = dungeoneer.remove_run(id)
			return ok, ok and ("Dungeon " .. id .. " is being removed.") or why
		end
		return false, "usage: /dungeon spawn castle <1-4> | list | leave | reset <id>"
	end,
})
