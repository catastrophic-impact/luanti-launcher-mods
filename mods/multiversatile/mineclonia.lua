-- Mineclonia's three dimensions, registered with the SAME extents mcl_worlds.y_to_layer uses, and a wrap of that function so
-- dimensions added by other mods are seen by Mineclonia's callers (pos_to_dimension, has_weather, beds, ...) by their own name.
-- Listed in patches/MINECLONIA_CHANGES.md (multiversatile).
local v = mcl_vars
local function reg(def) local err = multiversatile.register(def); if err then error("[multiversatile] " .. def.name .. ": " .. err) end end

reg{ name = "overworld", mineclonia = true, ymin = v.mg_overworld_min, ymax = v.mapgen_edge_max,
	build_max = v.mg_overworld_max_official } -- Mineclonia has no top for the Overworld; building stops at its official height
reg{ name = "nether", mineclonia = true, ymin = v.mg_nether_min, ymax = v.mg_nether_max + 128,
	build_max = v.mg_nether_max }
reg{ name = "end", mineclonia = true, ymin = v.mg_end_min, ymax = v.mg_end_max,
	build_max = v.mg_end_max_official }

-- Our own dimensions answer first; Mineclonia's three keep Mineclonia's own result (layer numbers included).
local orig = mcl_worlds.y_to_layer
function mcl_worlds.y_to_layer(y)
	local d = multiversatile.at_y(y)
	if d and not d.mineclonia then return y - d.ymin, d.name end
	return orig(y)
end

-- Mineclonia's void code (mcl_void_damage: players respawned/hurt, entities removed; mcl_death_drop) uses is_in_void, which only knows
-- Mineclonia's own bands. Positions inside a dimension of ours are not void.
local orig_void = mcl_worlds.is_in_void
function mcl_worlds.is_in_void(pos)
	local d = multiversatile.at_y(pos.y)
	if d and not d.mineclonia then return false, false end
	return orig_void(pos)
end
