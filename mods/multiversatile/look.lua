-- Per-player look of a dimension. A dimension may carry  look = { sky = <player:set_sky table>, sun = <set_sun>, moon = <set_moon>,
-- stars = <set_stars>, clouds = <set_clouds>, lighting = <set_lighting>, ratio = <override_day_night_ratio>,
-- night_vision_ratio = the ratio for a player with Mineclonia's night vision effect (meta night_vision == 1) }  (every part optional).
-- Applied when the player enters the dimension (Mineclonia's own dimension-change event), after joining and after respawning.
-- On leaving, lighting and clouds are put back as they were before and Mineclonia redraws its own sky, fog, sun and moon.
-- Mineclonia's own sky update has no branch for dimensions it does not know, so it leaves ours alone.
local saved = {} -- name -> { lighting, clouds, nv }
local function has_nv(player) return player:get_meta():get_int("night_vision") == 1 end

local function apply(player, d)
	local name = player:get_player_name()
	local look = d.look
	if not saved[name] then
		saved[name] = { lighting = player:get_lighting(), clouds = player:get_clouds() }
	end
	if look.lighting then player:set_lighting(look.lighting) end
	if look.clouds then player:set_clouds(look.clouds) end
	if look.sky then player:set_sky(look.sky) end
	if look.sun then player:set_sun(look.sun) end
	if look.moon then player:set_moon(look.moon) end
	if look.stars then player:set_stars(look.stars) end
	local nv = has_nv(player)
	saved[name].nv = nv
	player:override_day_night_ratio((nv and look.night_vision_ratio) or look.ratio)
end

local function restore(player)
	local name = player:get_player_name()
	local s = saved[name]
	if not s then return end
	saved[name] = nil
	player:set_lighting(s.lighting)
	player:set_clouds(s.clouds)
	player:override_day_night_ratio(nil)
	if rawget(_G, "mcl_weather") and mcl_weather.skycolor then mcl_weather.skycolor.update_sky_color({ player }) end
end

-- Apply or undo the look for the player's current position.
function multiversatile.refresh_look(player)
	local d = multiversatile.at(player:get_pos())
	if d and d.look then apply(player, d) else restore(player) end
end

mcl_worlds.register_on_dimension_change(function(player) multiversatile.refresh_look(player) end)
core.register_on_joinplayer(function(player) core.after(0.5, function() if player:is_valid() then multiversatile.refresh_look(player) end end) end)
core.register_on_respawnplayer(function(player) core.after(0.5, function() if player:is_valid() then multiversatile.refresh_look(player) end end) end)
core.register_on_leaveplayer(function(p) saved[p:get_player_name()] = nil end)

-- the night vision effect starting or ending while the player stands in a dimension with a look
local t = 0
core.register_globalstep(function(dtime)
	t = t + dtime
	if t < 1 then return end
	t = 0
	for _, player in ipairs(core.get_connected_players()) do
		local s = saved[player:get_player_name()]
		if s and s.nv ~= has_nv(player) then multiversatile.refresh_look(player) end
	end
end)
