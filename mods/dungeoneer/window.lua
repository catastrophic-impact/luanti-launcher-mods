-- Stepping into a lit portal asks: Enter / Reset / Cancel. Cancel (or closing the window) does not ask again until the player steps out
-- of the portal and back in. Reset asks once more first; it is greyed out while anybody is inside.
local S = core.get_translator("dungeoneer")
local mv = multiversatile
local dismissed, ctx = {}, {} -- name -> true ; name -> { run, ret, yaw }

local TIER = { "I", "II", "III", "IV" }
local function mmss(s) return string.format("%d:%02d", math.floor(s / 60), s % 60) end

local function info_lines(run)
	local inside = dungeoneer.players_inside(run)
	local left = dungeoneer.seconds_left(run)
	return {
		S("Tier @1 castle dungeon", TIER[run.tier]),
		#inside == 0 and S("Nobody is inside.") or S("Inside: @1", table.concat(inside, ", ")),
		(#inside > 0) and S("It stays open while somebody is inside.") or (left and S("Closes in @1 (nobody inside).", mmss(left)) or S("Closes @1 minutes after the last player leaves.", dungeoneer.reset_minutes())),
		run.cleared and S("The boss has been defeated.") or S("The boss has not been defeated."),
	}, #inside
end

local function window(player, run)
	local name = player:get_player_name()
	local lines, inside = info_lines(run)
	local W = 9
	local cols = uikit.cols(0.5, W - 1, 0.2, 3)
	local fs = { uikit.begin(player, W, 6.6), uikit.panel(0.25, 0.9, W - 0.5, 3.6), uikit.title(W, S("Dungeon")) }
	for i, l in ipairs(lines) do fs[#fs + 1] = uikit.text(0.6, 1.1 + (i - 1) * 0.8, W - 1.2, 0.7, l) end
	fs[#fs + 1] = "button[" .. cols[1].x .. ",5.2;" .. cols[1].w .. ",0.8;enter;" .. core.formspec_escape(S("Enter")) .. "]"
	if inside > 0 then fs[#fs + 1] = uikit.disabled("reset") end
	fs[#fs + 1] = "button[" .. cols[2].x .. ",5.2;" .. cols[2].w .. ",0.8;reset;" .. core.formspec_escape(S("Reset")) .. "]"
	fs[#fs + 1] = "button_exit[" .. cols[3].x .. ",5.2;" .. cols[3].w .. ",0.8;cancel;" .. core.formspec_escape(S("Cancel")) .. "]"
	core.show_formspec(name, "dungeoneer:window", table.concat(fs))
end

local function confirm(player, run)
	local name = player:get_player_name()
	local W = 9
	local cols = uikit.cols(0.5, W - 1, 0.2, 2)
	-- anything with contents left inside (chest, grave) is warned about
	local minp, maxp = mv.slot_area("dungeon", run.slot)
	local left = 0
	for _, p in ipairs(core.find_nodes_with_meta(minp, maxp)) do
		local n = core.get_node(p).name
		if n:find("chest") or n:find("grave") or n:find("barrel") then left = left + 1 end
	end
	local fs = { uikit.begin(player, W, 5.2), uikit.panel(0.25, 0.9, W - 0.5, 2.2), uikit.title(W, S("Reset the dungeon?")),
		uikit.text(0.6, 1.1, W - 1.2, 1.9, S("The dungeon and its portal are removed. The frame stays: light it again with a key.") ..
			(left > 0 and ("\n" .. S("A chest or grave inside still holds items: they are lost.")) or "")) }
	fs[#fs + 1] = "button[" .. cols[1].x .. ",3.7;" .. cols[1].w .. ",0.8;really;" .. core.formspec_escape(S("Reset")) .. "]"
	fs[#fs + 1] = "button_exit[" .. cols[2].x .. ",3.7;" .. cols[2].w .. ",0.8;back;" .. core.formspec_escape(S("Back")) .. "]"
	core.show_formspec(name, "dungeoneer:confirm", table.concat(fs))
end

-- where a player who came through the portal goes back to: a block or so off the portal on the side they came from, facing away
local function return_spot(run, ppos)
	local o, axis = run.portal.origin, run.portal.axis
	if axis == "x" then
		local s = ppos.z >= o.z and 1 or -1
		return vector.new(o.x + 0.5, o.y, o.z + s * 1.8), (s == 1) and 0 or math.pi
	else
		local s = ppos.x >= o.x and 1 or -1
		return vector.new(o.x + s * 1.8, o.y, o.z + 0.5), (s == 1) and -math.pi / 2 or math.pi / 2
	end
end

local function portal_at(player)
	local pos = player:get_pos()
	for _, dy in ipairs({ 0, 1 }) do
		local c = vector.round(vector.offset(pos, 0, dy, 0))
		local n = core.get_node(c).name
		if n == "dungeoneer:portal_x" or n == "dungeoneer:portal_z" then
			local m = core.get_meta(c)
			local run = dungeoneer.runs()[tostring(m:get_int("dungeoneer_run"))]
			if run and m:get_int("dungeoneer_exit") == 1 then return run, true end
			if run and run.portal then return run end
		end
	end
end

local t = 0
core.register_globalstep(function(dtime)
	t = t + dtime
	if t < 0.2 then return end
	t = 0
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local run, is_exit = portal_at(player)
		if not run then dismissed[name] = nil
		elseif not dismissed[name] and not ctx[name] then
			if is_exit then
				ctx[name] = { run = run.id, exit = true }
				dungeoneer.exit_window(player, run)
			else
				local ret, yaw = return_spot(run, player:get_pos())
				ctx[name] = { run = run.id, ret = ret, yaw = yaw }
				window(player, run)
			end
		end
	end
end)

-- Leave / Stay (exit portals): says whether the boss is dead, who else stays, and how long the dungeon lasts after you leave
function dungeoneer.exit_window(player, run)
	local name = player:get_player_name()
	local others = {}
	for _, n in ipairs(dungeoneer.players_inside(run)) do if n ~= name then others[#others + 1] = n end end
	local W = 9
	local cols = uikit.cols(0.5, W - 1, 0.2, 2)
	local lines = {
		run.cleared and S("The boss is dead.") or S("The boss is still alive."),
		#others > 0 and S("Staying inside: @1", table.concat(others, ", ")) or S("Nobody else is inside."),
		#others > 0 and S("The dungeon stays open while they are inside.") or S("The dungeon closes @1 minutes after you leave.", dungeoneer.reset_minutes()),
	}
	local fs = { uikit.begin(player, W, 5.6), uikit.panel(0.25, 0.9, W - 0.5, 2.9), uikit.title(W, S("Leave the dungeon?")) }
	for i, l in ipairs(lines) do fs[#fs + 1] = uikit.text(0.6, 1.1 + (i - 1) * 0.8, W - 1.2, 0.7, l) end
	fs[#fs + 1] = "button[" .. cols[1].x .. ",4.3;" .. cols[1].w .. ",0.8;leave;" .. core.formspec_escape(S("Leave")) .. "]"
	fs[#fs + 1] = "button_exit[" .. cols[2].x .. ",4.3;" .. cols[2].w .. ",0.8;stay;" .. core.formspec_escape(S("Stay")) .. "]"
	core.show_formspec(name, "dungeoneer:exit", table.concat(fs))
end

core.register_on_leaveplayer(function(p) dismissed[p:get_player_name()] = nil; ctx[p:get_player_name()] = nil end)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "dungeoneer:exit" then
		local name = player:get_player_name()
		if fields.leave then
			ctx[name] = nil; dismissed[name] = true
			core.close_formspec(name, formname)
			mv.back(player)
		elseif fields.stay or fields.quit then ctx[name] = nil; dismissed[name] = true end
		return
	end
	if formname ~= "dungeoneer:window" and formname ~= "dungeoneer:confirm" then return end
	local name = player:get_player_name()
	local c = ctx[name]
	local run = c and dungeoneer.runs()[tostring(c.run)]
	if formname == "dungeoneer:window" then
		if fields.enter and run then
			ctx[name] = nil; dismissed[name] = true
			core.close_formspec(name, formname)
			mv.set_return_point(name, c.ret, c.yaw)
			mv.go(player, dungeoneer.run_start_pos(run), { remember = false, yaw = -math.pi / 2 })
		elseif fields.reset and run then
			if #dungeoneer.players_inside(run) > 0 then window(player, run) else confirm(player, run) end
		elseif fields.cancel or fields.quit then
			if not fields.reset then ctx[name] = nil; dismissed[name] = true end
		end
	else -- confirm
		if fields.really and run then
			ctx[name] = nil; dismissed[name] = true
			core.close_formspec(name, formname)
			if #dungeoneer.players_inside(run) == 0 then
				dungeoneer.close_portal(run)
				dungeoneer.remove_run(run.id)
			end
		elseif fields.back or fields.quit then
			if run then window(player, run) end
		end
	end
end)
