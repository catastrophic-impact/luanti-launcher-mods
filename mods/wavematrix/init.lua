-- Wave Matrix (Luanti/Mineclonia port). A per-player music player. The server holds the files and sends a song to a player only when
-- that player plays it (core.dynamic_add_media, ephemeral); nothing is downloaded at join. Settings live in player meta "wavematrix:cfg".
wavematrix = {}
local S = core.get_translator("wavematrix")
local modpath = core.get_modpath("wavematrix")
local KEY = "wavematrix:cfg"
local now = function() return core.get_us_time() / 1e6 end

dofile(modpath .. "/ogg.lua")
dofile(modpath .. "/library.lua")
wavematrix.scan()
core.register_on_mods_loaded(wavematrix.scan) -- discs registered by later mods

-- ---------------------------------------------------------------- settings
local DEFAULT = { mode = "shuffle", continuous = false, favorites = {}, favorites_only = false, show_name = true, skipped = {}, volume = 0.5, stopped = false }
local cache = {}
function wavematrix.cfg(name)
	if cache[name] then return cache[name] end
	local p = core.get_player_by_name(name)
	local c = p and core.deserialize(p:get_meta():get_string(KEY))
	if type(c) ~= "table" then c = {} end
	for k, v in pairs(DEFAULT) do
		if c[k] == nil then c[k] = type(v) == "table" and {} or v end
	end
	if not c.discs_init then c.discs_init = true; c.skipped[wavematrix.GROUP_DISCS] = true end -- discs start out left out
	cache[name] = c
	return c
end
function wavematrix.save(name)
	local p, c = core.get_player_by_name(name), cache[name]
	if p and c then p:get_meta():set_string(KEY, core.serialize(c)) end
