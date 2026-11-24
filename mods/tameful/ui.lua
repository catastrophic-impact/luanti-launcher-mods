-- /tameful screen: left = your pets (list, picture, details, buttons), right = settings.
local S = core.get_translator("tameful")
local roster = tameful.roster
local msg, esc = tameful.msg, core.formspec_escape
local cfg = tameful.cfg

local selected = {}  -- selected[pname] = index into sorted ids
local confirm = {}   -- confirm[pname] = id being released

local function state_text(rec)
	if rec.status == "downed" then
		local n = tameful.ready_in(rec)
		return n > 0 and S("Downed, ready in @1 s", n) or S("Downed, recovered (in the stable)")
	elseif rec.status == "stabled" then
		return S("In the stable")
	end
	return rec.loaded and S("In the world, nearby") or S("Away (not nearby)")
end

local function model_element(rec, x, y, w, h)
	x, y, w, h = x or 0.7, y or 4.4, w or 3.0, h or 3.0
	local mesh, tex, frame0 = rec.mesh, rec.textures, rec.anim_frame or 0
	if not mesh or not tex then
		local def = mcl_mobs.registered_mobs[rec.kind]
		local props = def and (def.initial_properties or def)
		mesh = props and props.mesh
		tex = def and def.texture_list and def.texture_list[1]
		frame0 = def and def.animation and def.animation.stand_start or 0
	end
	if not mesh or not tex then return "" end
	if type(tex) == "string" then tex = { tex } end
	local parts = {}
	for _, t in ipairs(tex) do parts[#parts + 1] = esc(t) end
	-- Fixed pose (stand frame), not spinning; drag with the mouse to turn the animal.
	return string.format("box[%.2f,%.2f;%.2f,%.2f;#00000040]model[%.2f,%.2f;%.2f,%.2f;preview;", x, y, w, h, x, y, w, h) .. esc(mesh) .. ";"
		.. table.concat(parts, ",") .. ";-8,160;false;true;" .. frame0 .. "," .. frame0 .. ";0]"
end

-- Layout (window 17 x 10.8): left pane x 0.4..8.8, right pane x 9.0..16.6, Close centered at the bottom.
local PANE_Y, PANE_H = 0.4, 9.2

local function settings_pane(pname)
	local can = tameful.can_edit_settings(pname)
	local t = {
		uikit.panel(9.0, PANE_Y, 7.6, PANE_H),
		"label[9.3,0.9;", esc(S("Settings")), "]",
		uikit.rule(9.3, 1.2, 7.0),
	}
	local rows = {
		{ "consume_lead", S("Use up the lead"), "bool" },
		{ "immortal", S("Pets are downed, not killed"), "bool" },
		{ "regen_health", S("Pets heal over time"), "bool" },
		{ "show_name", S("Show the pet's name"), "bool" },
		{ "show_health", S("Show its health"), "bool" },
		{ "show_owner", S("Show its owner"), "bool" },
		{ "max_tames", S("Max pets per player"), "int" },
		{ "max_summoned", S("Max pets out at once"), "int" },
		{ "downed_seconds", S("Recovery time (seconds)"), "int" },
		{ "follow_teleport", S("Follow teleport distance"), "int" },
	}
	local y = 1.6
	for _, r in ipairs(rows) do
		local key, label, kind = r[1], r[2], r[3]
		if kind == "bool" then
			if can then
				t[#t + 1] = uikit.toggle(9.3, y, 7.0, 0.58, "s_" .. key, label, cfg.get(key))
			else
				t[#t + 1] = string.format("label[9.3,%.2f;%s: %s]", y + 0.35, esc(label), cfg.get(key) and esc(S("on")) or esc(S("off")))
			end
		else
			if can then
				t[#t + 1] = string.format("label[9.3,%.2f;%s]", y + 0.3, esc(label))
				t[#t + 1] = uikit.field(14.4, y, 1.9, 0.6, "s_" .. key, tostring(cfg.get(key)), true)
			else
				t[#t + 1] = string.format("label[9.3,%.2f;%s: %s]", y + 0.35, esc(label), esc(tostring(cfg.get(key))))
			end
		end
		y = y + 0.66
	end
	if can then
		t[#t + 1] = string.format("label[9.3,%.2f;%s]", y + 0.45, esc(S("0 means no limit.")))
		t[#t + 1] = string.format("button[13.3,%.2f;3.0,0.7;save_settings;%s]", y + 0.15, esc(S("Save")))
	else
		t[#t + 1] = string.format("label[9.3,%.2f;%s]", y + 0.2, esc(S("Only the world owner or an operator can change these.")))
	end
	return table.concat(t)
end

local function roster_formspec(pname)
	local ids = tameful.sorted_ids(pname)
	local items = {}
	for _, id in ipairs(ids) do
		local rec = roster[pname][id]
		items[#items + 1] = esc(rec.name .. "  -  " .. state_text(rec))
	end
	local sel = selected[pname] or 0
	if sel > #ids then sel = 0 end
	local rec = ids[sel] and roster[pname][ids[sel]]

	local player = core.get_player_by_name(pname)
	local H, G, LX, LW = uikit.row_h, uikit.gap, 0.7, 7.8
	local t = {
		uikit.begin(player, 17, 10.8),
		uikit.title(17, S("Pets"), 0),
		uikit.panel(0.4, PANE_Y, 8.4, PANE_H),
		"label[0.7,0.9;", esc(S("Your pets (@1)", #ids)), "]",
		uikit.rule(LX, 1.2, LW),
		"set_focus[pets;true]textlist[0.7,1.4;7.8,2.8;pets;", table.concat(items, ","), ";", tostring(sel), ";false]",
	}
	if rec then
		t[#t + 1] = model_element(rec)
		local hp = rec.hp and string.format("%d / %d", math.floor(rec.hp + 0.5), rec.hp_max or 0) or "?"
		t[#t + 1] = "label[3.95,4.75;" .. esc(table.concat({
			S("Name: @1", rec.name),
			S("Kind: @1", tameful.kind_description(rec.kind)),
			S("Health: @1", hp),
			S("Mode: @1", tameful.mode_label(rec.order)),
			S("State: @1", state_text(rec)),
		}, "\n")) .. "]"
		local nc = uikit.cols(LX, LW, G, { 1, "2.7" })        -- name field | Rename
		t[#t + 1] = uikit.field(nc[1].x, 7.65, nc[1].w, H, "newname", rec.name)
		t[#t + 1] = string.format("button[%.2f,7.65;%.2f,%.2f;rename;%s]", nc[2].x, nc[2].w, H, esc(S("Rename")))
		local bc = uikit.cols(LX, LW, G, { 1, 1.35, 1.5, 0.85, 1.1 })  -- five actions, one row on the panel's inner bottom edge (wider where the label is longer)
		local acts = { { "button", "stable", S("Stable") }, { "button", "resummon", S("Resummon") }, { "button", "toggle", S("Follow/Stay") },
			{ "button_exit", "ride", S("Ride") }, { "button", "release", S("Release") } }
		for i, a in ipairs(acts) do
			t[#t + 1] = string.format("%s[%.2f,%.2f;%.2f,%.2f;%s;%s]", a[1], bc[i].x, 9.3 - H, bc[i].w, H, a[2], esc(a[3]))
		end
		t[#t + 1] = string.format("button[%.2f,7.0;3.8,0.6;petwin;%s]", LX + LW - 3.8, esc(S("Pet window")))
	else
		t[#t + 1] = "label[0.7,5.2;" .. esc(S("No pet selected.")) .. "]"
		t[#t + 1] = "label[0.7,5.7;" .. esc(S("Right-click an animal with a lead to tame it.")) .. "]"
	end
	t[#t + 1] = settings_pane(pname)
	t[#t + 1] = "button_exit[7.0,9.85;3.0,0.7;close;" .. esc(S("Close")) .. "]"
	return table.concat(t)
end

function tameful.show_roster(pname)
	core.show_formspec(pname, "tameful:roster", roster_formspec(pname))
end

core.register_chatcommand("tameful", {
	description = S("Show your pets"),
	func = function(name) tameful.show_roster(name); return true end,
})

tameful.model_element = model_element
tameful.state_text = state_text

function tameful.ask_release(pname, id)
	local rec = roster[pname] and roster[pname][id]
	if not rec then return end
	confirm[pname] = id
	local player = core.get_player_by_name(pname)
	local bc = uikit.cols(0.5, 7.0, uikit.gap + 0.1, 2)
	core.show_formspec(pname, "tameful:release", table.concat({
		uikit.begin(player, 8, 3.6),
		uikit.panel(0.2, 0.2, 7.6, 3.2),
		"label[0.5,0.8;", esc(S("Release @1 for good?", rec.name)), "]",
		"label[0.5,1.5;", esc(S("It will be wild again.")), "]",
		string.format("button_exit[%.2f,2.3;%.2f,%.2f;yes;%s]", bc[1].x, bc[1].w, uikit.row_h, esc(S("Release"))),
		string.format("button_exit[%.2f,2.3;%.2f,%.2f;no;%s]", bc[2].x, bc[2].w, uikit.row_h, esc(S("Cancel"))),
	}))
end

local function apply_settings(pname, fields)
	if not tameful.can_edit_settings(pname) then return end
	for key, default in pairs(cfg.defaults) do
		local f = fields["s_" .. key]
		if f ~= nil then
			if type(default) == "boolean" then
				-- a toggle button sends its label when clicked: flip the value ("true"/"false" still set it directly)
				if f == "true" then cfg.set(key, true) elseif f == "false" then cfg.set(key, false) else cfg.set(key, not cfg.get(key)) end
			elseif fields.save_settings then
				local n = tonumber(f)
				if n then cfg.set(key, math.max(0, math.floor(n))) end
			end
		end
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	local pname = player:get_player_name()
	if formname == "tameful:tame" then
		local obj = tameful._pending[pname]
		tameful._pending[pname] = nil
		if fields.yes and obj and obj:is_valid() then
			local ent = obj:get_luaentity()
			local near = vector.distance(obj:get_pos(), player:get_pos()) < 8
			local holds = player:get_wielded_item():get_name() == "tameful:lead"
			if ent and not ent.tamed and near and (holds or core.is_creative_enabled(pname)) then
				tameful._do_tame(ent, player)
			end
		end
		return true
	elseif formname == "tameful:release" then
		local id = confirm[pname]
		confirm[pname] = nil
		if fields.yes and id and roster[pname] and roster[pname][id] then
			local rec = roster[pname][id]
			local name = rec.name
			tameful.release(pname, id)
			selected[pname] = nil
			msg(pname, S("@1 was released.", name))
		end
		tameful.show_roster(pname)
		return true
	elseif formname == "tameful:roster" then
		local ids = tameful.sorted_ids(pname)
		if fields.pets then
			local ev = core.explode_textlist_event(fields.pets)
			if ev.type == "CHG" or ev.type == "DCL" then selected[pname] = ev.index end
		end
		apply_settings(pname, fields)
		local id = ids[selected[pname] or 0]
		local rec = id and roster[pname][id]
		if fields.stable and rec then
			if rec.status ~= "out" then
				msg(pname, S("@1 is already in the stable.", rec.name))
			elseif tameful.stable(id, false) then
				msg(pname, S("@1 is now in the stable.", rec.name))
			else
				msg(pname, S("@1 cannot be stabled right now.", rec.name))
			end
		elseif fields.resummon and rec then
			local ok, why = tameful.resummon(id, player)
			if ok then msg(pname, S("@1 is back with you.", rec.name))
			elseif why then msg(pname, why) end
		elseif fields.toggle and rec then
			local ent = tameful.find_loaded(id)
			if ent then tameful.toggle_order(ent, pname) else msg(pname, S("That pet is not in the world.")) end
		elseif fields.ride and rec then
			local ent = tameful.find_loaded(id)
			if not ent then
				msg(pname, S("That pet is not in the world."))
			else
				local ok, why = tameful.ride(ent, player)
				if not ok and why then msg(pname, why) end
			end
			return true
		elseif fields.rename and rec and fields.newname then
			local name = fields.newname:gsub("[%c]", ""):sub(1, 32)
			if name ~= "" then
				rec.name = name
				local ent = tameful.find_loaded(id)
				if ent then tameful.refresh_tag(ent) end
				tameful.save()
			end
		elseif fields.petwin and rec then
			local ent = tameful.find_loaded(id)
			if ent and vector.distance(ent.object:get_pos(), player:get_pos()) < 8 then
				tameful.show_pet(pname, ent)
				return true
			end
			msg(pname, S("The pet window needs the pet to be close to you."))
		elseif fields.release and rec then
			tameful.ask_release(pname, id)
			return true
		end
		if not fields.quit then tameful.show_roster(pname) end
		return true
	end
end)

core.register_on_leaveplayer(function(player)
	local pname = player:get_player_name()
	selected[pname] = nil
	confirm[pname] = nil
end)

tameful._roster_formspec = roster_formspec
tameful._select = function(pname, index) selected[pname] = index end
