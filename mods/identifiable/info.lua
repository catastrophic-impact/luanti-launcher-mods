-- What is the player looking at, and what do we say about it.
local S = core.get_translator("identifiable")
local id = identifiable
local has_farming, has_armor, has_weather = core.get_modpath("mcl_farming") ~= nil, core.get_modpath("mcl_armor") ~= nil, core.get_modpath("mcl_weather") ~= nil

local function first_line(s) return (tostring(s or ""):gsub("\n.*$", "")) end

-- ---------------------------------------------------------------------------------------------------------------------
-- Liquids
-- ---------------------------------------------------------------------------------------------------------------------
local function is_liquid(name)
	local def = core.registered_nodes[name]
	return def and (def.liquidtype == "source" or def.liquidtype == "flowing")
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Ray: first thing we can name (liquids are looked through; if nothing is behind them the liquid is named)
-- ---------------------------------------------------------------------------------------------------------------------
local SKIP_ENTITIES = { ["mcl_wieldview:wieldview"] = true, ["mcl_mobspawners:doll"] = true }

function id.find_target(player, range, cfg)
	local pos = player:get_pos()
	local props = player:get_properties()
	local eye = vector.offset(pos, 0, (props.eye_height or 1.47), 0)
	local dir = player:get_look_dir()
	local ray = core.raycast(eye, vector.add(eye, vector.multiply(dir, range)), true, true)
	local liquid
	for p in ray do
		if p.type == "node" then
			local n = core.get_node(p.under)
			if n.name ~= "air" and n.name ~= "ignore" then
				if is_liquid(n.name) then
					liquid = liquid or p
				else
					return { kind = "node", pointed = p, node = n }
				end
			end
		elseif p.type == "object" then
			local o = p.ref
			if o and o ~= player and o:is_valid() then
				if o:is_player() then
					local pr = o:get_properties()
					if not (pr and pr.is_visible == false) then return { kind = "player", obj = o } end
				else
					local e = o:get_luaentity()
					local pr = o:get_properties()
					if e and not SKIP_ENTITIES[e.name] and not o:get_attach() and not (pr and pr.is_visible == false) and not (pr and pr.textures and #pr.textures == 1 and pr.textures[1] == "blank.png") then
						if e.name == "__builtin:item" then
							if cfg.show_items then return { kind = "item", obj = o, ent = e } end
						else
							return { kind = "entity", obj = o, ent = e }
						end
					end
				end
			end
		end
	end
	if liquid then return { kind = "node", pointed = liquid, node = core.get_node(liquid.under) } end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Pieces of information
-- ---------------------------------------------------------------------------------------------------------------------
local function mod_name(itemname)
	local m = itemname:match("^([^:]+):")
	if not m then return nil end
	if m:find("^mcl_") or m == "mcl" or m:find("^mobs_mc") or m:find("^mesecons") or m == "tsm_railcorridors" or m == "playerphysics" then return "Mineclonia" end
	if m == "__builtin" then return "Luanti" end
	return (m:gsub("^%l", string.upper))
end

local TOOL_NAME = { pickaxey = "Pickaxe", axey = "Axe", shovely = "Shovel", hoey = "Hoe", shearsy = "Shears", swordy = "Sword" }
local TIER = { [1] = "Wooden", [2] = "Golden", [3] = "Stone", [4] = "Iron", [5] = "Diamond", [6] = "Netherite" }

local function harvest_line(player, def)
	local name = player:get_player_name()
	if core.is_creative_enabled(name) then return nil end
	if def._mcl_hardness == -1 then return S("Unbreakable"), "unbreakable" end
	local g = def.groups or {}
	if (g.handy or 0) > 0 then return nil end -- anything breaks it
	local wield = player:get_wielded_item():get_definition()
	for group, tool in pairs(TOOL_NAME) do
		local need = g[group]
		if need and need > 0 then
			local tier = (need > 1) and (TIER[need] or "") or ""
			local label = (tier ~= "" and (tier .. " ") or "") .. tool
			local dg = wield and wield._mcl_diggroups and wield._mcl_diggroups[group]
			local ok = dg and (dg.level or 1) >= need
			return (ok and "✔ " or "✘ ") .. label, ok and "ok" or "bad"
		end
	end
	return nil
end

local function crop_growth(nodename)
	if not has_farming then return nil end
	for _, list in pairs(mcl_farming.plant_lists) do
		if list.full_grown == nodename then return 100 end
		for i, n in ipairs(list.names) do
			if n == nodename then return math.floor((i - 1) / #list.names * 100 + 0.5) end
		end
	end
end

local function block_details(node, pos)
	local out = {}
	local g = crop_growth(node.name)
	if g then out[#out + 1] = S("Growth: @1%", g) end
	local n = node.name
	local l = n:match("_(%d+)$")
	if n:find("cake", 1, true) and l then out[#out + 1] = S("Slices: @1", 7 - tonumber(l)) end
	if n:find("_active$") or n:find("_lit$") or n:find("lit_") then out[#out + 1] = S("Lit") end
	if n:find("_open$") or n:find("_open_") then out[#out + 1] = S("Open") elseif n:find("door") or n:find("trapdoor") or n:find("gate") then out[#out + 1] = S("Closed") end
	if n:find("repeater", 1, true) and l then out[#out + 1] = S("Delay: @1", tonumber(l)) end
	if n:find("noteblock", 1, true) then out[#out + 1] = S("Note: @1", node.param2) end
	local def = core.registered_nodes[n]
	local g2 = def and def.groups or {}
	if g2.honey_level then out[#out + 1] = S("Honey: @1", g2.honey_level) end
	if g2.composter then out[#out + 1] = S("Compost: @1", g2.composter) end
	if n:find("cauldron", 1, true) and l then out[#out + 1] = S("Level: @1", l) end
	return out
end

-- Light where a monster would stand (in front of the face you look at)
local function light_info(player, hitpos, cfg)
	local lines = {}
	local art = core.get_artificial_light(core.get_node(hitpos).param1)
	local day = core.get_natural_light(hitpos, 0.5) or 0
	local now = core.get_node_light(hitpos) or 0
	local mode = cfg.light_mode
	if mode == "light" then lines[#lines + 1] = S("Light: @1", art)
	elseif mode == "sky" then lines[#lines + 1] = S("Sky: @1", day)
	elseif mode == "both" then lines[#lines + 1] = S("Light: @1 · Sky: @2", art, day)
	elseif mode == "combined" then lines[#lines + 1] = S("Light: @1", now) end
	return lines, art, now
end

local DIM_LIGHT_LIMIT = { overworld = 0, nether = 11, ["end"] = 0 }
local function spawnable(pos, floor_pos, art, now)
	local function free(p) local d = core.registered_nodes[core.get_node(p).name]; return d and not d.walkable and d.liquidtype == "none" end
	if not (free(pos) and free(vector.offset(pos, 0, 1, 0))) then return false end
	local fd = core.registered_nodes[core.get_node(floor_pos).name]
	if not (fd and fd.walkable) then return false end
	local dim = mcl_worlds.pos_to_dimension(pos)
	if art > (DIM_LIGHT_LIMIT[dim] or 0) then return false end
	local lvl = now
	if has_weather and mcl_weather.get_weather and mcl_weather.get_weather() == "thunder" then lvl = math.max(art, lvl - 5) end
	return lvl <= 7
end

local function armor_points_entity(e)
	local pts = 0
	if e._tameful_stats then return e._tameful_stats.armor_points end
	if e.armor_list then for _, item in pairs(e.armor_list) do if item ~= "" then pts = pts + core.get_item_group(ItemStack(item):get_name(), "mcl_armor_points") end end end
	return pts
end

local function armor_points_player(p)
	if not has_armor then return 0 end
	local inv = mcl_util.get_inventory(p)
	local pts = 0
	if inv then for _, st in ipairs(inv:get_list("armor") or {}) do pts = pts + core.get_item_group(st:get_name(), "mcl_armor_points") end end
	return pts
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Build the panel for a target:  { key, lines = { {text, color?}... }, icon = itemname | nil, hidden = bool }
-- ---------------------------------------------------------------------------------------------------------------------
function id.describe(player, t, cfg)
	local lines, extra = {}, {}
	local info = { lines = lines }
	local function add(text, color, keep) lines[#lines + 1] = { text = text, color = color, keep = keep } end
	local idname, icon, display

	if t.kind == "node" then
		local n = t.node
		local def = core.registered_nodes[n.name] or {}
		display = first_line(def.description ~= "" and def.description or n.name)
		idname = n.name
		info.key = "node:" .. n.name
		info.title = S("Block: @1", display)
		icon = n.name
		if cfg.show_block_details then for _, l in ipairs(block_details(n, t.pointed.under)) do add(l) end end
		if cfg.show_harvest then local h, kind = harvest_line(player, def); if h then add(h, kind == "ok" and 0x55FF55 or 0xFF5555) end end
		if cfg.show_spawner and n.name:find("mobspawners:spawner", 1, true) then
			local mob = core.get_meta(t.pointed.under):get_string("Mob")
			if mob ~= "" then local md = mcl_mobs and mcl_mobs.registered_mobs[mob]; add(S("Spawns: @1", md and md.description or mob)) end
		end
		local lt = cfg.light_mode ~= "off" or cfg.show_spawnable
		if lt and t.pointed.above then
			local ls, art, now = light_info(player, t.pointed.above, cfg)
			local spawn = cfg.show_spawnable and spawnable(t.pointed.above, t.pointed.under, art, now)
			if #ls > 0 then add(ls[1] .. (spawn and ("  ! " .. S("Spawnable")) or ""), spawn and 0xFF5555 or nil)
			elseif spawn then add("! " .. S("Spawnable"), 0xFF5555) end
		end
	elseif t.kind == "item" then
		local st = ItemStack(t.ent.itemstring or "")
		idname = st:get_name()
		display = first_line(st:get_description())
		info.key = "item:" .. idname
		info.title = S("Item: @1 ×@2", display, st:get_count())
		icon = idname
	elseif t.kind == "player" then
		local pn = t.obj:get_player_name()
		idname = nil
		info.key = "player"
		info.title = S("Player: @1", pn)
		if cfg.show_player_health then
			add("♥ " .. math.floor(t.obj:get_hp() + 0.5) .. " / " .. (t.obj:get_properties().hp_max or 20))
			local a = armor_points_player(t.obj)
			if a > 0 then add(S("Armor: @1", a)) end
		end
	else -- entity
		local e = t.ent
		local mdef = mcl_mobs and mcl_mobs.registered_mobs[e.name]
		local nm = first_line(e.nametag)
		local kind = first_line(mdef and mdef.description or (core.registered_entities[e.name] and core.registered_entities[e.name].description) or e.name)
		display = (nm ~= "" and nm ~= kind) and nm or kind
		idname = e.name
		info.key = "entity:" .. e.name
		info.title = S("Entity: @1", display)
		local hp, mx = e.health, t.obj:get_properties().hp_max
		if cfg.show_health and hp and mx and e.is_mob then add("♥ " .. math.floor(hp + 0.5) .. " / " .. mx) end
		if cfg.show_armor and e.is_mob then local a = armor_points_entity(e); if a > 0 then add(S("Armor: @1", a)) end end
		if cfg.show_villager and e.name == "mobs_mc:villager" and not e.child and e._profession and e._profession ~= "" then
			if e._profession == "nitwit" then add(S("Nitwit"))
			else
				local prof = e._profession:gsub("^%l", string.upper)
				add(prof .. (e.get_tier_name and e._tier and (" · " .. e:get_tier_name(e._tier)) or ""))
			end
		end
		-- Mineclonia names a mob's spawn egg item exactly like the mob
		icon = core.registered_items[e.name] and e.name or nil
	end
	if idname and cfg.show_id then add(idname, 0xAAAAAA, true) end
	if idname and cfg.show_mod_name then local m = mod_name(idname); if m then add(m, 0x5555FF, true) end end
	info.icon = cfg.show_icon and icon and core.registered_items[icon] and icon or nil
	info.display = display
	return info
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Sample panels for the /idconfig preview: built with the same toggles and the same wording as id.describe.
-- ---------------------------------------------------------------------------------------------------------------------
id.SAMPLE_KINDS = { "block", "crop", "mob", "villager", "spawner", "item", "player" }
function id.sample(kind, cfg)
	local lines = {}
	local function add(text, color, keep) lines[#lines + 1] = { text = text, color = color, keep = keep } end
	local title, icon, idname
	local function light()
		if cfg.light_mode == "light" then add(S("Light: @1", 7))
		elseif cfg.light_mode == "sky" then add(S("Sky: @1", 12))
		elseif cfg.light_mode == "both" then add(S("Light: @1 · Sky: @2", 7, 12))
		elseif cfg.light_mode == "combined" then add(S("Light: @1", 12)) end
	end
	local function pick(...) for _, n in ipairs({ ... }) do if core.registered_items[n] then return n end end end
	if kind == "block" then
		title, idname = S("Block: @1", "Furnace"), "mcl_furnaces:furnace_active"
		icon = pick("mcl_furnaces:furnace_active", "mcl_furnaces:furnace", "mcl_core:stone")
		if cfg.show_block_details then add(S("Lit")) end
		if cfg.show_harvest then add("✔ " .. S("Stone Pickaxe"), 0x55FF55) end
		if cfg.light_mode ~= "off" or cfg.show_spawnable then
			local first = #lines + 1
			light()
			if cfg.show_spawnable then
				if lines[first] then lines[first].text = lines[first].text .. "  ! " .. S("Spawnable"); lines[first].color = 0xFF5555
				else add("! " .. S("Spawnable"), 0xFF5555) end
			end
		end
	elseif kind == "crop" then
		title, idname = S("Block: @1", "Wheat Crops"), "mcl_farming:wheat_5"
		icon = pick("mcl_farming:wheat_5", "mcl_farming:wheat_item", "mcl_core:dirt")
		if cfg.show_block_details then add(S("Growth: @1%", 57)) end
		light()
	elseif kind == "mob" then
		title, idname = S("Entity: @1", "Cow"), "mobs_mc:cow"
		icon = pick("mobs_mc:cow")
		if cfg.show_health then add("♥ 10 / 10") end
		if cfg.show_armor then add(S("Armor: @1", 2)) end
	elseif kind == "villager" then
		title, idname = S("Entity: @1", "Villager"), "mobs_mc:villager"
		icon = pick("mobs_mc:villager")
		if cfg.show_health then add("♥ 20 / 20") end
		if cfg.show_villager then add("Librarian · Expert") end
	elseif kind == "spawner" then
		title, idname = S("Block: @1", "Monster Spawner"), "mobspawners:spawner"
		icon = pick("mcl_mobspawners:spawner", "mcl_core:stone")
		if cfg.show_spawner then add(S("Spawns: @1", "Zombie")) end
	elseif kind == "item" then
		if not cfg.show_items then return { title = S("(dropped items are hidden)"), lines = {} } end
		title, idname = S("Item: @1 ×@2", "Diamond", 3), "mcl_core:diamond"
		icon = pick("mcl_core:diamond")
	else -- player
		title = S("Player: @1", "Steve")
		if cfg.show_player_health then add("♥ 20 / 20"); add(S("Armor: @1", 4)) end
	end
	if idname and cfg.show_id then add(idname, 0xAAAAAA, true) end
	if idname and cfg.show_mod_name then add("Mineclonia", 0x5555FF, true) end
	return { title = title, lines = lines, icon = cfg.show_icon and icon or nil }
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Breaking progress. The server does not see the client's mining progress, so it is estimated: how long the dig key has been held on
-- the same node, against the dig time of the item in hand (empty hand = Mineclonia's per-player "hand" item).
-- ---------------------------------------------------------------------------------------------------------------------
function id.dig_time(player, pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	if not def then return nil end
	local tool = player:get_wielded_item()
	if tool:is_empty() then
		local inv = player:get_inventory()
		if inv:get_size("hand") > 0 then tool = inv:get_stack("hand", 1) end
	end
	local p = core.get_dig_params(def.groups, tool:get_tool_capabilities(), tool:get_wear())
	if p and p.diggable then return p.time end
	return nil
end

-- s = per-player state; returns the progress 0..1 or nil (nothing to show). Restarts when the node changes or the key is released.
function id.dig_step(s, dtime, digging, pos, need)
	if not digging or not pos or not need or need <= 0 then s.dig = nil; return nil end
	if not s.dig or not vector.equals(s.dig.pos, pos) then s.dig = { pos = vector.new(pos), t = 0 } end
	s.dig.t = s.dig.t + dtime
	return math.min(1, s.dig.t / need)
end
