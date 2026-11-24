-- Populations: villagers are people (Mineclonia port of the Fabric mod).
populations = {}
local modpath = core.get_modpath("populations")
populations.names = dofile(modpath .. "/names.lua")
dofile(modpath .. "/settings.lua")
dofile(modpath .. "/people.lua")
dofile(modpath .. "/combat.lua")
dofile(modpath .. "/zombie.lua")
if core.get_modpath("hq") then
	hq.register_shortcut({ id = "populations", name = "Populations", command = "pop", icon = "mcl_core:emerald", short = "PO" })
end
