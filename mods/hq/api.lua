-- Shortcut registry, per-player data, command runner.
local S = core.get_translator("hq")

-- Other mods: hq.register_shortcut({ id = "tameful", name = "Tameful", command = "tameful" | func = function(player) end,
--   icon = "item:name" (or icons = {..} taking turns), short = "TM" (written on the button when there is no picture) })
-- Mods call it only if core.get_modpath("hq"): nothing else is needed.
function hq.register_shortcut(def)
	assert(def.id and (def.command or def.func), "hq shortcut needs id and command or func")
	def.name = def.name or def.id
	if not hq.shortcuts[def.id] then hq.order[#hq.order + 1] = def.id end
	hq.shortcuts[def.id] = def
end

local function meta_data(player)
	local m = player:get_meta()
	local d = core.deserialize(m:get_string("hq:data"))
	if type(d) ~= "table" then d = {} end
	d.own = d.own or {}      -- { {name=, command=}, ... }
	d.pics = d.pics or {}
	d.stars = d.stars or {}  -- stars[id] = true/false (mini button on/off); nil = the mod's default
	d.minis = d.minis or 4   -- most mini buttons shown (0..10)
	return d, m
end
function hq.get(player) return (meta_data(player)) end
function hq.save(player, d) player:get_meta():set_string("hq:data", core.serialize(d)) end

local function msg(name, text) core.chat_send_player(name, core.colorize("#9cf", "[HQ] ") .. text) end
hq.msg = msg

-- Runs `line` ("/time 6000" or "time 6000") as if typed: only with the privileges that command needs.
function hq.run_command(player, line)
	local name = player:get_player_name()
	line = line:gsub("^%s*/", ""):gsub("^%s+", "")
	local cmd, param = line:match("^(%S+)%s*(.*)$")
	local def = cmd and core.registered_chatcommands[cmd]
	if not def then msg(name, S("Unknown command: @1", tostring(cmd))); return false end
	local ok, missing = core.check_player_privs(name, def.privs or {})
	if not ok then
		msg(name, S("You need the privilege(s): @1", table.concat(missing, ", ")))
		return false
	end
	local res, text = def.func(name, param)
	if text and text ~= "" then msg(name, text) end
	return res
end

function hq.run_shortcut(player, sc)
	if sc.func then sc.func(player) else hq.run_command(player, "/" .. sc.command) end
end

-- Own shortcuts
local NAME_OK = "^[%w_%-]+$"
local RESERVED = { add = true, remove = true, list = true }
function hq.valid_name(n) return n and #n >= 1 and #n <= 32 and n:match(NAME_OK) and not RESERVED[n] end

function hq.find_own(d, name)
	for i, e in ipairs(d.own) do if e.name == name then return i, e end end
end

function hq.add_own(player, name, command, replace_index)
	local d = hq.get(player)
	command = (command or ""):gsub("^%s*/", ""):gsub("%s+$", "")
	if not hq.valid_name(name) then return false, S("Names use letters, numbers, _ and - (up to 32); add, remove and list are reserved.") end
	if command == "" then return false, S("The command is empty.") end
	local at = hq.find_own(d, name)
	if at and at ~= replace_index then return false, S("You already have a shortcut called @1.", name) end
	if hq.shortcuts[name] then return false, S("@1 is taken by a mod shortcut.", name) end
	if replace_index and d.own[replace_index] then
		d.own[replace_index] = { name = name, command = command } -- a rename keeps its place
	else
		d.own[#d.own + 1] = { name = name, command = command }
	end
	hq.save(player, d)
	return true
end

function hq.remove_own(player, index)
	local d = hq.get(player)
	if d.own[index] then table.remove(d.own, index); hq.save(player, d); return true end
	return false
end

-- Standard pictures for a mini button (the star's picture button cycles through them); 1 = the mod's own picture or its short name.
hq.PICTURES = { false, "short" }
for _, it in ipairs({ "mobs_mc:spawn_egg", "mcl_crafting_table:crafting_table", "mcl_furnaces:furnace", "mcl_chests:chest", "mcl_books:bookshelf",
		"mcl_tools:sword_diamond", "mcl_armor:chestplate_iron", "mcl_doors:door_oak", "mcl_compass:compass" }) do
	hq.PICTURES[#hq.PICTURES + 1] = it
end
function hq.picture_of(d, sc) -- returns item name or nil, plus the short text
	local i = d.pics and d.pics[sc.id] or 1
	local p = hq.PICTURES[i]
	local short = sc.short
	if not short then
		short = ""
		for w in sc.name:gmatch("%a+") do short = short .. w:sub(1, 1):upper() end
		short = short:sub(1, 3)
	end
	if p == "short" then return nil, short end
	if p and core.registered_items[p] then return p, short end
	local own = sc.icon or (sc.icons and sc.icons[1])
	return own and core.registered_items[own] and own or nil, short
end

-- Is the mod's mini button on for this player? (default: on when the mod chose a picture)
function hq.mini_on(d, sc)
	local v = d.stars[sc.id]
	if v == nil then return (sc.icon or sc.icons) ~= nil end
	return v
end

-- Chat command
core.register_chatcommand("hq", {
	params = "[add <name> <command> | remove <name> | list | <name>]",
	description = S("Open HQ, or run / manage your shortcuts"),
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return false end
		param = param:gsub("^%s+", ""):gsub("%s+$", "")
		if param == "" then hq.show(name); return true end
		local sub, rest = param:match("^(%S+)%s*(.*)$")
		local d = hq.get(player)
		if sub == "add" then
			local n, c = rest:match("^(%S+)%s+(.+)$")
			if not n then return false, S("Usage: /hq add <name> <command>") end
			local ok, why = hq.add_own(player, n, c)
			return ok, ok and S("Saved @1.", n) or why
		elseif sub == "remove" then
			local i = hq.find_own(d, rest)
			if not i then return false, S("No shortcut called @1.", rest) end
			hq.remove_own(player, i)
			return true, S("Removed @1.", rest)
		elseif sub == "list" then
			local t = {}
			for _, id in ipairs(hq.order) do t[#t + 1] = hq.shortcuts[id].name .. " -> /" .. (hq.shortcuts[id].command or "(button)") end
			for _, e in ipairs(d.own) do t[#t + 1] = e.name .. " -> /" .. e.command end
			return true, #t > 0 and table.concat(t, "\n") or S("No shortcuts yet.")
		end
		local _, e = hq.find_own(d, param)
		if e then hq.run_command(player, "/" .. e.command); return true end
		local sc = hq.shortcuts[param]
		if sc then hq.run_shortcut(player, sc); return true end
		return false, S("No shortcut called @1.", param)
	end,
})

-- Creative on/off for the player: game mode + fly + fast. In a world that is creative for everyone the game mode stays creative
-- (Mineclonia), but fly and fast are still granted/taken here.
function hq.toggle_creative(player)
	local name = player:get_player_name()
	if not core.check_player_privs(name, { server = true }) then return end
	local want_on = not (rawget(_G, "mcl_gamemode") and mcl_gamemode.get_gamemode(player) == "creative")
	if rawget(_G, "mcl_gamemode") then mcl_gamemode.set_gamemode(player, want_on and "creative" or "survival") end
	local privs = core.get_player_privs(name)
	privs.fly, privs.fast = want_on or nil, want_on or nil
	core.set_player_privs(name, privs)
	if not want_on and rawget(_G, "mcl_gamemode") and mcl_gamemode.get_gamemode(player) == "creative" then
		hq.msg(name, "Creative off: fly and fast removed (this world is creative for everyone, so the game mode stays).")
	else
		hq.msg(name, want_on and "Creative on: fly and fast granted." or "Creative off: fly and fast removed.")
	end
end
