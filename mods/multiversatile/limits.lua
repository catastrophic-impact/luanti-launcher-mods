-- Height limits, the Minecraft way: you cannot PLACE a block above (or below) a dimension's build limits; breaking blocks there and
-- flying are not limited. The player gets "Height limit for building is N blocks" above the hotbar. Positions outside every
-- registered band (void) are not limited.
local last_msg = {}
multiversatile.message_interval_us = 1000000 -- at most one message per player per second
local function tell(player, y)
	local name = player:get_player_name()
	local now = core.get_us_time()
	if last_msg[name] and now - last_msg[name] < multiversatile.message_interval_us then return end -- once per second
	last_msg[name] = now
	local text = "Height limit for building is " .. y .. " blocks"
	if rawget(_G, "mcl_title") then mcl_title.set(player, "actionbar", { text = text, color = "red", stay = 60 })
	else core.chat_send_player(name, text) end
end
core.register_on_leaveplayer(function(p) last_msg[p:get_player_name()] = nil end)

core.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack)
	if multiversatile.can_build(pos) then return end
	core.set_node(pos, oldnode)
	if placer and placer.get_player_name and placer:is_player() then
		local d = multiversatile.at(pos)
		tell(placer, pos.y > d.build_max and d.build_max or d.build_min)
	end
	return true -- the item is not used up
end)
