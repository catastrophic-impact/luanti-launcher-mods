-- Pet window (right-click a pet with a stick): the pet's picture, numbers and stats on the left; name, mode and actions on the right.
local S = core.get_translator("tameful")
local roster = tameful.roster
local msg, esc = tameful.msg, core.formspec_escape

local current = {} -- current[pname] = pet id

local WEAPON_NAME = { wood = "Wooden sword", stone = "Stone sword", iron = "Iron sword", diamond = "Diamond sword", netherite = "Netherite sword" }
local ARMOR_NAME = { leather = "Leather", chain = "Chain", iron = "Iron", diamond = "Diamond", netherite = "Netherite" }

local H, G = uikit.row_h, uikit.gap
local RX, RW = 9.3, 7.0   -- right pane content (panel 9.0..16.6)

-- A group of buttons across the right pane: one per entry { key, label, selected }. The selected one gets the "active" look and a dot.
local function group(y, items, prefix)
	local cols = uikit.cols(RX, RW, G, #items)
	local out = {}
	for i, it in ipairs(items) do
		local name = (prefix or "") .. it[1]
		if it[3] then out[#out + 1] = uikit.active(name) end
		out[#out + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;%s;%s]", cols[i].x, y, cols[i].w, H, name, esc((it[3] and "● " or "") .. it[2]))
	end
	return table.concat(out)
end

local function formspec(pname, ent)
	local id = ent._tameful_id
	local rec = tameful.find_record(id)
	if not rec then return nil end
	local player = core.get_player_by_name(pname)
	local st = ent._tameful_stats or tameful.stats_for(ent.name)
	local hpmax = ent.object:get_properties().hp_max
	local jump = st.jump == "fly" and S("Flies") or S("@1 block(s)", st.jump)
	local order, att = tameful.mode_of(ent.order), ent._tameful_attitude or "defensive"
	local nc = uikit.cols(RX, RW, G, { 1, "2.2" })          -- name field | Rename
	local wc = uikit.cols(RX, RW, G, 2)                      -- wander | range
	local ac = uikit.cols(RX, RW, G, 3)                      -- ride | stable | release
	local bc = uikit.cols(RX, RW, G, 2)                      -- pets list | done
	local t = {
		uikit.begin(player, 17, 10.8),
		uikit.title(17, S("Pet"), 0),
		uikit.panel(0.4, 0.4, 8.4, 9.2),
		uikit.panel(9.0, 0.4, 7.6, 9.2),
		"label[0.7,0.9;", esc(rec.name), "]",
		uikit.rule(0.7, 1.2, 7.8),
		tameful.model_element(rec, 0.7, 1.5, 3.4, 3.6),
		"label[4.4,1.9;", esc(table.concat({
			S("Kind: @1", tameful.kind_description(rec.kind)),
			S("Health: @1 / @2", math.floor(ent.health + 0.5), hpmax),
			S("Mode: @1", tameful.mode_label(ent.order)),
			S("Saddle: @1", (ent.saddle == "yes" or (type(ent._saddle) == "string" and ent._saddle ~= "")) and S("yes") or S("no")),
		}, "\n")), "]",
		uikit.rule(0.7, 5.4, 7.8),
		"label[0.7,5.8;", esc(S("Stats")), "]",
		"label[0.7,6.3;", esc(table.concat({
			S("Mount speed: @1 blocks/second", tameful.mount_speed(ent)),
			S("Mount jump: @1", jump),
			S("Attack: @1 (@2)", st.attack, S(WEAPON_NAME[st.weapon])),
			S("Armor: @1 (@2 points)", S(ARMOR_NAME[st.armor]), st.armor_points),
			S("Crit chance: @1%", st.crit),
		}, "\n")), "]",
		-- right pane: every row spans RX..RX+RW
		"label[", RX, ",0.9;", esc(S("Name")), "]",
		uikit.field(nc[1].x, 1.15, nc[1].w, H, "newname", rec.name),
		string.format("button[%.2f,1.15;%.2f,%.2f;rename;%s]", nc[2].x, nc[2].w, H, esc(S("Rename"))),
		"label[", RX, ",2.35;", esc(S("Mode")), "]",
		group(2.6, { { "follow", S("Follow"), order == "follow" }, { "stay", S("Stay"), order == "stay" }, { "relax", S("Relax"), order == "relax" } }),
		"label[", RX, ",3.8;", esc(S("Attitude")), "]",
		group(4.05, { { "passive", S("Passive"), att == "passive" }, { "defensive", S("Defensive"), att == "defensive" }, { "aggressive", S("Aggressive"), att == "aggressive" } }, "att_"),
		string.format("button[%.2f,5.25;%.2f,%.2f;wander;%s]", wc[1].x, wc[1].w, H, esc(S("Wander: @1", ent._tameful_wander or 12))),
		string.format("button[%.2f,5.25;%.2f,%.2f;range;%s]", wc[2].x, wc[2].w, H, esc(S("Range: @1", ent._tameful_range or 16))),
		"tooltip[wander;", esc(S("How far a relaxing pet roams")), "]tooltip[range;", esc(S("How far an aggressive pet looks for enemies")), "]",
		string.format("button_exit[%.2f,6.25;%.2f,%.2f;ride;%s]", ac[1].x, ac[1].w, H, esc(S("Ride"))),
		string.format("button_exit[%.2f,6.25;%.2f,%.2f;stable;%s]", ac[2].x, ac[2].w, H, esc(S("Stable"))),
		string.format("button[%.2f,6.25;%.2f,%.2f;release;%s]", ac[3].x, ac[3].w, H, esc(S("Release"))),
		ent.generate_inventory_formspec and string.format("button_exit[%.2f,7.25;%.2f,%.2f;inventory;%s]", RX, RW, H, esc(S("Inventory (saddle, armor, chest)"))) or "",
		string.format("button[%.2f,%.2f;%.2f,%.2f;back;%s]", bc[1].x, 9.3 - H, bc[1].w, H, esc(S("Pets list"))),
		string.format("button_exit[%.2f,%.2f;%.2f,%.2f;close;%s]", bc[2].x, 9.3 - H, bc[2].w, H, esc(S("Done"))),
	}
	return table.concat(t)
end

function tameful.show_pet(pname, ent)
	if not ent or not ent._tameful_id then return end
	current[pname] = ent._tameful_id
	local fs = formspec(pname, ent)
	if fs then core.show_formspec(pname, "tameful:pet", fs) end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "tameful:pet" then return end
	local pname = player:get_player_name()
	local id = current[pname]
	local rec = id and roster[pname] and roster[pname][id]
	local ent = id and tameful.find_loaded(id)
	if not rec or not ent or ent.owner ~= pname then
		if rec and not ent then msg(pname, S("That pet is not in the world.")) end
		return true
	end
	if fields.rename and fields.newname then
		local name = fields.newname:gsub("[%c]", ""):sub(1, 32)
		if name ~= "" then
			rec.name = name
			tameful.refresh_tag(ent)
			tameful.save()
		end
	elseif fields.follow then tameful.set_mode(ent, "follow")
	elseif fields.stay then tameful.set_mode(ent, "stay")
	elseif fields.relax then tameful.set_mode(ent, "relax")
	elseif fields.att_passive then tameful.set_attitude(ent, "passive")
	elseif fields.att_defensive then tameful.set_attitude(ent, "defensive")
	elseif fields.att_aggressive then tameful.set_attitude(ent, "aggressive")
	elseif fields.wander then ent._tameful_wander = tameful.cycle(tameful.WANDERS, ent._tameful_wander, 12)
	elseif fields.range then ent._tameful_range = tameful.cycle(tameful.RANGES, ent._tameful_range, 16)
	elseif fields.ride then
		local ok, why = tameful.ride(ent, player)
		if not ok and why then msg(pname, why) end
		return true
	elseif fields.inventory then
		-- Mineclonia shows an animal's inventory only as the player's own inventory while mounted: mount it, then open that.
		local ok, why = true, nil
		if ent.driver ~= player then ok, why = tameful.ride(ent, player) end
		if not ok and why then msg(pname, why)
		else core.after(0.3, function() if player:is_valid() then core.show_formspec(pname, "", player:get_inventory_formspec()) end end) end
		return true
	elseif fields.stable then
		if tameful.stable(id, false) then msg(pname, S("@1 is now in the stable.", rec.name)) end
		return true
	elseif fields.release then
		tameful.ask_release(pname, id)
		return true
	elseif fields.back then
		tameful.show_roster(pname)
		return true
	elseif fields.quit then
		return true
	end
	if not fields.quit then tameful.show_pet(pname, ent) end
	return true
end)

core.register_on_leaveplayer(function(p) current[p:get_player_name()] = nil end)
tameful._pet_formspec = formspec
