-- Travel between dimensions.
--   multiversatile.go(player, pos, opts, cb)  move the player to pos (the area is generated/loaded first). opts: remember = true (default:
--        save where the player came from as their return point), yaw = number, keep = true (do not overwrite an existing return point:
--        used when moving between two spots of the same trip). cb(ok) runs after the move.
--   multiversatile.back(player, opts, cb)     back to the saved return point, or to the player's spawn when there is none; clears the point.
--   multiversatile.return_point(name)         { pos, dim, yaw } or nil (stored per player, survives restarts).
--   multiversatile.set_return_point(name, pos, yaw) / clear_return_point(name)
-- A dimension with transient = true (throwaway worlds such as dungeons) never keeps a player over a login: a player who logs in inside
-- one (logged out inside, server restarted, the world was reset) is put back at their return point or spawn.
local storage = core.get_mod_storage()
local KEY = "return:"

function multiversatile.return_point(name)
	local raw = storage:get_string(KEY .. name)
	if raw == "" then return nil end
	local t = core.parse_json(raw)
	if type(t) ~= "table" or type(t.pos) ~= "table" then return nil end
	return t
end
function multiversatile.set_return_point(name, pos, yaw)
	local d = multiversatile.at(pos)
	storage:set_string(KEY .. name, core.write_json({ pos = { x = pos.x, y = pos.y, z = pos.z }, dim = d and d.name or "void", yaw = yaw }))
end
function multiversatile.clear_return_point(name) storage:set_string(KEY .. name, "") end

local function move(player, pos, yaw, cb)
	core.emerge_area(vector.offset(pos, -8, -8, -8), vector.offset(pos, 8, 8, 8), function(_, _, remaining)
		if remaining > 0 then return end
		if not player:is_valid() then if cb then cb(false) end return end
		player:set_pos(pos)
		if yaw then player:set_look_horizontal(yaw) end
		multiversatile.refresh_look(player) -- sky/lighting at once, not at Mineclonia's next dimension check
		if cb then cb(true) end
	end)
end

function multiversatile.go(player, pos, opts, cb)
	opts = opts or {}
	local name = player:get_player_name()
	if opts.remember ~= false and not (opts.keep and multiversatile.return_point(name)) then
		multiversatile.set_return_point(name, player:get_pos(), player:get_look_horizontal())
	end
	move(player, pos, opts.yaw, cb)
end

function multiversatile.back(player, opts, cb)
	local name = player:get_player_name()
	local rp = multiversatile.return_point(name)
	local pos, yaw
	if rp then pos, yaw = vector.new(rp.pos.x, rp.pos.y, rp.pos.z), rp.yaw
	elseif rawget(_G, "mcl_spawn") then pos = mcl_spawn.get_player_spawn_pos(player) or mcl_spawn.get_world_spawn_pos(player) end
	if not pos then if cb then cb(false) end return end
	multiversatile.clear_return_point(name)
	move(player, pos, yaw, cb)
end

-- Login in a transient dimension.
function multiversatile.handle_login(player, cb)
	local d = multiversatile.at(player:get_pos())
	if d and d.transient then multiversatile.back(player, nil, cb) elseif cb then cb(false) end
end
core.register_on_joinplayer(function(player)
	core.after(1, function() if player:is_valid() then multiversatile.handle_login(player) end end)
end)
