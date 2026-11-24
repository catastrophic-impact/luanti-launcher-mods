-- HQ (Luanti/Mineclonia port of the Fabric HQ mod): shortcuts list, own commands, quick buttons, mini buttons in the inventory.
hq = { shortcuts = {}, order = {} }
local path = core.get_modpath("hq")
dofile(path .. "/api.lua")
dofile(path .. "/village.lua")
dofile(path .. "/ui.lua")
dofile(path .. "/inventory.lua")
core.log("action", "[hq] loaded")
