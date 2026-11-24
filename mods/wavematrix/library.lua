-- The song list. Sources: bundled tracks (<mod>/music) and the shared music mod wm_music (root files = "Your music", each subfolder = a group).
-- Song = { id, name, group, path, media }. id is "b:<file>" (bundled) or "u:<relative path>" (your music): favorites are stored by id.
local S = core.get_translator("wavematrix")
local modpath = core.get_modpath("wavematrix")
wavematrix.GROUP_BUNDLED = "Wave Matrix"
wavematrix.GROUP_OWN = "Your music"
wavematrix.GROUP_DISCS = "Music discs"
local lengths = {}

local function natural_less(a, b)
	local na, nb = tonumber(a:match("%d+")), tonumber(b:match("%d+"))
	if na and nb and na ~= nb then return na < nb end
	return a:lower() < b:lower()
end

local function add(list, id, name, group, path)
	list[#list + 1] = { id = id, name = name, group = group, path = path, media = "wm_" .. core.sha1(id):sub(1, 12) }
end

local function scan_dir(list, base, rel, rootgroup)
	local dir = rel == "" and base or (base .. "/" .. rel)
	local files = core.get_dir_list(dir, false)
	table.sort(files, natural_less)
	for _, f in ipairs(files) do
		if f:lower():match("%.ogg$") then
			local r = rel == "" and f or (rel .. "/" .. f)
			add(list, "u:" .. r, (f:gsub("%.[Oo][Gg][Gg]$", "")), rel == "" and rootgroup or rel:gsub("/", " / "), dir .. "/" .. f)
		end
	end
	local dirs = core.get_dir_list(dir, true)
	table.sort(dirs, natural_less)
	for _, d in ipairs(dirs) do
		if d:sub(1, 1) ~= "." then scan_dir(list, base, rel == "" and d or (rel .. "/" .. d), rootgroup) end
	end
end

function wavematrix.scan()
	local list = {}
	local files = core.get_dir_list(modpath .. "/music", false)
	table.sort(files, natural_less)
	for _, f in ipairs(files) do
		if f:lower():match("%.ogg$") then
			local n = f:gsub("%.[Oo][Gg][Gg]$", "")
			local num = n:match("^track(%d+)$")
			add(list, "b:" .. f, num and S("Track @1", num) or n, wavematrix.GROUP_BUNDLED, modpath .. "/music/" .. f)
		end
	end
	local shared = core.get_modpath("wm_music")
	if shared then scan_dir(list, shared, "", wavematrix.GROUP_OWN) end
	-- Mineclonia music discs: their sounds are normal game media (already on every client), so they need no sending
	if mcl_jukebox and mcl_jukebox.registered_records then
		local files = {}
		for _, mod in ipairs(core.get_modnames()) do
			local dir = core.get_modpath(mod) .. "/sounds"
			for _, f in ipairs(core.get_dir_list(dir, false)) do
				local base = f:match("^(.+)%.ogg$")
				if base and not files[base] then files[base] = dir .. "/" .. f end
			end
		end
		local discs = {}
		for item, def in pairs(mcl_jukebox.registered_records) do
			if type(def.sound) == "string" then
				discs[#discs + 1] = { item = item, name = (def.author and def.author ~= "" and (def.author .. " - ") or "") .. tostring(def.title), sound = def.sound }
			end
		end
		table.sort(discs, function(a, b) return a.name:lower() < b.name:lower() end)
		for _, d in ipairs(discs) do
			add(list, "d:" .. d.item, d.name, wavematrix.GROUP_DISCS, files[d.sound] or "")
			list[#list].media, list[#list].builtin = d.sound, true
		end
	end
	local byid, groups, seen = {}, {}, {}
	for i, s in ipairs(list) do
		s.index = i
		byid[s.id] = s
		if not seen[s.group] then seen[s.group] = true; groups[#groups + 1] = s.group end
	end
	wavematrix.songs, wavematrix.by_id, wavematrix.groups = list, byid, groups
	return list
end

function wavematrix.length(song)
	local l = lengths[song.id]
	if l == nil then
		l = (song.path ~= "" and wavematrix.ogg_seconds(song.path)) or false
		lengths[song.id] = l
	end
	return l or 180
end
