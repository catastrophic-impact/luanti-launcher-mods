-- The portal: a 4x4 ring of frames (corners optional) around a 2x2 opening, standing up in either direction. A key lights it (and builds a
-- dungeon of the key's tier); every lit portal has its own dungeon (portal nodes carry the run id in their metadata).
local S = core.get_translator("dungeoneer")
local mv = multiversatile

local function portal_box() return { type = "fixed", fixed = { -0.5, -0.5, -0.0625, 0.5, 0.5, 0.0625 } } end
for _, axis in ipairs({ "x", "z" }) do
	core.register_node("dungeoneer:portal_" .. axis, {
		description = S("Dungeon Portal"),
		drawtype = "nodebox", node_box = portal_box(), selection_box = { type = "fixed", fixed = { 0, 0, 0, 0, 0, 0 } },
		tiles = { { name = "dungeoneer_portal.png", backface_culling = false } },
		use_texture_alpha = "blend", paramtype = "light", paramtype2 = "facedir", sunlight_propagates = true, light_source = 11,
		walkable = false, pointable = false, diggable = false, buildable_to = false, is_ground_content = false,
		-- param2 rotates the plane: facedir 0 = plane along x (thin in z), facedir 1 = plane along z
		groups = { not_in_creative_inventory = 1, unmovable_by_piston = 1 },
		drop = "", on_blast = function() end,
	})
end
local portal_param2 = { x = 0, z = 1 }
local function is_portal(name) return name == "dungeoneer:portal_x" or name == "dungeoneer:portal_z" end

-- ring cells for an opening whose lower corner is `o`: axis x -> plane x/y, axis z -> plane z/y
local function cell(o, axis, i, j) if axis == "x" then return vector.new(o.x + i, o.y + j, o.z) else return vector.new(o.x, o.y + j, o.z + i) end end
local ring = {}
for i = -1, 2 do for j = -1, 2 do
	local corner = (i == -1 or i == 2) and (j == -1 or j == 2)
	local opening = i >= 0 and i <= 1 and j >= 0 and j <= 1
	if not corner and not opening then ring[#ring + 1] = { i, j } end
end end

local function find_portal(pos)
	for _, axis in ipairs({ "x", "z" }) do
		for a = -2, 2 do for b = -3, 2 do
			local o = axis == "x" and vector.new(pos.x + a, pos.y + b, pos.z) or vector.new(pos.x, pos.y + b, pos.z + a)
			local ok, has = true, false
			for _, r in ipairs(ring) do
				local c = cell(o, axis, r[1], r[2])
				if core.get_node(c).name ~= "dungeoneer:frame" then ok = false; break end
				if vector.equals(c, pos) then has = true end
			end
			if ok and has then
				for i = 0, 1 do for j = 0, 1 do
					local n = core.get_node(cell(o, axis, i, j)).name
					if not (n == "air" or is_portal(n)) then ok = false end
				end end
				if ok then return { axis = axis, origin = o } end
			end
		end end
	end
end
dungeoneer.find_portal = find_portal

local function opening_cells(p)
	local t = {}
	for i = 0, 1 do for j = 0, 1 do t[#t + 1] = cell(p.origin, p.axis, i, j) end end
	return t
end

local function light(p, run)
	for _, c in ipairs(opening_cells(p)) do
		core.set_node(c, { name = "dungeoneer:portal_" .. p.axis, param2 = portal_param2[p.axis] })
		core.get_meta(c):set_int("dungeoneer_run", run.id)
	end
end

local function say(player, text)
	if rawget(_G, "mcl_title") then mcl_title.set(player, "actionbar", { text = text, color = "white", stay = 60 }) else core.chat_send_player(player:get_player_name(), text) end
end

-- the run lit in this portal (read from any opening cell)
local function portal_run(p)
	for _, c in ipairs(opening_cells(p)) do
		if is_portal(core.get_node(c).name) then
			local id = core.get_meta(c):get_int("dungeoneer_run")
			local run = dungeoneer.runs()[tostring(id)]
			if run then return run end
		end
	end
end
dungeoneer.portal_run = portal_run

-- Use a key on a frame: build a dungeon of the key's tier and light the opening. Returns the stack (one key less when it worked).
function dungeoneer.use_key(player, stack, pos, tier)
	if mv.at(pos) and mv.at(pos).name == "dungeon" then return stack end -- no portals inside a dungeon
	if core.get_node(pos).name ~= "dungeoneer:frame" then return stack end
	local p = find_portal(pos)
	if not p then say(player, S("A key needs a ring of Dungeon Portal Frames around a 2x2 opening.")); return stack end
	local old = portal_run(p)
	if old and #dungeoneer.players_inside(old) > 0 then say(player, S("Somebody is inside: the dungeon stays and you keep the key.")); return stack end
	local function build()
		local failed, sync = nil, true
		dungeoneer.new_run(tier, function(run, why)
			if not run then failed = why; if not sync then say(player, why) end return end
			run.portal = { axis = p.axis, origin = { x = p.origin.x, y = p.origin.y, z = p.origin.z } }
			dungeoneer.update_run(run)
			light(p, run)
			if player:is_valid() then say(player, S("The dungeon is ready.")) end
		end)
		sync = false
		return failed
	end
	if old then
		-- replace: the old dungeon is cleaned first (its slot may be reused), then the new one is built
		local ok, why = dungeoneer.remove_run(old.id, function() build() end)
		if not ok then say(player, why or "?"); return stack end
		for _, c in ipairs(opening_cells(p)) do if is_portal(core.get_node(c).name) then core.set_node(c, { name = "air" }) end end
		say(player, S("Building the dungeon..."))
		stack:take_item(1)
		return stack
	end
	local failed = build()
	if failed then say(player, failed); return stack end
	say(player, S("Building the dungeon..."))
	stack:take_item(1) -- used up, in creative mode too
	return stack
end

-- Close a run's portal: the opening goes dark (the frame stays), the run is marked closed.
function dungeoneer.close_portal(run)
	if run.portal then
		local p = { axis = run.portal.axis, origin = vector.new(run.portal.origin.x, run.portal.origin.y, run.portal.origin.z) }
		for _, c in ipairs(opening_cells(p)) do
			if is_portal(core.get_node(c).name) and core.get_meta(c):get_int("dungeoneer_run") == run.id then core.set_node(c, { name = "air" }) end
		end
	end
	run.portal = nil; run.closed = true
	dungeoneer.update_run(run)
end

-- Breaking a frame block closes the portal; the dungeon goes when it is empty (at once if nobody is inside).
function dungeoneer.on_frame_destroyed(pos)
	local seen = {}
	for dx = -2, 2 do for dy = -2, 2 do for dz = -2, 2 do
		local c = vector.offset(pos, dx, dy, dz)
		if is_portal(core.get_node(c).name) then
			local id = core.get_meta(c):get_int("dungeoneer_run")
			local run = dungeoneer.runs()[tostring(id)]
			if run and not seen[id] then
				seen[id] = true
				dungeoneer.close_portal(run)
				if #dungeoneer.players_inside(run) == 0 then dungeoneer.remove_run(id) end
			end
		end
	end end end
end

-- Exit portals inside a dungeon (start room and boss room): lit after the build; their cells carry the run id and an exit flag.
function dungeoneer.light_exits(run, minp, layout)
	for _, e in pairs(layout.exits) do
		local o = vector.new(minp.x + e.x, minp.y + e.y, minp.z + e.z)
		for i = 0, 1 do for j = 0, 1 do
			local c = vector.new(o.x + i, o.y + j, o.z)
			core.set_node(c, { name = "dungeoneer:portal_x", param2 = portal_param2.x })
			local m = core.get_meta(c); m:set_int("dungeoneer_run", run.id); m:set_int("dungeoneer_exit", 1)
		end end
	end
end

-- chest (the node was written by the generator): fill it and tie it to the run
function dungeoneer.setup_chest(run, minp, layout)
	local c = layout.chest
	dungeoneer.fill_chest(run, vector.new(minp.x + c.x, minp.y + c.y, minp.z + c.z))
end