end
local function prune_favorites(c)
	local keep = {}
	for _, id in ipairs(c.favorites) do if wavematrix.by_id[id] then keep[#keep + 1] = id end end
	c.favorites = keep
	if #keep == 0 then c.favorites_only = false end
end
function wavematrix.is_favorite(name, id)
	for _, f in ipairs(wavematrix.cfg(name).favorites) do if f == id then return true end end
	return false
end
function wavematrix.toggle_favorite(name, id)
	local c = wavematrix.cfg(name)
	if wavematrix.is_favorite(name, id) then
		local keep = {}
		for _, f in ipairs(c.favorites) do if f ~= id then keep[#keep + 1] = f end end
		c.favorites = keep
		if #keep == 0 then c.favorites_only = false end
	else
		c.favorites[#c.favorites + 1] = id
	end
	wavematrix.save(name)
end

-- ---------------------------------------------------------------- picking the next song
function wavematrix.pool(name)
	local c = wavematrix.cfg(name)
	prune_favorites(c)
	local out = {}
	if c.favorites_only then
		local fav = {}
		for _, id in ipairs(c.favorites) do fav[id] = true end
		for _, s in ipairs(wavematrix.songs) do if fav[s.id] then out[#out + 1] = s end end
	else
		for _, s in ipairs(wavematrix.songs) do if not c.skipped[s.group] then out[#out + 1] = s end end
	end
	return out
end

function wavematrix.pick_next(name, current)
	local c, pool = wavematrix.cfg(name), wavematrix.pool(name)
	if #pool == 0 then return nil end
	if c.mode == "loop" and current and wavematrix.by_id[current] then return wavematrix.by_id[current] end
	if c.mode == "in_order" then
		local cur = current and wavematrix.by_id[current]
		if cur then
			for _, s in ipairs(pool) do if s.index > cur.index then return s end end
		end
		return pool[1]
	end
	if #pool == 1 then return pool[1] end
	local s
	repeat s = pool[math.random(#pool)] until s.id ~= current
	return s
end

-- ---------------------------------------------------------------- playback (per player)
-- st = { id, handle, started, offset, length, token, wait_until, sent = { [media] = true } }
local states = {}
local function state(name)
	if not states[name] then states[name] = { sent = {}, token = 0 } end
	return states[name]
end
function wavematrix.state(name) return states[name] end

local hud = {}
local function announce(name, text)
	local p = core.get_player_by_name(name)
	if not p then return end
	if hud[name] then p:hud_remove(hud[name].id); hud[name] = nil end
	local id = p:hud_add({
		type = "text", position = { x = 0.5, y = 0.9 }, offset = { x = 0, y = -60 }, alignment = { x = 0, y = 0 },
		text = text, number = 0xFFFFFF, z_index = 100,
	})
	hud[name] = { id = id }
	core.after(6, function()
		local pp = core.get_player_by_name(name)
		if pp and hud[name] and hud[name].id == id then pp:hud_remove(id); hud[name] = nil end
	end)
end

local function halt_sound(st)
	if st.handle then core.sound_stop(st.handle); st.handle = nil end
end

local function start_sound(name, st, song, offset)
	local c = wavematrix.cfg(name)
	st.handle = core.sound_play(song.media, { to_player = name, gain = c.volume, start_time = offset > 0 and offset or nil })
	st.started = now() - offset
	st.playing_media = true
end

-- play a song now (offset = seconds into it)
function wavematrix.play(name, id, offset)
	local song = wavematrix.by_id[id]
	local p = core.get_player_by_name(name)
	if not song or not p then return false end
	local st, c = state(name), wavematrix.cfg(name)
	offset = offset or 0
	halt_sound(st)
	st.token = st.token + 1
	local token = st.token
	st.id, st.length, st.offset, st.wait_until, st.pending = song.id, wavematrix.length(song), offset, nil, true
	if c.stopped then c.stopped = false; wavematrix.save(name) end
	local function go()
		if state(name).token ~= token or not core.get_player_by_name(name) then return end
		st.pending = false
		start_sound(name, st, song, offset)
		if offset == 0 and c.show_name then announce(name, "♪ " .. song.name) end
	end
	if song.builtin or st.sent[song.media] then
		go()
	else
		local ok = core.dynamic_add_media({ filename = song.media .. ".ogg", filepath = song.path, to_player = name, ephemeral = true }, function()
			st.sent[song.media] = true
			go()
		end)
		if ok == false then st.pending = false; return false end
	end
	return true
end

function wavematrix.stop(name)
	local st, c = state(name), wavematrix.cfg(name)
	halt_sound(st)
	st.token = st.token + 1
	st.id, st.wait_until, st.pending = nil, nil, false
	c.stopped = true
	wavematrix.save(name)
end

function wavematrix.next(name)
	local st = state(name)
	local s = wavematrix.pick_next(name, st.id)
	if s then return wavematrix.play(name, s.id) end
	return false
end

function wavematrix.set_volume(name, vol)
	local c, st = wavematrix.cfg(name), state(name)
	c.volume = vol
	wavematrix.save(name)
	if st.id and not st.pending and st.handle then -- the engine cannot change a running sound's volume: restart where it was
		local song = wavematrix.by_id[st.id]
		local at = now() - st.started
		if song and at < st.length then wavematrix.play(name, st.id, at) end
	end
end

-- seconds played of the current song, nil when nothing plays
function wavematrix.elapsed(name)
	local st = states[name]
	if st and st.id and st.handle and st.started then return math.min(now() - st.started, st.length) end
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.5 then return end
	timer = 0
	local t = now()
	for name, st in pairs(states) do
		local c = wavematrix.cfg(name)
		if not c.stopped and not st.pending then
			if st.handle and st.started and t - st.started >= st.length + 0.5 then
				-- the song ended
				st.handle = nil
				if c.continuous then
					wavematrix.next(name)
				else
					st.wait_until = t + math.random(180, 480) -- Immersion "Natural": a pause like the game's own music
				end
			elseif not st.handle and st.wait_until and t >= st.wait_until then
				st.wait_until = nil
				wavematrix.next(name)
			end
		end
	end
end)

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	states[name] = { sent = {}, token = 0 }
	local c = wavematrix.cfg(name)
	prune_favorites(c)
	if not c.stopped then states[name].wait_until = now() + 5 end -- a few seconds after arriving
end)
core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	wavematrix.save(name)
	states[name], cache[name], hud[name] = nil, nil, nil
end)

dofile(modpath .. "/ui.lua")

if core.get_modpath("hq") then
	hq.register_shortcut({ id = "wavematrix", name = "Wave Matrix", command = "wm", icon = "mcl_jukebox:jukebox", short = "WM" })
end
