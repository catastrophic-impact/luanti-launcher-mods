-- Pure-Lua Ogg Vorbis duration: sample rate from the identification header, granule position of the last OggS page.
local function le(s, i, n) local v = 0 for k = n, 1, -1 do v = v * 256 + s:byte(i + k - 1) end return v end
function wavematrix.ogg_seconds(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local ok, res = pcall(function()
		local head = f:read(64)
		local p = head and head:find("\1vorbis", 1, true)
		if not p then return nil end
		local rate = le(head, p + 12, 4)
		if rate == 0 then return nil end
		local size = f:seek("end")
		f:seek("set", math.max(0, size - 65536))
		local tail = f:read("*a")
		local last, i = nil, 1
		while true do
			local s = tail:find("OggS", i, true)
			if not s then break end
			last = s
			i = s + 1
		end
		if not last then return nil end
		return le(tail, last + 6, 6) / rate
	end)
	f:close()
	return ok and res or nil
end
