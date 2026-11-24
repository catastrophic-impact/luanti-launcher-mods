-- HQ button + mini buttons inside Mineclonia's inventory formspecs (survival and creative), without patching Mineclonia:
-- every inventory formspec Mineclonia sets goes through mcl_player.set_inventory_formspec; we append our elements to it.
local S = core.get_translator("hq")
local esc = core.formspec_escape

-- Layout per inventory size (the formspec is 11.75 x 10.9 in survival, 13 x 11.43 in creative); y < 0 = above the panel.
local function elements(player, w, creative)
	local d = hq.get(player)
	local btns = { { name = "hq_open", label = "HQ", tip = S("HQ: shortcuts and quick buttons") } }
	local shown = 0
	for _, id in ipairs(hq.order) do
		local sc = hq.shortcuts[id]
		if shown < d.minis and hq.mini_on(d, sc) then
			shown = shown + 1
			local icon, short = hq.picture_of(d, sc)
			btns[#btns + 1] = { name = "hq_mini_" .. id, icon = icon, label = short, tip = sc.name .. (sc.command and (" - /" .. sc.command) or "") }
		end
	end
	local size, gap = 0.9, 0.1
	local total = #btns * size + (#btns - 1) * gap
	-- Survival: one row centered above the panel. Creative: its own tab row is full across the top, so a column left of the panel.
	-- (The first element is a throwaway: creative ends its formspec with a stray "p<page>" that would swallow the next element's name.)
	local t = { "box[0,0;0,0;#00000000]style_type[button,item_image_button;noclip=true]" }
	for i, b in ipairs(btns) do
		local bx, y
		if creative then
			bx, y = -1.1, 0.2 + (i - 1) * (size + gap)
		else
			bx, y = (w - total) / 2 + (i - 1) * (size + gap), -1.35
		end
		if b.icon then
			t[#t + 1] = string.format("item_image_button[%.2f,%.2f;%.2f,%.2f;%s;%s;]", bx, y, size, size, b.icon, b.name)
		else
			t[#t + 1] = string.format("button[%.2f,%.2f;%.2f,%.2f;%s;%s]", bx, y, size, size, b.name, esc(b.label))
		end
		t[#t + 1] = string.format("tooltip[%s;%s]", b.name, esc(b.tip))
	end
	return table.concat(t)
end

local orig = mcl_player.set_inventory_formspec
mcl_player.set_inventory_formspec = function(player, formspec, priority)
	if priority == 0 and type(formspec) == "string" then
		local w = tonumber(formspec:match("size%[([%d%.]+),"))
		if w and not formspec:find("hq_open", 1, true) then formspec = formspec .. elements(player, w, formspec:find("^formspec_version%[%d+%]size%[13,") ~= nil) end
	end
	return orig(player, formspec, priority)
end

function hq.refresh_inventory(player)
	if mcl_inventory and mcl_inventory.update_inventory_formspec then mcl_inventory.update_inventory_formspec(player) end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	for k in pairs(fields) do if k:find("^hq_") then core.log("action", "[hq] button '" .. k .. "' formname='" .. formname .. "'") end end
	if formname ~= "" then return end
	if fields.hq_open then
		-- Replacing the open inventory formspec directly flashes and closes again: close it first, then open HQ a moment later.
		local pname = player:get_player_name()
		core.close_formspec(pname, "")
		core.after(0.1, function() hq.show(pname) end)
		return
	end
	for k in pairs(fields) do
		local id = k:match("^hq_mini_(.+)$")
		if id and hq.shortcuts[id] then
			-- same as the HQ button: a formspec opened in the same tick as the inventory closes is lost, so wait a moment
			local pname, sc = player:get_player_name(), hq.shortcuts[id]
			core.close_formspec(pname, "")
			core.after(0.1, function()
				local p = core.get_player_by_name(pname)
				if p then hq.run_shortcut(p, sc) end
			end)
			return
		end
	end
end)

-- Inventory formspecs set before HQ loaded / for players already online are rebuilt when they join.
core.register_on_joinplayer(function(player) core.after(0.5, function() if player:is_player() then hq.refresh_inventory(player) end end) end)
