local function log(s) core.log("action", "[WM_PROBE_TEST] NOTE " .. s) end
local up = core.get_user_path()
local shared = core.get_modpath("wm_music")
local mp = core.get_modpath("wm_probe")

local function try(label, fn)
	local ok, a, b = pcall(fn)
	log(label .. ": " .. (ok and ("OK " .. tostring(a) .. " " .. tostring(b)) or ("ERR " .. tostring(a))))
end

-- ogg duration: sample rate from the identification header, granule of the last page
local function le(s, i, n) local v = 0 for k = n, 1, -1 do v = v * 256 + s:byte(i + k - 1) end return v end
local function ogg_seconds(f)
	local head = f:read(64)
	local p = head:find("\1vorbis", 1, true)
	if not p then return nil, "no vorbis header" end
	local rate = le(head, p + 12, 4)
	local size = f:seek("end")
	local from = math.max(0, size - 65536)
	f:seek("set", from)
	local tail = f:read("*a")
	local last
	local i = 1
	while true do
		local s = tail:find("OggS", i, true)
		if not s then break end
		last = s
		i = s + 1
	end
	if not last then return nil, "no page" end
	local g = le(tail, last + 6, 6) -- 48 bits are plenty (avoid float loss)
	return g / rate, rate
end

try("get_dir_list shared (user path)", function() return table.concat(core.get_dir_list(shared, false), ","), table.concat(core.get_dir_list(shared, true), ",") end)
try("get_dir_list shared/Rock", function() return table.concat(core.get_dir_list(shared .. "/Rock", false), ",") end)
try("io.open shared file", function() local f = assert(io.open(shared .. "/a_track1.ogg", "rb")); local d = f:read(4); f:close(); return d end)
try("ogg_seconds shared", function() local f = assert(io.open(shared .. "/a_track1.ogg", "rb")); local s, r = ogg_seconds(f); f:close(); return s, r end)
try("ogg_seconds shared/Rock", function() local f = assert(io.open(shared .. "/Rock/b_track2.ogg", "rb")); local s, r = ogg_seconds(f); f:close(); return s, r end)
try("insecure env", function() return tostring(core.request_insecure_environment and core.request_insecure_environment()) end)

core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(10, function()
		for _, path in ipairs({ shared .. "/a_track1.ogg", shared .. "/Rock/b_track2.ogg" }) do
			local name = "wmprobe_" .. path:match("([^/]+)%.ogg$")
			local ok, err = pcall(core.dynamic_add_media, { filename = name .. ".ogg", filepath = path, to_player = "tester", ephemeral = true },
				function(pname) log("media arrived " .. name .. " for " .. tostring(pname)) 
					local h = core.sound_play(name, { to_player = "tester", gain = 0.0 })
					log("sound_play handle " .. tostring(h))
					core.after(3, function() core.sound_stop(h) end)
				end)
			log("dynamic_add_media " .. name .. " pcall " .. tostring(ok) .. " " .. tostring(err))
		end
		core.after(15, function() log("SCENARIO_DONE"); core.request_shutdown("done") end)
	end)
end)
