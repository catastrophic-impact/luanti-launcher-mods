-- Out of bounds (the Minecraft way for the void): more than `margin` blocks past a dimension's build limits (below the bottom or above
-- the top) the player dies, in creative too. A player in a gap between bands is measured against the last dimension they were in.
-- (Mineclonia's mcl_void_damage also acts below the Overworld/End/Nether; with damage off it only sends players to spawn.)
multiversatile.margin = 64
multiversatile.check_interval = 0.5
local last_dim, last_safe, timer = {}, {}, 0

-- true if y is out of bounds for dimension d
function multiversatile.out_of_bounds(d, y)
	return y < d.build_min - multiversatile.margin or y > d.build_max + multiversatile.margin
end

local function kill(player, d, y)
	local name = player:get_player_name()
	core.log("action", "[multiversatile] " .. name .. " out of bounds in " .. d.name .. " at y=" .. math.floor(y))
	core.chat_send_player(name, "You left the world.")
	-- out_of_world bypasses armor and invulnerability in Mineclonia (creative included)
	if rawget(_G, "mcl_util") and mcl_util.deal_damage then mcl_util.deal_damage(player, 1000000, { type = "out_of_world" }) end
	if player:get_hp() > 0 then player:set_hp(0, { type = "set_hp", from = "mod", reason = "out_of_bounds" }) end
	-- damage switched off in the world: nobody can die, so the player is put back where they were last inside the limits
	if player:get_hp() > 0 then
		local back = last_safe[name]
		if back then player:set_pos(back) else player:respawn() end
	end
end

core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < multiversatile.check_interval then return end
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		if player:get_hp() > 0 then
			local name = player:get_player_name()
			local y = player:get_pos().y
			local d = multiversatile.at_y(y) or last_dim[name]
			if d then
				last_dim[name] = d
				if multiversatile.out_of_bounds(d, y) then kill(player, d, y)
				elseif y >= d.build_min and y <= d.build_max then last_safe[name] = player:get_pos() end
			end
		end
	end
end)
core.register_on_leaveplayer(function(p) local n = p:get_player_name(); last_dim[n] = nil; last_safe[n] = nil end)
