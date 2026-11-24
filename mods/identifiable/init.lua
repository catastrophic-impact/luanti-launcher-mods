-- Identifiable (Luanti/Mineclonia port of the Fabric mod; original Luanti mod by Twinsonian): a panel naming what you look at.
identifiable = {}
local path = core.get_modpath("identifiable")
dofile(path .. "/settings.lua")
dofile(path .. "/info.lua")
dofile(path .. "/hud.lua")
dofile(path .. "/ui.lua")
dofile(path .. "/main.lua")
core.log("action", "[identifiable] loaded")
