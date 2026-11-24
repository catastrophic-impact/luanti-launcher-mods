-- Tameful (Luanti/Mineclonia port)
tameful = { storage = core.get_mod_storage() }
local path = core.get_modpath("tameful")
dofile(path .. "/settings.lua")
dofile(path .. "/roster.lua")
dofile(path .. "/stats.lua")
dofile(path .. "/combat.lua")
dofile(path .. "/pets.lua")
dofile(path .. "/riding.lua")
dofile(path .. "/leftovers.lua")
dofile(path .. "/ui.lua")
dofile(path .. "/petwindow.lua")
core.log("action", "[tameful] loaded")
if core.get_modpath("hq") then
	hq.register_shortcut({ id = "tameful", name = "Tameful", command = "tameful", icon = "tameful:lead", short = "TM" })
end
