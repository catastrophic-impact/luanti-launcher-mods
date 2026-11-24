local function log(s) core.log("action", "[SKIN_SPIKE] " .. s) end
local dir = core.get_modpath("skin_spike") .. "/skins/"
-- minimal PNG reader: header + pixel alpha via core.decompress("deflate") on the joined IDAT chunks (8-bit RGBA / RGB only)
local function read_png(path)
	local f = io.open(path, "rb"); if not f then return nil, "open" end
	local data = f:read("*a"); f:close()
	if data:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil, "not png" end
	local pos, idat, info = 9, {}, {}
	while pos < #data do
		local len = string.unpack(">I4", data, pos); local typ = data:sub(pos + 4, pos + 7)
		local body = data:sub(pos + 8, pos + 7 + len)
		if typ == "IHDR" then info.w, info.h, info.depth, info.ctype = string.unpack(">I4I4BB", body)
		elseif typ == "IDAT" then idat[#idat + 1] = body
		elseif typ == "PLTE" then info.plte = body
		elseif typ == "tRNS" then info.trns = body end
		pos = pos + 12 + len
	end
	info.raw = core.decompress(table.concat(idat), "deflate")
	return info
end
-- returns rows 0..maxrow unfiltered as strings (bytes per pixel 3/4 only)
local function rows(info, maxrow)
	local bpp = (info.ctype == 6) and 4 or (info.ctype == 2) and 3 or nil
	if not bpp or info.depth ~= 8 then return nil, "unsupported ctype " .. info.ctype .. " depth " .. info.depth end
	local stride = info.w * bpp
	local out, prev = {}, string.rep("\0", stride)
	for y = 0, maxrow do
		local base = y * (stride + 1) + 1
		local ft = info.raw:byte(base)
		local line = { info.raw:byte(base + 1, base + stride) }
		local pl = { prev:byte(1, stride) }
		for i = 1, stride do
			local a = i > bpp and line[i - bpp] or 0
			local b = pl[i]
			local c = i > bpp and pl[i - bpp] or 0
			local x = line[i]
			if ft == 1 then x = x + a elseif ft == 2 then x = x + b elseif ft == 3 then x = x + math.floor((a + b) / 2)
			elseif ft == 4 then
				local p = a + b - c; local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
				x = x + ((pa <= pb and pa <= pc) and a or (pb <= pc) and b or c)
			end
			line[i] = x % 256
		end
		local s = string.char(unpack(line)); out[y] = s; prev = s
	end
	return out, bpp
end
local function alpha(r, bpp, x, y) if bpp == 3 then return 255 end return r[y]:byte(x * 4 + 4) end
core.register_on_joinplayer(function(player)
	if player:get_player_name() ~= "tester" then return end
	core.after(5, function()
		for _, n in ipairs({ "steve", "alex" }) do
			local info, err = read_png(dir .. n .. ".png")
			if not info then log("FAIL " .. n .. " " .. tostring(err))
			else
				local t0 = core.get_us_time()
				local r, bpp = rows(info, 20)
				local dt = (core.get_us_time() - t0) / 1000
				if not r then log("FAIL " .. n .. " " .. tostring(bpp))
				else
					-- slim = pixel (54,20) of a 64x64 skin is transparent (the 4th column of the right arm front is missing)
					local a = alpha(r, bpp, 54, 20)
					log(("PASS %s %dx%d ctype %d, alpha(54,20)=%d => %s arms, decoded 21 rows in %.1f ms"):format(n, info.w, info.h, info.ctype, a, a == 0 and "SLIM" or "WIDE", dt))
				end
			end
		end
		log("SCENARIO_DONE"); core.request_shutdown("done")
	end)
end)
